import { NextRequest, NextResponse } from "next/server";

import { CURATED_RESOURCES, getSscpDomain } from "@/lib/sscp/catalog";
import { buildFallbackDrill, inferConfidenceLevel, sortCitations } from "@/lib/sscp/engine";
import { loadCachedImportedNotes } from "@/lib/sscp/notes";
import { createStructuredResponse, hasOpenAIConfig } from "@/lib/sscp/openai";
import { DrillRequest, DrillResponse, QuestionAnswerLens, QuestionBlueprint, SourceCitation } from "@/lib/sscp/types";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

const questionSchema = {
  type: "object",
  additionalProperties: false,
  required: ["questions", "missedConcepts", "recommendedNextTask"],
  properties: {
    missedConcepts: {
      type: "array",
      items: { type: "string" },
      maxItems: 6,
    },
    recommendedNextTask: { type: "string" },
    questions: {
      type: "array",
      minItems: 1,
      maxItems: 20,
      items: {
        type: "object",
        additionalProperties: false,
        required: [
          "id",
          "format",
          "title",
          "prompt",
          "domainIds",
          "objectiveIds",
          "difficulty",
          "difficultyLabel",
          "scenarioContext",
          "idealAnswer",
          "options",
          "correctOptionIds",
          "optionRationales",
          "answerGuidance",
          "answerKeyPhrases",
          "strategicTakeaway",
          "answerLenses",
        ],
        properties: {
          id: { type: "string" },
          format: {
            type: "string",
            enum: ["single_select", "multi_select", "short_answer", "scenario"],
          },
          title: { type: "string" },
          prompt: { type: "string" },
          domainIds: {
            type: "array",
            items: { type: "string" },
            minItems: 1,
          },
          objectiveIds: {
            type: "array",
            items: { type: "string" },
            minItems: 1,
          },
          difficulty: {
            type: "string",
            enum: ["foundation", "pressure", "bridge"],
          },
          difficultyLabel: { type: "string" },
          scenarioContext: { anyOf: [{ type: "string" }, { type: "null" }] },
          idealAnswer: { type: "string" },
          options: {
            anyOf: [
              {
                type: "array",
                items: {
                  type: "object",
                  additionalProperties: false,
                  required: ["id", "label", "text"],
                  properties: {
                    id: { type: "string" },
                    label: { type: "string" },
                    text: { type: "string" },
                  },
                },
              },
              { type: "null" },
            ],
          },
          correctOptionIds: {
            anyOf: [
              {
                type: "array",
                items: { type: "string" },
              },
              { type: "null" },
            ],
          },
          optionRationales: {
            anyOf: [
              {
                type: "array",
                items: {
                  type: "object",
                  additionalProperties: false,
                  required: ["optionId", "rationale"],
                  properties: {
                    optionId: { type: "string" },
                    rationale: { type: "string" },
                  },
                },
              },
              { type: "null" },
            ],
          },
          answerGuidance: {
            type: "array",
            items: { type: "string" },
            minItems: 1,
          },
          answerKeyPhrases: {
            type: "array",
            items: { type: "string" },
            minItems: 1,
          },
          strategicTakeaway: { type: "string" },
          answerLenses: {
            type: "array",
            minItems: 3,
            maxItems: 3,
            items: {
              type: "object",
              additionalProperties: false,
              required: ["level", "title", "answer", "explanation", "focus"],
              properties: {
                level: {
                  type: "string",
                  enum: ["sscp", "cissp", "cto"],
                },
                title: { type: "string" },
                answer: { type: "string" },
                explanation: { type: "string" },
                focus: { type: "string" },
              },
            },
          },
        },
      },
    },
  },
} as const;

function bad(error: string, status = 400) {
  return NextResponse.json({ ok: false, error }, { status });
}

function formatTitle(format: QuestionBlueprint["format"], index: number) {
  const label =
    format === "single_select"
      ? "Best-answer question"
      : format === "multi_select"
        ? "Multi-select question"
        : format === "scenario"
          ? "Scenario question"
          : "Short-answer question";
  return `Question ${index + 1} · ${label}`;
}

function stripVisibleMetadata(text?: string | null) {
  if (!text) return "";

  return text
    .replace(/^you need to think across[^.]*\.\s*/i, "")
    .replace(/^keep the reasoning centered on[^.]*\.\s*/i, "")
    .replace(/^treat the prompt like[^.]*\.\s*/i, "")
    .replace(/study-book anchor:[\s\S]*$/i, "")
    .replace(/trusted anchor:[^.]*\.?/gi, "")
    .replace(/pdf anchor:[^.]*\.?/gi, "")
    .replace(/objective focus:[^.]*\.?/gi, "")
    .replace(/active domains?:[^.]*\.?/gi, "")
    .replace(/\([^)]*\.pdf[^)]*\)/gi, "")
    .replace(/\b[^.\n]*\.pdf\b/gi, "")
    .replace(/\s{2,}/g, " ")
    .trim();
}

function sanitizeTitle(title: string | undefined, format: QuestionBlueprint["format"], index: number) {
  const cleaned = stripVisibleMetadata(title);
  if (!cleaned) {
    return formatTitle(format, index);
  }

  if (
    cleaned.length > 90 ||
    /(anchor|objective focus|active domain|trusted|\.pdf\b|best-answer drill|layered controls check|cross-domain scenario|concise explanation)/i.test(
      cleaned,
    )
  ) {
    return formatTitle(format, index);
  }

  return cleaned;
}

/**
 * Force alternating single_select / multi_select regardless of what the AI returned.
 * Even index (0, 2, 4…) → single_select with exactly 1 correctOptionId.
 * Odd  index (1, 3, 5…) → multi_select  with exactly 2 correctOptionIds.
 * This is applied after the AI call so the distribution is deterministic.
 */
function enforceFormatDistribution(
  questions: QuestionBlueprint[],
): QuestionBlueprint[] {
  return questions.map((question, index) => {
    const forcedFormat: QuestionBlueprint["format"] =
      index % 2 === 0 ? "single_select" : "multi_select";

    let correctIds = question.correctOptionIds ?? [];
    const options = question.options ?? [];

    if (forcedFormat === "single_select") {
      // Keep only the first correct id (or the first option as fallback)
      correctIds = correctIds.length > 0 ? [correctIds[0]] : options.length > 0 ? [options[0].id] : [];
    } else {
      // Need exactly 2 correct ids
      if (correctIds.length >= 2) {
        correctIds = correctIds.slice(0, 2);
      } else if (correctIds.length === 1 && options.length >= 2) {
        // Pick a second correct id that is different from the first
        const second = options.find((o) => o.id !== correctIds[0]);
        if (second) correctIds = [correctIds[0], second.id];
      } else if (correctIds.length === 0 && options.length >= 2) {
        correctIds = [options[0].id, options[1].id];
      }
    }

    return { ...question, format: forcedFormat, correctOptionIds: correctIds };
  });
}

function sanitizeQuestions(
  rawQuestions: QuestionBlueprint[],
  citations: SourceCitation[],
): QuestionBlueprint[] {
  const distributed = enforceFormatDistribution(rawQuestions);
  return distributed.map((question, index) => ({
    ...question,
    id: question.id || `generated-question-${index + 1}`,
    title: sanitizeTitle(question.title, question.format, index),
    prompt: stripVisibleMetadata(question.prompt),
    difficultyLabel: question.difficultyLabel || "Pressure drill",
    scenarioContext: stripVisibleMetadata(question.scenarioContext),
    idealAnswer:
      question.idealAnswer ||
      `${question.answerGuidance.join(" ")} Key phrases: ${question.answerKeyPhrases.join(", ")}.`,
    options: question.options ?? undefined,
    correctOptionIds: question.correctOptionIds ?? undefined,
    optionRationales: question.optionRationales ?? undefined,
    strategicTakeaway:
      question.strategicTakeaway ||
      "After solving the tactical problem, explain the business, governance, or architecture implication.",
    answerLenses:
      question.answerLenses?.length === 3
        ? question.answerLenses
        : ([
            {
              level: "sscp",
              title: "An SSCP may answer like this",
              answer: question.idealAnswer,
              explanation: "Start with the operationally correct control action and the risk it reduces.",
              focus: "Operational control decision",
            },
            {
              level: "cissp",
              title: "A CISSP may answer like this",
              answer: `${question.idealAnswer} Then add governance, risk, or architecture implications.`,
              explanation: "Broaden the tactical answer into cross-domain enterprise reasoning.",
              focus: "Risk and architecture framing",
            },
            {
              level: "cto",
              title: "A CTO may answer like this",
              answer: `${question.strategicTakeaway} Treat the issue as a leadership and operating-model decision.`,
              explanation: "Turn the control problem into a business, standardization, and communication problem.",
              focus: "Business impact and leadership execution",
            },
          ] satisfies QuestionAnswerLens[]),
    citations,
    sourceTypes: [...new Set(citations.map((citation) => citation.trustLevel))],
  }));
}

export async function POST(req: NextRequest) {
  let body: DrillRequest | null = null;
  try {
    body = await req.json();
  } catch {
    return bad("Invalid JSON payload.");
  }

  if (!body?.domainIds?.length) return bad("At least one domainId is required.");

  try {
    const notes = await loadCachedImportedNotes();
    const noteRefs = notes.filter((note) => body!.domainIds.includes(note.domainId)).slice(0, 8);
    const domainRefs = body.domainIds.map((domainId) => getSscpDomain(domainId));
    const trustedRefs = CURATED_RESOURCES.filter((resource) =>
      resource.domainIds.some((domainId) => body!.domainIds.includes(domainId)),
    ).slice(0, 4);
    const citations = sortCitations(
      [
        ...domainRefs.map((domain) => domain.officialCitation),
        ...trustedRefs.flatMap((resource) => resource.citations),
        ...noteRefs.map((note) => ({
          id: `note-${note.id}`,
          label: `${note.fileName} · ${note.sectionLabel}`,
          sourceName: note.fileName,
          trustLevel: "user_notes" as const,
          note: "Local PDF study corpus",
        })),
      ],
    );

    if (!hasOpenAIConfig()) {
      return NextResponse.json({ ok: true, ...buildFallbackDrill(body, notes) });
    }

    const prompt = [
      "Build an SSCP drill set with a CISSP bridge mindset using the official tutor domain framing, trusted study references, and the supplementary local PDF study corpus.",
      `Mode: ${body.mode}`,
      `Difficulty: ${body.difficulty}`,
      `Thinking level emphasis: ${body.thinkingLevel ?? "sscp"}`,
      `Domain mode: ${body.domainMode ?? "combined"}`,
      `Question count: ${body.count}`,
      `Generation nonce: ${body.generationNonce ?? Date.now()}`,
      body.topicHint?.trim() ? `Topic hint: ${body.topicHint.trim()}` : "",
      "",
      "Official domain framing:",
      ...domainRefs.map(
        (domain) =>
          `- ${domain.title}: ${domain.summary} Objectives: ${domain.objectives
            .map((objective) => objective.title)
            .join("; ")}`,
      ),
      "",
      "Trusted study references:",
      ...trustedRefs.map((resource) => `- ${resource.title}: ${resource.summary}`),
      "",
      "Supplementary PDF excerpts:",
      ...noteRefs.map((note) => `- ${note.fileName} / ${note.sectionLabel}: ${note.excerpt.slice(0, 320)}`),
      "",
      "Rules:",
      "- Make questions hard but fair.",
      "- Use the generation nonce as a variation hint so each request produces a fresh set of questions instead of reusing the same stems.",
      "- Write certification-style exam questions, not vague discussion prompts.",
      "- Use a clear stem, realistic distractors, and a best-answer mindset.",
      "- The visible title, prompt, and scenarioContext must read like exam content, not like retrieval notes or a prompt template.",
      "- Do not mention source names, PDFs, filenames, trust labels, anchors, objective IDs, or phrases such as study-book anchor, trusted anchor, PDF anchor, or objective focus in any visible question field.",
      "- Keep titles short and plain, for example 'Question 1' or 'Scenario question'.",
      `- Every question must be scenario-based with a realistic situation and four options.`,
      `- Exactly half the questions must use single_select format (one correct answer) and exactly half must use multi_select format (two correct answers). For ${body.count} questions that means ${Math.floor(body.count / 2)} single_select and ${Math.ceil(body.count / 2)} multi_select items. Alternate them — do not cluster one type together.`,
      `- The question prompt must not reveal how many answers to select. Do not use phrases such as "which TWO", "select two", "which ONE", "the best single", or any wording that states or implies a count. Use neutral phrasing such as "Which of the following actions should the security team take?" for all questions regardless of format.`,
      "- Keep the official domain framing primary, use trusted references for deeper reasoning, and use PDF excerpts as reinforcement or extra examples.",
      "- If domain mode is combined, make the learner use at least two SSCP domains in the reasoning whenever the question format allows it.",
      "- If domain mode is single, stay inside the selected domain while still making the question challenging.",
      "- Always include exactly three answer lenses: SSCP, CISSP, and CTO.",
      "- Let the selected thinking level influence the difficulty and the prompt style, but still provide all three answer lenses.",
      "- For scenario items, still make them exam-style by ending with the best answer or best next action question and providing options.",
      "- Provide a difficultyLabel, scenarioContext, optionRationales when options exist, and a strategicTakeaway for every item.",
      "- Every question must include a concise idealAnswer that can be shown to the learner as the expected answer.",
    ].join("\n");

    const aiPayload = await createStructuredResponse<{
      questions: QuestionBlueprint[];
      missedConcepts: string[];
      recommendedNextTask: string;
    }>({
      name: "sscp_drill",
      description: "Structured SSCP drill set with dual-review readiness.",
      schema: questionSchema,
      instructions:
        "You are an SSCP and CISSP tutor. Generate difficult, valid, well-structured study questions. Return JSON only.",
      input: prompt,
    });

    const questions = sanitizeQuestions(aiPayload.questions, citations);
    const response: DrillResponse = {
      generatedAt: new Date().toISOString(),
      questions,
      citations,
      sourceTypes: [...new Set(citations.map((citation) => citation.trustLevel))],
      confidenceLevel: inferConfidenceLevel(citations),
      sscpReview: {
        score: 86,
        verdict: "SSCP-ready drill",
        rationale:
          "The questions stay tied to official SSCP domain framing while still forcing careful reasoning.",
        strengths: ["Objective-grounded prompts", "Mixed item styles"],
        gaps: ["Needs your submitted answers before precise grading"],
        nextStep: "Answer the hardest scenario first, then compare your confidence to your actual performance.",
      },
      cisspReview: {
        score: 74,
        verdict: "CISSP bridge active",
        rationale:
          "The scenarios already ask for broader tradeoff thinking, but your final answer quality determines real bridge value.",
        strengths: ["Tradeoff-aware prompts", "Cross-domain framing"],
        gaps: ["Needs explicit governance or architecture rationale in your own answers"],
        nextStep: "For every answer, add one sentence on enterprise impact or control-family consequences.",
      },
      missedConcepts: aiPayload.missedConcepts,
      recommendedNextTask: aiPayload.recommendedNextTask,
      selectedLevel: body.thinkingLevel ?? "sscp",
      domainMode: body.domainMode ?? "combined",
    };

    return NextResponse.json({ ok: true, ...response });
  } catch (error: any) {
    const notes = await loadCachedImportedNotes().catch(() => []);
    const fallback = buildFallbackDrill(body, notes);
    return NextResponse.json({
      ok: true,
      ...fallback,
      warning: error?.message ?? "Falling back to local drill generation.",
    });
  }
}
