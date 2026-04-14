import { NextRequest } from "next/server";

vi.mock("@/lib/sscp/notes", () => ({
  loadCachedImportedNotes: vi.fn().mockResolvedValue([
    {
      id: "note-1",
      domainId: "security-concepts-practices",
      title: "Control hierarchy notes",
      fileName: "domain1.pdf",
      excerpt: "Administrative, technical, and physical controls should be linked to operational accountability.",
      sectionLabel: "Section 1",
      keywords: ["controls", "accountability"],
      sourceType: "user_notes",
    },
  ]),
}));

import { POST } from "@/app/api/sscp/teach/route";

describe("POST /api/sscp/teach", () => {
  it("returns an enriched guided lesson payload", async () => {
    const request = new NextRequest("http://localhost:3000/api/sscp/teach", {
      method: "POST",
      body: JSON.stringify({ domainId: "security-concepts-practices" }),
    });

    const response = await POST(request);
    const json = await response.json();

    expect(response.status).toBe(200);
    expect(json.flashcards.length).toBeGreaterThan(0);
    expect(json.lessonScenarios.length).toBeGreaterThan(0);
    expect(json.diagramSpecs.length).toBeGreaterThan(0);
    expect(json.strategicLens.title).toContain("strategic");
  });
});
