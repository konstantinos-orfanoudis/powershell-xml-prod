import { NextRequest, NextResponse } from "next/server";

import { getCisspDomainsForSscp, getSscpDomain } from "@/lib/sscp/catalog";
import { inferConfidenceLevel, sortCitations } from "@/lib/sscp/engine";
import { loadCachedImportedNotes } from "@/lib/sscp/notes";
import { createStructuredResponse, hasOpenAIConfig } from "@/lib/sscp/openai";
import { DualReview, QuestionAttempt, QuestionBlueprint } from "@/lib/sscp/types";

export const runtime = "nodejs";
export const dynamic = "force-dynamic";

const evaluationSchema = {
  type: "object",
  additionalProperties: false,
  required: [
    "correctness",
    "confidenceGap",
    "missedConcepts",
    "crossDomainSignals",
    "recommendedNextTask",
    "bestAnswerRationale",
    "distractorWarnings",
    "thinkingCorrection",
    "sscpTakeaway",
    "cisspTakeaway",
    "sscpReview",
    "cisspReview",
  ],
  properties: {
    correctness: {
      type: "string",
      enum: ["incorrect", "partial", "correct", "strong"],
    },
    confidenceGap: { type: "number" },
    missedConcepts: {
      type: "array",
      items: { type: "string" },
    },
    crossDomainSignals: {
      type: "array",
      items: { type: "string" },
    },
    recommendedNextTask: { type: "string" },
    bestAnswerRationale: { type: "string" },
    distractorWarnings: {
      type: "array",
      items: { type: "string" },
    },
    thinkingCorrection: { type: "string" },
    sscpTakeaway: { type: "string" },
    cisspTakeaway: { type: "string" },
    sscpReview: {
      type: "object",
      additionalProperties: false,
      required: ["score", "verdict", "rationale", "strengths", "gaps", "nextStep"],
      properties: {
        score: { type: "number" },
        verdict: { type: "string" },
        rationale: { type: "string" },
        strengths: { type: "array", items: { type: "string" } },
        gaps: { type: "array", items: { type: "string" } },
        nextStep: { type: "string" },
      },
    },
    cisspReview: {
      type: "object",
      additionalProperties: false,
      required: ["score", "verdict", "rationale", "strengths", "gaps", "nextStep"],
      properties: {
        score: { type: "number" },
        verdict: { type: "string" },
        rationale: { type: "string" },
        strengths: { type: "array", items: { type: "string" } },
        gaps: { type: "array", items: { type: "string" } },
        nextStep: { type: "string" },
      },
    },
  },
} as const;

function bad(error: string, status = 400) {
  return NextResponse.json({ ok: false, error }, { status });
}

function normalizeAnswer(answer: QuestionAttempt["answer"]): string {
  return Array.isArray(answer) ? answer.join(", ") : answer;
}

function fallbackScore(question: QuestionBlueprint, answer: QuestionAttempt["answer"]) {
  if (question.correctOptionIds?.length) {
    const actual = Array.isArray(answer) ? [...answer].sort().join("|") : String(answer);
    const expected =
      question.correctOptionIds.length > 1
        ? [...question.correctOptionIds].sort().join("|")
        : question.correctOptionIds[0];
    return actual === expected ? 92 : 35;
  }

  const normalized = normalizeAnswer(answer).toLowerCase();
  const hits = question.answerKeyPhrases.filter((phrase) =>
    normalized.includes(phrase.toLowerCase()),
  ).length;
  const ratio = question.answerKeyPhrases.length
    ? hits / question.answerKeyPhrases.length
    : 0;
  if (ratio >= 0.75) return 88;
  if (ratio >= 0.45) return 67;
  return 38;
}

export async function POST(req: NextRequest) {
  let body:
    | {
        question?: QuestionBlueprint;
        attempt?: QuestionAttempt;
      }
    | null = null;
  try {
    body = await req.json();
  } catch {
    return bad("Invalid JSON payload.");
  }

  if (!body?.question || !body?.attempt) {
    return bad("Both question and attempt are required.");
  }

  const question = body.question;
  const attempt = body.attempt;

  try {
    const notes = await loadCachedImportedNotes();
    const domainRefs = question.domainIds.map((domainId) => getSscpDomain(domainId));
    const noteRefs = notes.filter((note) => question.domainIds.includes(note.domainId)).slice(0, 4);
    const citations = sortCitations([
      ...question.citations,
      ...noteRefs.map((note) => ({
        id: `note-${note.id}`,
        label: `${note.fileName} · ${note.sectionLabel}`,
        sourceName: note.fileName,
        trustLevel: "user_notes" as const,
        note: "Local PDF study corpus",
      })),
    ]);

    if (!hasOpenAIConfig()) {
      const score = fallbackScore(question, attempt.answer);
      const response: DualReview = {
        confidenceLevel: inferConfidenceLevel(citations),
        correctness: score >= 85 ? "correct" : score >= 60 ? "partial" : "incorrect",
        confidenceGap: Math.round(attempt.confidence - score),
        missedConcepts: score >= 85 ? [] : question.answerKeyPhrases.slice(0, 3),
        crossDomainSignals: question.domainIds.flatMap((domainId) =>
          getCisspDomainsForSscp(domainId).map((domain) => domain.title),
        ),
        recommendedNextTask:
          score >= 85
            ? "Move to a harder mixed-domain scenario and keep your confidence honest."
            : "Rebuild the objective in the Learn tab, then answer the same prompt again with one broader CISSP sentence.",
        bestAnswerRationale: question.idealAnswer,
        distractorWarnings:
          question.optionRationales
            ?.filter((item) => !question.correctOptionIds?.includes(item.optionId))
            .map((item) => item.rationale)
            .slice(0, 3) ?? ["Weak answers usually skip the direct control move or ignore risk reduction."],
        thinkingCorrection:
          score >= 85
            ? "Keep the same structure under pressure: control action first, broader framing second."
            : "Tighten the answer around the direct control action, then explain the risk and only then add broader enterprise framing.",
        sscpTakeaway:
          "SSCP answers win when they are operationally direct, objective-aligned, and explicit about the control or process being applied.",
        cisspTakeaway:
          "CISSP depth appears when the same answer expands into governance, architecture, business risk, or leadership tradeoffs.",
        sscpReview: {
          score,
          verdict: score >= 85 ? "Operationally sound" : "Needs tighter SSCP precision",
          rationale:
            "The fallback grader checks direct alignment with the expected answer and the key objective language.",
          strengths:
            score >= 85 ? ["Aligned to the objective", "Good SSCP focus"] : ["Attempted the right topic"],
          gaps:
            score >= 85 ? ["Add more confidence discipline"] : ["Missed or underused core objective language"],
          nextStep: "Name the control, the operational action, and the risk it reduces.",
        },
        cisspReview: {
          score: Math.max(25, Math.round(score - 10)),
          verdict: score >= 80 ? "Bridge-worthy" : "Needs broader framing",
          rationale:
            "The CISSP lens expects business, architecture, and governance consequences in addition to the SSCP-correct action.",
          strengths: score >= 80 ? ["Can scale into broader reasoning"] : ["Has a tactical starting point"],
          gaps: ["Needs clearer tradeoff or enterprise-impact thinking"],
          nextStep: "Add one sentence on governance, architecture, or business risk impact.",
        },
        citations,
        sourceTypes: [...new Set(citations.map((citation) => citation.trustLevel))],
      };
      return NextResponse.json({ ok: true, ...response });
    }

    const prompt = [
      "Grade this answer using the question metadata, the official tutor domain framing, and the supplementary local PDF study corpus.",
      "",
      `Question format: ${question.format}`,
      `Question title: ${question.title}`,
      `Question prompt: ${question.prompt}`,
      `Expected objective IDs: ${question.objectiveIds.join(", ")}`,
      `Ideal answer: ${question.idealAnswer}`,
      `Answer guidance: ${question.answerGuidance.join(" | ")}`,
      `Answer key phrases: ${question.answerKeyPhrases.join(", ")}`,
      `Correct option IDs: ${(question.correctOptionIds ?? []).join(", ") || "n/a"}`,
      `Option rationales: ${(question.optionRationales ?? [])
        .map((item) => `${item.optionId}=${item.rationale}`)
        .join(" | ") || "n/a"}`,
      `Learner answer: ${normalizeAnswer(attempt.answer)}`,
      `Learner confidence: ${attempt.confidence}/100`,
      `Strategic takeaway: ${question.strategicTakeaway}`,
      "",
      "Official domain framing:",
      ...domainRefs.map(
        (domain) =>
          `- ${domain.title}: ${domain.summary} Objectives: ${domain.objectives
            .map((objective) => objective.title)
            .join("; ")}`,
      ),
      "",
      "Supporting PDF excerpts:",
      ...noteRefs.map((note) => `- ${note.excerpt.slice(0, 260)}`),
      "",
      "Review rules:",
      "- Score the SSCP review on operational correctness and objective alignment.",
      "- Score the CISSP review on broader risk, governance, architecture, and tradeoff depth.",
      "- Keep the official domain framing primary and use the PDF excerpts only as supporting context.",
      "- If the answer is solid for SSCP but shallow for CISSP, say that explicitly.",
      "- Explain the best-answer logic, not just the score.",
      "- Call out distractor patterns or reasoning traps when relevant.",
      "- Keep missed concepts concrete and actionable.",
    ].join("\n");

    const aiPayload = await createStructuredResponse<Omit<DualReview, "citations" | "sourceTypes" | "confidenceLevel">>({
      name: "sscp_dual_review",
      description: "Dual SSCP and CISSP answer review.",
      schema: evaluationSchema,
      instructions:
        "You are a rigorous security tutor. Return JSON only and avoid unsupported claims.",
      input: prompt,
    });

    const response: DualReview = {
      ...aiPayload,
      confidenceLevel: inferConfidenceLevel(citations),
      citations,
      sourceTypes: [...new Set(citations.map((citation) => citation.trustLevel))],
    };

    return NextResponse.json({ ok: true, ...response });
  } catch (error: any) {
    return bad(error?.message ?? "Failed to evaluate answer.", 500);
  }
}
