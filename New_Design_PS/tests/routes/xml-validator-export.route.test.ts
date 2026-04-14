import { NextRequest } from "next/server";

import { POST } from "@/app/api/ai/xml-validator/export/route";

describe("POST /api/ai/xml-validator/export", () => {
  it("returns a downloadable PDF for a validation report", async () => {
    const request = new NextRequest("http://localhost:3000/api/ai/xml-validator/export", {
      method: "POST",
      body: JSON.stringify({
        xmlFileName: "SAPCostCenter.xml",
        psFileName: "SAPCostCenter.psm1",
        generatedAt: "2026-04-14T10:00:00.000Z",
        report: {
          analysis: "A compact review summary.",
          derivedSchema: [],
          summary: {
            totalFunctions: 1,
            globalFunctions: ["Get-Data"],
            helperFunctions: [],
            xmlClasses: ["CostCenter"],
            customCommands: [],
            predefinedCommands: ["Connect-API"],
            inferredConnectionParameters: [],
            actualConnectionParameters: [],
            expectedEntities: [],
          },
          issues: [],
          scriptAudit: {
            totalScore: 92,
            summary: "No major PowerShell issues were returned.",
            violatedRules: [],
          },
        },
      }),
    });

    const response = await POST(request);
    const buffer = Buffer.from(await response.arrayBuffer());

    expect(response.status).toBe(200);
    expect(response.headers.get("Content-Type")).toBe("application/pdf");
    expect(response.headers.get("Content-Disposition")).toContain(".pdf");
    expect(buffer.subarray(0, 8).toString("utf8")).toContain("%PDF-1.4");
    expect(buffer.byteLength).toBeGreaterThan(500);
  });
});
