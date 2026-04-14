<#
.SYNOPSIS
Scaffolds a new draft declarative rule into the OneIM audit rule catalog.

.DESCRIPTION
Appends a new rule with state=draft and engine=declarative to assets/audit-rules.json.
The rule is NOT active until you manually change state to "active" after review.

After scaffolding, run validate_audit_rules.ps1 to confirm the rule is structurally valid,
then run run_auditor_tests.ps1 to verify no regressions before activating it.

.PARAMETER Id
Unique rule identifier, e.g. SEC180. Must not already exist in the catalog.

.PARAMETER Title
Short human-readable title for the rule.

.PARAMETER Category
Rule category: correctness, security, reliability, performance, or concurrency.

.PARAMETER Severity
Rule severity: high, medium, or low.

.PARAMETER Confidence
Confidence score 0-100. Defaults to 70.

.PARAMETER MatchKind
Declarative match strategy: line-pattern, header-required, or line-absence. Defaults to line-pattern.

.PARAMETER Pattern
Regular expression pattern for the declarative check.

.PARAMETER Why
Explanation of why this rule exists.

.PARAMETER TriggeringScenario
Description of the scenario that triggers the finding.

.PARAMETER Remediation
Recommended fix for the finding.

.PARAMETER TestIdeas
One or more test ideas for verifying the finding.

.PARAMETER DetectorFamily
Optional label grouping this rule with related checks.

.PARAMETER SurfaceScope
Optional list of OneIM surfaces where the rule applies. Defaults to any.

.PARAMETER MatchConfidence
Match-strength hint for the rule: high, medium, or low. Defaults to medium.

.PARAMETER SourceIds
Optional list of approved source IDs that back this rule.

.PARAMETER IncludePaths
Optional list of path globs that restrict the rule to matching relative paths.

.PARAMETER ExcludePaths
Optional list of path globs that exclude matching relative paths from this rule.

.PARAMETER MaxExamplesPerFile
Maximum duplicate examples reported per file. 0 means no cap. Defaults to 0.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$Id,

    [Parameter(Mandatory)]
    [string]$Title,

    [Parameter(Mandatory)]
    [ValidateSet("correctness", "security", "reliability", "performance", "concurrency")]
    [string]$Category,

    [Parameter(Mandatory)]
    [ValidateSet("high", "medium", "low")]
    [string]$Severity,

    [Parameter()]
    [ValidateRange(0, 100)]
    [int]$Confidence = 70,

    [Parameter()]
    [ValidateSet("line-pattern", "header-required", "line-absence")]
    [string]$MatchKind = "line-pattern",

    [Parameter(Mandatory)]
    [string]$Pattern,

    [Parameter(Mandatory)]
    [string]$Why,

    [Parameter(Mandatory)]
    [string]$TriggeringScenario,

    [Parameter(Mandatory)]
    [string]$Remediation,

    [Parameter(Mandatory)]
    [string[]]$TestIdeas,

    [Parameter()]
    [string]$DetectorFamily = "",

    [Parameter()]
    [ValidateSet("any", "script", "template", "process", "formatter")]
    [string[]]$SurfaceScope = @("any"),

    [Parameter()]
    [ValidateSet("high", "medium", "low")]
    [string]$MatchConfidence = "medium",

    [Parameter()]
    [string[]]$SourceIds = @(),

    [Parameter()]
    [string[]]$IncludePaths = @(),

    [Parameter()]
    [string[]]$ExcludePaths = @(),

    [Parameter()]
    [int]$MaxExamplesPerFile = 0
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$scriptRoot = Split-Path -Parent $PSCommandPath
$skillRoot = Split-Path -Parent $scriptRoot
$ruleCatalogPath = Join-Path $skillRoot "assets\audit-rules.json"

if (-not (Test-Path -LiteralPath $ruleCatalogPath)) {
    throw "Rule catalog not found at '$ruleCatalogPath'."
}

# Validate the regex pattern before touching the catalog
try {
    $null = [System.Text.RegularExpressions.Regex]::new($Pattern)
} catch {
    $host.UI.WriteErrorLine(("The provided Pattern is not a valid .NET regex: {0}" -f $_.Exception.Message))
    exit 1
}

$raw = Get-Content -LiteralPath $ruleCatalogPath -Raw | ConvertFrom-Json

# PS5.1 ConvertFrom-Json deserialises an empty JSON array [] as $null.
# Use Generic.List from the start so we always have a real .Count — no @() assignment risk.
$rulesList = New-Object System.Collections.Generic.List[object]
if ($null -ne $raw.rules) {
    foreach ($r in @($raw.rules)) {
        if ($null -ne $r) { $rulesList.Add($r) }
    }
}

# Check for duplicate ID
foreach ($existing in $rulesList) {
    if ([string]$existing.id -eq $Id) {
        $host.UI.WriteErrorLine(("Rule id '{0}' already exists in the catalog. Choose a unique id." -f $Id))
        exit 1
    }
}

# Build the new rule
$newRule = [ordered]@{
    id                   = $Id
    title                = $Title
    category             = $Category
    severity             = $Severity
    confidence           = $Confidence
    enabled              = $false
    state                = "draft"
    engine               = "declarative"
    match_kind           = $MatchKind
    pattern              = $Pattern
    why                  = $Why
    triggering_scenario  = $TriggeringScenario
    remediation          = $Remediation
    test_ideas           = @($TestIdeas)
    surface_scope        = @($SurfaceScope)
    match_confidence     = $MatchConfidence
    source_ids           = @($SourceIds)
}

$newRule.detector_family = if ([string]::IsNullOrWhiteSpace($DetectorFamily)) { "custom-rule" } else { $DetectorFamily }

if ($MaxExamplesPerFile -gt 0) {
    $newRule.max_examples_per_file = $MaxExamplesPerFile
}

if (@($IncludePaths).Count -gt 0) {
    $newRule.include_paths = @($IncludePaths)
}

if (@($ExcludePaths).Count -gt 0) {
    $newRule.exclude_paths = @($ExcludePaths)
}

# Append to the rules list already built above
$rulesList.Add([pscustomobject]$newRule)

$raw.rules = $rulesList.ToArray()

# Preserve policy_version date
if ($null -ne $raw.PSObject.Properties["policy_version"]) {
    $raw.policy_version = (Get-Date -Format "yyyy-MM-dd")
}

$raw | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $ruleCatalogPath -Encoding UTF8

Write-Host ("Scaffolded draft declarative rule '{0}' into {1}" -f $Id, $ruleCatalogPath)
Write-Host ""
Write-Host "Next steps:"
Write-Host "  1. Review the new rule entry in assets/audit-rules.json."
Write-Host "  2. Run  scripts/validate_audit_rules.ps1  to confirm it is valid."
Write-Host "  3. Change state from 'draft' to 'active' when the rule is ready."
Write-Host "  4. Run  scripts/run_auditor_tests.ps1  to verify no regressions."
exit 0
