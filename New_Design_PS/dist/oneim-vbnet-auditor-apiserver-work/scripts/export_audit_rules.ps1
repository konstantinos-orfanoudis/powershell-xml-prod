<#
.SYNOPSIS
Exports the OneIM audit rule set for review.

.DESCRIPTION
Reads the reviewable rule catalog from assets/audit-rules.json and exports it as a Bundle
(Markdown + JSON + CSV together), or as a single Markdown, JSON, or CSV file.

Bundle mode is the default and writes three files to the output directory so both humans
and tooling can review the complete rule set in one operation.

.PARAMETER Format
Export format: Bundle (default), Markdown, Json, or Csv.
Bundle writes audit-rules.md, audit-rules.json, and audit-rules.csv together.

.PARAMETER OutputDir
Destination directory for bundle mode. Defaults to output\oneim-audit-rules-export\<timestamp>.
Ignored for single-format exports unless OutputPath is also omitted.

.PARAMETER OutputPath
Destination file path for single-format (Markdown, Json, Csv) exports.
If omitted, output is written to standard output.

.PARAMETER RuleState
Which lifecycle states to include: Active (default), All, Draft, or Disabled.
Active exports only rules with state=active. All includes draft and disabled rules.
#>
[CmdletBinding()]
param(
    [Parameter()]
    [ValidateSet("Bundle", "Markdown", "Json", "Csv")]
    [string]$Format = "Bundle",

    [Parameter()]
    [string]$OutputDir,

    [Parameter()]
    [string]$OutputPath,

    [Parameter()]
    [ValidateSet("All", "Active", "Draft", "Disabled")]
    [string]$RuleState = "Active"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$scriptRoot = Split-Path -Parent $PSCommandPath
$skillRoot = Split-Path -Parent $scriptRoot
$moduleRoot = Join-Path $scriptRoot "modules"
$approvedSourcesPath = Join-Path $skillRoot "assets\approved-sources.json"
$ruleCatalogPath = Join-Path $skillRoot "assets\audit-rules.json"

foreach ($modulePath in @(
    (Join-Path $moduleRoot "OneimAudit.Common.psm1"),
    (Join-Path $moduleRoot "OneimAudit.RuleCatalog.psm1")
)) {
    Import-Module $modulePath -Force
}

$ruleCatalog = Get-OneImAuditRuleCatalog -RuleCatalogPath $ruleCatalogPath -RuleState $RuleState
$sourceLookup = Get-OneImAuditSourceLookup -ApprovedSourcesPath $approvedSourcesPath

if ($Format -eq "Bundle") {
    $resolvedOutputDir = if ([string]::IsNullOrWhiteSpace($OutputDir)) {
        Join-Path (Get-Location).Path ("output\oneim-audit-rules-export\" + (Get-Date -Format "yyyyMMdd-HHmmss"))
    }
    else {
        [System.IO.Path]::GetFullPath($OutputDir)
    }

    New-OneImAuditDirectory -Path $resolvedOutputDir

    $mdPath  = Join-Path $resolvedOutputDir "audit-rules.md"
    $jsonPath = Join-Path $resolvedOutputDir "audit-rules.json"
    $csvPath = Join-Path $resolvedOutputDir "audit-rules.csv"

    Export-OneImAuditRuleSet -RuleCatalog $ruleCatalog -SourceLookup $sourceLookup -Format "Markdown" | Set-Content -LiteralPath $mdPath  -Encoding UTF8
    Export-OneImAuditRuleSet -RuleCatalog $ruleCatalog -SourceLookup $sourceLookup -Format "Json"     | Set-Content -LiteralPath $jsonPath -Encoding UTF8
    Export-OneImAuditRuleSet -RuleCatalog $ruleCatalog -SourceLookup $sourceLookup -Format "Csv"      | Set-Content -LiteralPath $csvPath  -Encoding UTF8

    Write-Host ("Rule export bundle written to: {0}" -f $resolvedOutputDir)
    Write-Host ("  Markdown : {0}" -f $mdPath)
    Write-Host ("  JSON     : {0}" -f $jsonPath)
    Write-Host ("  CSV      : {0}" -f $csvPath)
}
else {
    $content = Export-OneImAuditRuleSet -RuleCatalog $ruleCatalog -SourceLookup $sourceLookup -Format $Format

    if ($OutputPath) {
        $outputFullPath = [System.IO.Path]::GetFullPath($OutputPath)
        $parent = Split-Path -Parent $outputFullPath
        if ($parent) {
            New-OneImAuditDirectory -Path $parent
        }

        Set-Content -LiteralPath $outputFullPath -Value $content -Encoding UTF8
        Write-Host ("Rule export written to: {0}" -f $outputFullPath)
    }
    else {
        $content
    }
}
