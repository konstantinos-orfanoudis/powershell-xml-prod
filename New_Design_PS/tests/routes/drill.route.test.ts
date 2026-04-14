import { NextRequest } from "next/server";

vi.mock("@/lib/sscp/notes", () => ({
  loadCachedImportedNotes: vi.fn().mockResolvedValue([]),
}));

import { POST } from "@/app/api/sscp/drill/route";

describe("POST /api/sscp/drill", () => {
  it("returns fallback drill questions with richer metadata", async () => {
    const request = new NextRequest("http://localhost:3000/api/sscp/drill", {
      method: "POST",
      body: JSON.stringify({
        domainIds: ["cryptography"],
        mode: "mixed",
        count: 3,
        difficulty: "pressure",
        thinkingLevel: "cissp",
        domainMode: "combined",
        generationNonce: 101,
      }),
    });

    const response = await POST(request);
    const json = await response.json();

    expect(response.status).toBe(200);
    expect(json.questions).toHaveLength(3);
    expect(json.questions[0].difficultyLabel).toBeTruthy();
    expect(json.questions[0].strategicTakeaway).toBeTruthy();
    expect(json.questions[0].answerLenses).toHaveLength(3);
    expect(json.questions[0].options?.length ?? 0).toBeGreaterThan(1);
    expect(json.questions[0].correctOptionIds?.length ?? 0).toBeGreaterThan(0);
    expect(json.selectedLevel).toBe("cissp");
    expect(json.domainMode).toBe("combined");
    expect(json.questions[0].prompt).not.toMatch(/study-book anchor|trusted anchor|pdf anchor|objective focus|\.pdf/i);
    expect(json.questions[0].scenarioContext ?? "").not.toMatch(/study-book anchor|trusted anchor|pdf anchor|objective focus|\.pdf/i);
    expect(new Set(json.questions.map((question: { prompt: string }) => question.prompt)).size).toBeGreaterThan(1);
  });
});
