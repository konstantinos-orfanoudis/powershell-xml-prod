import { NextRequest } from "next/server";

vi.mock("@/lib/sscp/notes", () => ({
  loadCachedImportedNotes: vi.fn().mockResolvedValue([]),
}));

import { POST } from "@/app/api/sscp/evaluate/route";

describe("POST /api/sscp/evaluate", () => {
  it("returns richer fallback dual-review guidance", async () => {
    const request = new NextRequest("http://localhost:3000/api/sscp/evaluate", {
      method: "POST",
      body: JSON.stringify({
        question: {
          id: "q-1",
          format: "single_select",
          title: "Access control question",
          prompt: "Which option best supports least privilege?",
          domainIds: ["access-controls"],
          objectiveIds: ["sscp-2-1"],
          difficulty: "foundation",
          difficultyLabel: "Foundation pressure",
          scenarioContext: "A new user needs access fast.",
          options: [
            { id: "a", label: "A", text: "Grant only the access required." },
            { id: "b", label: "B", text: "Grant broad access to save time." },
          ],
          correctOptionIds: ["a"],
          optionRationales: [
            { optionId: "a", rationale: "Directly supports least privilege." },
            { optionId: "b", rationale: "Overprivileges the user." },
          ],
          idealAnswer: "A is correct because it applies least privilege directly.",
          answerGuidance: ["Name the control action.", "Explain the risk reduction."],
          answerKeyPhrases: ["least privilege", "access"],
          strategicTakeaway: "Standardize provisioning so broad access is not the fast default.",
          answerLenses: [
            {
              level: "sscp",
              title: "An SSCP may answer like this",
              answer: "Grant only the access required and document why.",
              explanation: "This is the direct least-privilege move.",
              focus: "Operational control action",
            },
            {
              level: "cissp",
              title: "A CISSP may answer like this",
              answer: "Grant only what is required and explain the governance and risk impact of broader access.",
              explanation: "This expands the tactical control into enterprise risk thinking.",
              focus: "Risk and governance",
            },
            {
              level: "cto",
              title: "A CTO may answer like this",
              answer: "Fix the immediate access decision, then standardize provisioning so broad access is never the default.",
              explanation: "This turns the issue into an operating-model and leadership decision.",
              focus: "Business and operating model",
            },
          ],
          citations: [],
          sourceTypes: ["official"],
        },
        attempt: {
          questionId: "q-1",
          answer: "a",
          confidence: 70,
        },
      }),
    });

    const response = await POST(request);
    const json = await response.json();

    expect(response.status).toBe(200);
    expect(json.bestAnswerRationale).toContain("least privilege");
    expect(json.sscpTakeaway).toContain("SSCP");
    expect(json.cisspTakeaway).toContain("CISSP");
    expect(Array.isArray(json.distractorWarnings)).toBe(true);
  });
});
