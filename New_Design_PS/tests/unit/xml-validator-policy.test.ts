vi.mock("@/lib/sscp/notes", () => ({
  loadCachedImportedNotes: vi.fn().mockRejectedValue(new Error("notes unavailable")),
}));

import {
  buildValidatorPolicyContext,
  inferPowerShellTechnologies,
} from "@/lib/xml-validator/policy";

describe("xml-validator policy enrichment", () => {
  it("infers likely vendor technologies from module names and endpoint URLs", () => {
    const technologies = inferPowerShellTechnologies(
      `<CustomCommand Name="Connect"><![CDATA[Import-Module Okta -Force]]></CustomCommand>`,
      `
        function global:Get-Data {
          Invoke-RestMethod -Uri "https://example.okta.com/api/v1/users"
        }
      `
    );

    expect(technologies.some((technology) => technology.id === "okta")).toBe(true);
    expect(
      technologies.find((technology) => technology.id === "okta")?.hosts.some((host) =>
        host.includes("okta.com")
      )
    ).toBe(true);
  });

  it("builds a prompt addendum even when the local SSCP note cache is unavailable", async () => {
    const context = await buildValidatorPolicyContext(
      `<PowershellConnectorDefinition />`,
      `
        function global:Get-Data {
          Invoke-RestMethod -Uri "https://graph.microsoft.com/v1.0/users"
        }
      `
    );

    expect(context.promptAddendum).toContain("Internal SSCP policy addendum");
    expect(context.promptAddendum).toContain("Auditor-approved external reference model");
    expect(context.allowedReferences.length).toBeGreaterThan(0);
  });
});
