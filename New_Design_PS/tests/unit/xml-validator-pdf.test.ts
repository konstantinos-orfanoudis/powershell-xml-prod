import type { ValidationReportExportRequest } from "@/app/XML-Validator/types";
import { buildValidationReportPdf } from "@/lib/xml-validator/pdf";

describe("xml-validator pdf export", () => {
  it("creates a non-empty PDF for a populated validation report", () => {
    const payload: ValidationReportExportRequest = {
      xmlFileName: "SAPCostCenter.xml",
      psFileName: "SAPCostCenter.psm1",
      generatedAt: "2026-04-14T10:00:00.000Z",
      report: {
        analysis: "AI summary about the most important connector risks.",
        derivedSchema: [],
        summary: {
          totalFunctions: 3,
          globalFunctions: ["Get-Data", "Update-Data"],
          helperFunctions: ["Write-ConnectorLog"],
          xmlClasses: ["CostCenter"],
          customCommands: ["Import-SFModule"],
          predefinedCommands: ["Connect-API"],
          inferredConnectionParameters: ["UserName", "Password"],
          actualConnectionParameters: ["UserName", "Password"],
          expectedEntities: [],
        },
        issues: [
          {
            id: "xml-1",
            code: "xml.root.connector",
            line: 1,
            message: "Root element should be PowershellConnectorDefinition.",
            severity: "warning",
            relatedPath: "<PowershellConnectorDefinition>",
          },
        ],
        scriptAudit: {
          totalScore: 76,
          summary: "Security posture is acceptable but logging and transport hardening should improve.",
          violatedRules: [
            {
              id: "rule-1",
              code: "ps.security.http-request.insecure",
              title: "Review insecure outbound HTTP request construction",
              category: "security",
              severity: "high",
              scoreImpact: 15,
              evidence: "Invoke-RestMethod uses a variable-built URL without an allowlist.",
              fix: "Validate destinations and keep TLS defaults explicit.",
              references: [
                {
                  id: "owasp-ssrf",
                  title: "OWASP SSRF Prevention Cheat Sheet",
                  authority: "OWASP",
                  url: "https://cheatsheetseries.owasp.org/cheatsheets/Server_Side_Request_Forgery_Prevention_Cheat_Sheet.html",
                  kind: "policy",
                  confidence: "high",
                },
              ],
            },
          ],
        },
      },
    };

    const pdf = buildValidationReportPdf(payload);
    const header = pdf.subarray(0, 8).toString("utf8");

    expect(header).toContain("%PDF-1.4");
    expect(pdf.byteLength).toBeGreaterThan(1000);
  });
});
