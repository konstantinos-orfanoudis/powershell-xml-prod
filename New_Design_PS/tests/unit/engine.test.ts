import { buildFallbackDrill, buildTeachResponse, sortCitations } from "@/lib/sscp/engine";
import { SourceCitation } from "@/lib/sscp/types";

describe("SSCP engine", () => {
  it("builds a guided lesson with interactive study assets", () => {
    const lesson = buildTeachResponse("access-controls", [
      {
        id: "note-1",
        domainId: "access-controls",
        title: "MFA and provisioning reminders",
        fileName: "access.pdf",
        excerpt: "Provisioning, deprovisioning, and MFA choices must reinforce accountability and least privilege in live environments.",
        sectionLabel: "Section 1",
        keywords: ["mfa", "least privilege"],
        sourceType: "user_notes",
      },
    ]);

    expect(lesson.flashcards.length).toBeGreaterThan(3);
    expect(lesson.workedExamples.length).toBeGreaterThan(0);
    expect(lesson.lessonScenarios.length).toBeGreaterThan(0);
    expect(lesson.checkpointQuestions.length).toBeGreaterThan(0);
    expect(lesson.diagramSpecs.length).toBeGreaterThan(0);
    expect(lesson.strategicLens.leadershipPrompt).toContain("leadership");
    expect(lesson.sourceTypes).toContain("official");
    expect(lesson.sourceTypes).toContain("user_notes");
  });

  it("generates richer fallback drill metadata", () => {
    const drill = buildFallbackDrill({
      domainIds: ["incident-response-recovery"],
      mode: "mixed",
      count: 4,
      difficulty: "pressure",
      thinkingLevel: "cto",
      domainMode: "combined",
      generationNonce: 101,
    });

    expect(drill.questions).toHaveLength(4);
    expect(drill.selectedLevel).toBe("cto");
    expect(drill.domainMode).toBe("combined");
    for (const question of drill.questions) {
      expect(question.difficultyLabel.length).toBeGreaterThan(0);
      expect(question.strategicTakeaway.length).toBeGreaterThan(0);
      expect(question.scenarioContext?.length).toBeGreaterThan(0);
      expect(question.answerLenses).toHaveLength(3);
      expect(question.domainIds.length).toBeGreaterThan(1);
      expect(question.options?.length ?? 0).toBeGreaterThan(1);
      expect(question.correctOptionIds?.length ?? 0).toBeGreaterThan(0);
      expect(question.optionRationales?.length ?? 0).toBeGreaterThan(0);
      expect(question.prompt).not.toMatch(/study-book anchor|trusted anchor|pdf anchor|objective focus|\.pdf/i);
      expect(question.scenarioContext ?? "").not.toMatch(/study-book anchor|trusted anchor|pdf anchor|objective focus|\.pdf/i);
    }
  });

  it("changes the fallback drill when the generation nonce changes", () => {
    const first = buildFallbackDrill({
      domainIds: ["access-controls"],
      mode: "scenario",
      count: 4,
      difficulty: "pressure",
      thinkingLevel: "cissp",
      domainMode: "combined",
      generationNonce: 101,
    });
    const second = buildFallbackDrill({
      domainIds: ["access-controls"],
      mode: "scenario",
      count: 4,
      difficulty: "pressure",
      thinkingLevel: "cissp",
      domainMode: "combined",
      generationNonce: 202,
    });

    expect(first.questions.map((question) => question.prompt)).not.toEqual(
      second.questions.map((question) => question.prompt),
    );
  });

  it("keeps official citations ahead of weaker sources", () => {
    const citations: SourceCitation[] = [
      {
        id: "note",
        label: "User notes",
        sourceName: "notes.pdf",
        trustLevel: "user_notes",
      },
      {
        id: "trusted",
        label: "Trusted guide",
        sourceName: "NIST",
        trustLevel: "trusted_live",
      },
      {
        id: "official",
        label: "Official outline",
        sourceName: "ISC2",
        trustLevel: "official",
      },
    ];

    const sorted = sortCitations(citations);
    expect(sorted.map((item) => item.trustLevel)).toEqual(["official", "trusted_live", "user_notes"]);
  });
});
