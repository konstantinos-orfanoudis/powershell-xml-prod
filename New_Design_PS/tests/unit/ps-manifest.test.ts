import { parsePsModuleManifest } from "@/lib/ps-manifest";

describe("parsePsModuleManifest", () => {
  it("extracts root module and exported functions from a psd1 manifest", () => {
    const manifest = parsePsModuleManifest(`
@{
  RootModule = 'Okta.psm1'
  FunctionsToExport = @(
    "Connect-Okta",
    "Get-OktaUsers"
    "Remove-OktaUser"
  )
}
`);

    expect(manifest.rootModule).toBe("Okta.psm1");
    expect(manifest.functionsToExport).toEqual([
      "Connect-Okta",
      "Get-OktaUsers",
      "Remove-OktaUser",
    ]);
    expect(manifest.wildcardFunctionsToExport).toBe(false);
  });

  it("detects wildcard exports", () => {
    const manifest = parsePsModuleManifest(`
@{
  RootModule = "Module.psm1"
  FunctionsToExport = "*"
}
`);

    expect(manifest.functionsToExport).toEqual([]);
    expect(manifest.wildcardFunctionsToExport).toBe(true);
  });
});
