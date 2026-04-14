import { ACTION_HEALTH_MATRIX, buildCaptureStudyAid } from "@/lib/sscp/coach-utils";

describe("coach utils", () => {
  it("creates study aids from extension captures", () => {
    const aid = buildCaptureStudyAid({
      id: "capture-1",
      title: "Zero Trust Notes",
      url: "https://example.com",
      selectionText:
        "Zero trust requires policy-driven access decisions, better telemetry, and tighter least-privilege enforcement across identities and workloads.",
      createdAt: new Date().toISOString(),
    });

    expect(aid.summary).toContain("Zero trust");
    expect(aid.flashcards.length).toBeGreaterThan(1);
    expect(aid.scenarioPrompt).toContain("SSCP");
  });

  it("tracks action coverage across the app and extension", () => {
    const workspaces = new Set(ACTION_HEALTH_MATRIX.map((item) => item.workspace));
    expect(workspaces.has("plan")).toBe(true);
    expect(workspaces.has("learn")).toBe(true);
    expect(workspaces.has("drill")).toBe(true);
    expect(workspaces.has("resources")).toBe(true);
    expect(workspaces.has("library")).toBe(true);
    expect(workspaces.has("extension")).toBe(true);
  });
});
