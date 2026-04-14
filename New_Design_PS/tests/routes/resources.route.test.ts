import { NextRequest } from "next/server";

vi.mock("@/lib/sscp/notes", () => ({
  loadCachedImportedNotes: vi.fn().mockResolvedValue([
    {
      id: "note-1",
      domainId: "network-communications-security",
      title: "Segmentation and trust boundaries",
      fileName: "cissp.pdf",
      excerpt: "Segmentation, trust boundaries, and policy enforcement reduce lateral movement and help express zero trust more concretely.",
      sectionLabel: "Section 4",
      keywords: ["segmentation", "trust boundaries", "zero trust"],
      sourceType: "user_notes",
    },
  ]),
}));

import { POST } from "@/app/api/sscp/resources/route";

describe("POST /api/sscp/resources", () => {
  it("returns validated study resources with supplemental PDF support", async () => {
    const request = new NextRequest("http://localhost:3000/api/sscp/resources", {
      method: "POST",
      body: JSON.stringify({
        domainIds: ["network-communications-security"],
        topicHint: "segmentation and zero trust",
      }),
    });

    const response = await POST(request);
    const json = await response.json();

    expect(response.status).toBe(200);
    expect(json.curated.length).toBeGreaterThan(0);
    expect(json.live).toEqual([]);
    expect(json.summary.toLowerCase()).toContain("trusted");
    expect(json.summary.toLowerCase()).toContain("pdf");
    expect(json.curated.some((item: any) => item.sourceType === "trusted_live")).toBe(true);
    expect(json.curated.some((item: any) => item.sourceType === "user_notes")).toBe(true);
  });
});
