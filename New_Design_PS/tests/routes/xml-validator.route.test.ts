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

  it("adds manifest-specific validation guidance for psd1 uploads", async () => {
    vi.resetModules();
    createMock.mockClear();

    createMock.mockResolvedValueOnce({
      choices: [
        {
          message: {
            content: JSON.stringify({
              analysis: "Manifest-based validation summary.",
              summary: {
                totalFunctions: 0,
                globalFunctions: [],
                helperFunctions: [],
                xmlClasses: ["User"],
                customCommands: [],
                predefinedCommands: ["Get-Users"],
                inferredConnectionParameters: [],
                actualConnectionParameters: [],
                expectedEntities: [],
              },
              issues: [],
              scriptAudit: {
                summary: "Manifest upload limits deep script inspection.",
                violatedRules: [],
              },
            }),
          },
        },
      ],
    });

    const request = new NextRequest("http://localhost:3000/api/ai/xml-validator", {
      method: "POST",
      body: JSON.stringify({
        xmlText: `<PowershellConnectorDefinition />`,
        psFiles: [
          {
            name: "Okta.psd1",
            text: `
@{
  RootModule = 'Okta.psm1'
  FunctionsToExport = @(
    "Connect-Okta",
    "Get-OktaUsers"
  )
}
            `,
          },
          {
            name: "Okta.psm1",
            text: `
function Connect-Okta {
  param($Site, $ApiToken)
}

function Get-OktaUsers {
  param()
}
            `,
          },
        ],
        schemaText: "[]",
      }),
    });

    const { POST } = await import("@/app/api/ai/xml-validator/route");
    const response = await POST(request);
    const lastCall = createMock.mock.calls.at(-1);
    const prompt = lastCall?.[0]?.messages?.[1]?.content as string;

    expect(response.status).toBe(200);
    expect(prompt).toContain("Manifest interpretation");
    expect(prompt).toContain("Manifest file: Okta.psd1");
    expect(prompt).toContain("RootModule: Okta.psm1");
    expect(prompt).toContain("FunctionsToExport: Connect-Okta, Get-OktaUsers");
    expect(prompt).toContain("Matching root module source was also uploaded: Okta.psm1");
    expect(prompt).toContain("module manifest (.psd1)");
    expect(prompt).toContain("PowerShell file (Okta.psd1)");
    expect(prompt).toContain("PowerShell file (Okta.psm1)");
  });

  it("removes provable false positives and groups repeated listing-binding issues", async () => {
    vi.resetModules();
    createMock.mockClear();

    createMock.mockResolvedValueOnce({
      choices: [
        {
          message: {
            content: JSON.stringify({
              analysis: "Noisy validation summary.",
              summary: {
                totalFunctions: 3,
                globalFunctions: [],
                helperFunctions: [],
                xmlClasses: ["User"],
                customCommands: [],
                predefinedCommands: [
                  "Get-OktaUsers",
                  "Get-OktaSingleUser",
                  "Get-OktaUsersInGroupsSingle",
                ],
                inferredConnectionParameters: [],
                actualConnectionParameters: [],
                expectedEntities: [],
              },
              issues: [
                {
                  code: "xml.predefined.missing-global",
                  severity: "error",
                  message:
                    "Predefined command 'Get-OktaUsers' is not exported by the manifest and was not found in the uploaded module source.",
                  line: 3,
                  snippet: '<Command Name="Get-OktaUsers" />',
                  relatedPath: '<Command Name="Get-OktaUsers" />',
                },
                {
                  code: "xml.command.missing",
                  severity: "error",
                  message:
                    "XML references command 'Get-OktaUsersInGroupsSingle', but it does not exist in the uploaded PowerShell public command set or XML custom commands.",
                  line: 4,
                  snippet: '<Command Name="Get-OktaUsersInGroupsSingle" />',
                  relatedPath: '<Command Name="Get-OktaUsersInGroupsSingle" />',
                },
                {
                  code: "map.parameter.missing",
                  severity: "error",
                  message:
                    "Map Parameter 'ID' does not match a real parameter on function 'Get-OktaSingleUser' by exact XML casing convention check; PowerShell parameter is 'ID'. This is actually present, so no issue should exist.",
                  line: 8,
                  snippet: '<Map ToCommand="Get-OktaSingleUser" Parameter="ID" />',
                  relatedPath: '<Map ToCommand="Get-OktaSingleUser" Parameter="ID" />',
                },
                {
                  code: "xml.class.returnbind.listing-command.missing",
                  severity: "error",
                  message:
                    "User property 'Status' only binds to item-read command 'Get-OktaSingleUser' and does not expose a same-class return binding for the listing command 'Get-OktaUsers'.",
                  line: 12,
                  snippet: '<Bind CommandResultOf="Get-OktaSingleUser" Path="status.ToString()" />',
                  relatedPath: '<Property Name="Status">',
                },
                {
                  code: "xml.class.returnbind.listing-command.missing",
                  severity: "error",
                  message:
                    "User property 'Email' only binds to item-read command 'Get-OktaSingleUser' and does not expose a same-class return binding for the listing command 'Get-OktaUsers'.",
                  line: 16,
                  snippet: '<Bind CommandResultOf="Get-OktaSingleUser" Path="email.ToString()" />',
                  relatedPath: '<Property Name="Email">',
                },
              ],
              scriptAudit: {
                summary: "PowerShell audit summary.",
                violatedRules: [],
              },
            }),
          },
        },
      ],
    });

    const request = new NextRequest("http://localhost:3000/api/ai/xml-validator", {
      method: "POST",
      body: JSON.stringify({
        xmlText: `
<PowershellConnectorDefinition>
  <Initialization>
    <PredefinedCommands>
      <Command Name="Get-OktaUsers" />
      <Command Name="Get-OktaUsersInGroupsSingle" />
    </PredefinedCommands>
  </Initialization>
  <Schema>
    <Class Name="User">
      <Properties>
        <Property Name="Id">
          <CommandMappings>
            <Map ToCommand="Get-OktaSingleUser" Parameter="ID" />
          </CommandMappings>
        </Property>
        <Property Name="Status">
          <ReturnBindings>
            <Bind CommandResultOf="Get-OktaSingleUser" Path="status.ToString()" />
          </ReturnBindings>
        </Property>
        <Property Name="Email">
          <ReturnBindings>
            <Bind CommandResultOf="Get-OktaSingleUser" Path="email.ToString()" />
          </ReturnBindings>
        </Property>
      </Properties>
    </Class>
  </Schema>
</PowershellConnectorDefinition>
        `,
        psFiles: [
          {
            name: "Okta.psd1",
            text: `
@{
  RootModule = 'Okta.psm1'
  FunctionsToExport = @(
    "Get-OktaUsers",
    "Get-OktaSingleUser"
  )
}
            `,
          },
          {
            name: "Okta.psm1",
            text: `
function Get-OktaUsers {
  param()
}

function Get-OktaSingleUser {
  param(
    [string] $ID,
    [string] $login
  )
}
            `,
          },
        ],
        schemaText: "[]",
      }),
    });

    const { POST } = await import("@/app/api/ai/xml-validator/route");
    const response = await POST(request);
    const json = await response.json();

    expect(response.status).toBe(200);
    expect(json.report.issues).toHaveLength(2);
    expect(json.report.issues.some((issue: { code: string; message: string }) => issue.code === "map.parameter.missing")).toBe(false);
    expect(
      json.report.issues.some(
        (issue: { code: string; message: string }) =>
          issue.code === "xml.predefined.missing-global" &&
          issue.message.includes("Get-OktaUsers")
      )
    ).toBe(false);
    expect(
      json.report.issues.find(
        (issue: { code: string; severity: string }) =>
          issue.code === "xml.class.returnbind.listing-command.missing" &&
          issue.severity === "warning"
      )?.message
    ).toContain("User has 2 properties");
    expect(json.report.analysis).toContain("Post-processing removed 2 command or parameter findings");
    expect(json.report.analysis).toContain(
      "Post-processing grouped 2 repeated listing-binding findings"
    );
  });
});
