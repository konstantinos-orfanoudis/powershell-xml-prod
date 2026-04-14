import { NextRequest } from "next/server";

const createMock = vi.fn();

process.env.OPENAI_API_KEY = "test-key";

vi.mock("@/lib/sscp/notes", () => ({
  loadCachedImportedNotes: vi.fn().mockResolvedValue([
    {
      id: "note-1",
      domainId: "network-communications-security",
      title: "Transport security and trust boundaries",
      fileName: "sscp.pdf",
      excerpt:
        "Strong TLS defaults, outbound destination validation, and precise logging improve secure connector operations.",
      sectionLabel: "Section 2",
      keywords: ["tls", "logging", "validation"],
      sourceType: "user_notes",
    },
  ]),
}));

vi.mock("openai", () => ({
  default: class OpenAI {
    chat = {
      completions: {
        create: createMock,
      },
    };
  },
}));

describe("POST /api/ai/xml-validator", () => {
  it("builds the AI prompt with SSCP and auditor enrichment and attaches references", async () => {
    vi.resetModules();

    createMock.mockResolvedValueOnce({
      choices: [
        {
          message: {
            content: JSON.stringify({
              analysis: "Short AI summary.",
              summary: {
                totalFunctions: 1,
                globalFunctions: ["Get-Data"],
                helperFunctions: [],
                xmlClasses: ["CostCenter"],
                customCommands: [],
                predefinedCommands: ["Connect-API"],
                inferredConnectionParameters: ["ApiToken"],
                actualConnectionParameters: ["ApiToken"],
                expectedEntities: [],
              },
              issues: [
                {
                  code: "xml.ok",
                  severity: "info",
                  message: "XML parsed successfully.",
                  line: 1,
                  snippet: "<PowershellConnectorDefinition",
                  relatedPath: "<PowershellConnectorDefinition>",
                },
              ],
              scriptAudit: {
                summary: "PowerShell audit summary.",
                violatedRules: [
                  {
                    code: "ps.security.http-request.insecure",
                    title: "Review insecure outbound HTTP request construction",
                    category: "security",
                    severity: "high",
                    scoreImpact: 15,
                    evidence:
                      "Invoke-RestMethod uses a variable-built URL without a strong allowlist.",
                    fix: "Validate outbound destinations and keep TLS defaults explicit.",
                    line: 12,
                  },
                ],
              },
            }),
          },
        },
      ],
    });

    const request = new NextRequest("http://localhost:3000/api/ai/xml-validator", {
      method: "POST",
      body: JSON.stringify({
        xmlText: `<PowershellConnectorDefinition Name="OktaConnector" />`,
        psText: `
          Import-Module Okta -Force
          function global:Get-Data {
            Invoke-RestMethod -Uri "https://tenant.okta.com/api/v1/users"
          }
        `,
        schemaText: "[]",
      }),
    });

    const { POST } = await import("@/app/api/ai/xml-validator/route");
    const response = await POST(request);
    const json = await response.json();
    const prompt = createMock.mock.calls[0][0].messages[1].content as string;

    expect(response.status).toBe(200);
    expect(prompt).toContain("Validation rules prompt");
    expect(prompt).toContain("Internal policy addendum");
    expect(prompt).toContain("Internal SSCP policy addendum");
    expect(prompt).toContain("Auditor-approved external reference model");
    expect(prompt).toContain("Okta");
    expect(json.report.scriptAudit.violatedRules[0].references.length).toBeGreaterThan(0);
  });
});
