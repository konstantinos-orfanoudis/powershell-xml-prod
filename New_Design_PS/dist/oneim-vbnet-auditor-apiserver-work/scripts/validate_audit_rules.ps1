<#
.SYNOPSIS
Validates the OneIM audit rule catalog for structural correctness.

.DESCRIPTION
Checks the rule catalog for problems that would cause silent misbehavior or
runtime errors:

  1. Required base fields present on every rule
  2. Unique rule IDs — no duplicates
  3. Valid enum values for category, severity, state, engine, and match_kind
  4. Declarative rules have their extra required fields (match_kind, pattern,
     triggering_scenario, remediation, test_ideas)
  5. The pattern field on declarative rules compiles as a valid .NET regex
  6. When -ApprovedSourcesPath is given: every source_id resolves in that file

All errors are collected and printed before exit so the full list is visible.

Exit codes:
  0  All checks passed.
  1  One or more validation errors found.

.PARAMETER RuleCatalogPath
Path to audit-rules.json. Defaults to assets\audit-rules.json in the skill root.

.PARAMETER ApprovedSourcesPath
Optional path to approved-sources.json. When blank, the default skill-asset path
is used if the file exists; omitted entirely if it does not.
#>
[CmdletBinding()]
param(
    [Parameter()]
    [string]$RuleCatalogPath,

    [Parameter()]
    [string]$ApprovedSourcesPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$scriptRoot = Split-Path -Parent $PSCommandPath
$skillRoot  = Split-Path -Parent $scriptRoot

$resolvedCatalogPath = if ([string]::IsNullOrWhiteSpace($RuleCatalogPath)) {
    [System.IO.Path]::GetFullPath((Join-Path $skillRoot "assets\audit-rules.json"))
} else {
    [System.IO.Path]::GetFullPath($RuleCatalogPath)
}

$resolvedSourcesPath = if (-not [string]::IsNullOrWhiteSpace($ApprovedSourcesPath)) {
    [System.IO.Path]::GetFullPath($ApprovedSourcesPath)
} else {
    $candidate = [System.IO.Path]::GetFullPath((Join-Path $skillRoot "assets\approved-sources.json"))
    if (Test-Path -LiteralPath $candidate) { $candidate } else { $null }
}

if (-not (Test-Path -LiteralPath $resolvedCatalogPath)) {
    $host.UI.WriteErrorLine("Rule catalog not found at '$resolvedCatalogPath'.")
    exit 1
}

# ---------------------------------------------------------------------------
# Parse catalog
# ---------------------------------------------------------------------------
$raw = $null
try {
    $raw = Get-Content -LiteralPath $resolvedCatalogPath -Raw | ConvertFrom-Json
} catch {
    $host.UI.WriteErrorLine(("Failed to parse rule catalog JSON: {0}" -f $_.Exception.Message))
    exit 1
}

if ($null -eq $raw.PSObject.Properties["rules"]) {
    $host.UI.WriteErrorLine("Catalog is missing a top-level 'rules' array.")
    exit 1
}

# ---------------------------------------------------------------------------
# Valid enum sets
# ---------------------------------------------------------------------------
$validCategories = @("correctness", "security", "reliability", "performance", "concurrency")
$validSeverities = @("low", "medium", "high")
$validStates     = @("active", "draft", "disabled")
$validEngines    = @("coded", "declarative")
$validMatchKinds = @("header-required", "line-pattern", "line-absence")
$validSurfaceScopes = @("any", "script", "template", "process", "formatter")
$validMatchConfidences = @("high", "medium", "low")

$requiredBaseFields        = @("id", "title", "category", "severity", "confidence", "why", "source_ids")
$requiredDeclarativeFields = @("match_kind", "pattern", "triggering_scenario", "remediation", "test_ideas")
$requiredActiveFields      = @("detector_family", "remediation", "test_ideas", "surface_scope", "match_confidence")

# ---------------------------------------------------------------------------
# Load approved sources (optional)
# ---------------------------------------------------------------------------
$approvedSourceIds = @{}
if ($null -ne $resolvedSourcesPath -and (Test-Path -LiteralPath $resolvedSourcesPath)) {
    try {
        $ruleCatalogModulePath = Join-Path $skillRoot "scripts\modules\OneimAudit.RuleCatalog.psm1"
        Import-Module $ruleCatalogModulePath -Force
        $sourceLookup = Get-OneImAuditSourceLookup -ApprovedSourcesPath $resolvedSourcesPath
        foreach ($sourceId in @($sourceLookup.Keys)) {
            $approvedSourceIds[[string]$sourceId] = $true
        }
        Write-Host ("Approved sources loaded: {0} known IDs." -f $approvedSourceIds.Count)
    } catch {
        $host.UI.WriteErrorLine(("Failed to parse approved-sources.json: {0}" -f $_.Exception.Message))
        exit 1
    }
}

# ---------------------------------------------------------------------------
# Per-rule validation
# ---------------------------------------------------------------------------
$failures  = New-Object System.Collections.Generic.List[string]
$warnings  = New-Object System.Collections.Generic.List[string]
$seenIds   = @{}

foreach ($rule in @($raw.rules)) {
    $ruleId = if ($null -ne $rule.PSObject.Properties["id"]) { [string]$rule.id } else { "<missing-id>" }
    $p = "Rule '$ruleId'"
    $effectiveState = if ($null -ne $rule.PSObject.Properties["state"] -and [string]$rule.state -in $validStates) {
        [string]$rule.state
    } elseif ($null -ne $rule.PSObject.Properties["enabled"]) {
        if ([bool]$rule.enabled) { "active" } else { "disabled" }
    } else {
        "active"
    }

    # 1. Required base fields
    foreach ($field in $requiredBaseFields) {
        if ($null -eq $rule.PSObject.Properties[$field]) {
            $failures.Add(("{0}: missing required field '{1}'." -f $p, $field))
        }
    }

    # 2. Unique IDs
    if ($ruleId -ne "<missing-id>") {
        if ($seenIds.ContainsKey($ruleId)) {
            $failures.Add(("Duplicate rule id '{0}'." -f $ruleId))
        } else {
            $seenIds[$ruleId] = $true
        }
    }

    # 3. Valid enum values
    if ($null -ne $rule.PSObject.Properties["category"] -and [string]$rule.category -notin $validCategories) {
        $failures.Add(("{0}: invalid category '{1}'. Valid: {2}." -f $p, [string]$rule.category, ($validCategories -join ", ")))
    }
    if ($null -ne $rule.PSObject.Properties["severity"] -and [string]$rule.severity -notin $validSeverities) {
        $failures.Add(("{0}: invalid severity '{1}'. Valid: {2}." -f $p, [string]$rule.severity, ($validSeverities -join ", ")))
    }
    if ($null -ne $rule.PSObject.Properties["state"] -and [string]$rule.state -notin $validStates) {
        $failures.Add(("{0}: invalid state '{1}'. Valid: {2}." -f $p, [string]$rule.state, ($validStates -join ", ")))
    }
    $engine = if ($null -ne $rule.PSObject.Properties["engine"]) { [string]$rule.engine } else { "coded" }
    if ($engine -notin $validEngines) {
        $failures.Add(("{0}: invalid engine '{1}'. Valid: {2}." -f $p, $engine, ($validEngines -join ", ")))
    }
    if ($null -ne $rule.PSObject.Properties["match_kind"] -and [string]$rule.match_kind -notin $validMatchKinds) {
        $failures.Add(("{0}: invalid match_kind '{1}'. Valid: {2}." -f $p, [string]$rule.match_kind, ($validMatchKinds -join ", ")))
    }

    if ($effectiveState -eq "active") {
        foreach ($field in $requiredActiveFields) {
            if ($null -eq $rule.PSObject.Properties[$field]) {
                $failures.Add(("{0} (active): missing required field '{1}'." -f $p, $field))
            }
        }

        if ($null -ne $rule.PSObject.Properties["detector_family"] -and [string]::IsNullOrWhiteSpace([string]$rule.detector_family)) {
            $failures.Add(("{0}: detector_family must be non-empty for active rules." -f $p))
        }
        if ($null -ne $rule.PSObject.Properties["remediation"] -and [string]::IsNullOrWhiteSpace([string]$rule.remediation)) {
            $failures.Add(("{0}: remediation must be non-empty for active rules." -f $p))
        }
        if ($null -ne $rule.PSObject.Properties["test_ideas"] -and @($rule.test_ideas).Count -eq 0) {
            $failures.Add(("{0}: test_ideas must contain at least one entry for active rules." -f $p))
        }
        if ($null -ne $rule.PSObject.Properties["match_confidence"] -and [string]$rule.match_confidence -notin $validMatchConfidences) {
            $failures.Add(("{0}: invalid match_confidence '{1}'. Valid: {2}." -f $p, [string]$rule.match_confidence, ($validMatchConfidences -join ", ")))
        }

        if ($null -ne $rule.PSObject.Properties["surface_scope"]) {
            $surfaceValues = @()
            $surfaceRaw = $rule.surface_scope
            if ($surfaceRaw -is [System.Collections.IEnumerable] -and -not ($surfaceRaw -is [string])) {
                $surfaceValues = @($surfaceRaw | ForEach-Object { [string]$_ })
            } elseif (-not [string]::IsNullOrWhiteSpace([string]$surfaceRaw)) {
                $surfaceValues = @([string]$surfaceRaw)
            }

            if ($surfaceValues.Count -eq 0) {
                $failures.Add(("{0}: surface_scope must contain at least one value for active rules." -f $p))
            } else {
                foreach ($scope in $surfaceValues) {
                    if ($scope -notin $validSurfaceScopes) {
                        $failures.Add(("{0}: invalid surface_scope value '{1}'. Valid: {2}." -f $p, $scope, ($validSurfaceScopes -join ", ")))
                    }
                }
            }
        }
    }

    # 4+5. Declarative-only requirements
    if ($engine -eq "declarative") {
        foreach ($field in $requiredDeclarativeFields) {
            if ($null -eq $rule.PSObject.Properties[$field]) {
                $failures.Add(("{0} (declarative): missing required field '{1}'." -f $p, $field))
            }
        }
        # Soft warning for non-active declarative rules with empty ideas; active rules already fail above.
        if ($effectiveState -ne "active" -and $null -ne $rule.PSObject.Properties["test_ideas"] -and @($rule.test_ideas).Count -eq 0) {
            $warnings.Add(("{0}: test_ideas is empty — add at least one test idea to guide future coverage." -f $p))
        }
        if ($null -ne $rule.PSObject.Properties["pattern"]) {
            $pat = [string]$rule.pattern
            if ([string]::IsNullOrWhiteSpace($pat)) {
                $failures.Add(("{0}: pattern must be non-empty for declarative rules." -f $p))
            } else {
                try {
                    $null = [System.Text.RegularExpressions.Regex]::new($pat)
                } catch {
                    $failures.Add(("{0}: pattern does not compile as .NET regex — {1}" -f $p, $_.Exception.Message))
                }
            }
        }
    }

    # 6. source_ids resolve in approved sources
    if ($approvedSourceIds.Count -gt 0 -and $null -ne $rule.PSObject.Properties["source_ids"]) {
        foreach ($sid in @($rule.source_ids)) {
            $sidStr = [string]$sid
            if (-not [string]::IsNullOrWhiteSpace($sidStr) -and -not $approvedSourceIds.ContainsKey($sidStr)) {
                $failures.Add(("{0}: source_id '{1}' not found in approved sources." -f $p, $sidStr))
            }
        }
    }
}

# ---------------------------------------------------------------------------
# Result
# ---------------------------------------------------------------------------
$ruleCount = @($raw.rules).Count
Write-Host ("Validated {0} rule(s) from: {1}" -f $ruleCount, $resolvedCatalogPath)

if ($warnings.Count -gt 0) {
    foreach ($w in $warnings) {
        Write-Host ("  [WARN] {0}" -f $w) -ForegroundColor Yellow
    }
}

if ($failures.Count -eq 0) {
    $suffix = if ($warnings.Count -gt 0) { " ({0} warning(s))." -f $warnings.Count } else { "." }
    Write-Host ("All checks passed{0}" -f $suffix) -ForegroundColor Green
    exit 0
}

Write-Host ("{0} validation error(s):" -f $failures.Count) -ForegroundColor Red
foreach ($f in $failures) {
    Write-Host ("  [ERROR] {0}" -f $f) -ForegroundColor Red
}
exit 1
