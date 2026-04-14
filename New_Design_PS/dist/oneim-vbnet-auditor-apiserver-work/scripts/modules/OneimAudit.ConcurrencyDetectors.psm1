Set-StrictMode -Version Latest

# ---------------------------------------------------------------------------
# CNC601 — BeginTransaction without Commit or Rollback in scope
# ---------------------------------------------------------------------------
function Get-OneImCncBeginTransactionFindings {
    <#
    .SYNOPSIS
    Detects BeginTransaction calls that have no visible Commit or Rollback within
    the next 60 lines (CNC601) or that appear a second time before a Commit (CNC602).
    Returns finding objects suitable for direct addition to a findings list.
    #>
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [string[]]$Lines,

        [Parameter(Mandatory)]
        [string]$FilePath,

        [Parameter(Mandatory)]
        [string]$RelativePath,

        [Parameter(Mandatory)]
        [hashtable]$RuleCatalog,

        [Parameter(Mandatory)]
        [hashtable]$SourceLookup
    )

    $findings = New-Object System.Collections.Generic.List[object]
    $seen601  = @{}
    $seen602  = @{}

    $openCount = 0   # running count of BeginTransaction calls without a matching Commit/Rollback
    $commitPattern = "(?i)\b(CommitTransaction|Commit|RollbackTransaction|Rollback)\b"
    $beginPattern  = "(?i)\bBeginTransaction\b"

    for ($i = 0; $i -lt $Lines.Count; $i++) {
        $line = $Lines[$i]

        if ($line -match $commitPattern) {
            if ($openCount -gt 0) { $openCount-- }
            continue
        }

        if ($line -notmatch $beginPattern) { continue }

        # This line has BeginTransaction
        $lineNumber = $i + 1
        $evidence   = $line.Trim()

        # CNC602: second open transaction before prior one closed
        if ($openCount -gt 0 -and $RuleCatalog.ContainsKey("CNC602") -and -not $seen602.ContainsKey($lineNumber)) {
            $seen602[$lineNumber] = $true
            $f602 = New-OneImConcurrencyFinding `
                -RuleId "CNC602" -RuleCatalog $RuleCatalog -SourceLookup $SourceLookup `
                -FilePath $FilePath -RelativePath $RelativePath -Line $lineNumber `
                -Evidence $evidence `
                -TriggeringScenario "A second BeginTransaction was found while a prior transaction was still open (no intervening Commit or Rollback). Most providers do not support nested transactions." `
                -Remediation "Commit or roll back the first transaction before starting a new one, or restructure the logic to avoid nested transaction scopes."
            $findings.Add($f602)
        }

        $openCount++

        # CNC601: look forward up to 60 lines for a Commit/Rollback
        if (-not $RuleCatalog.ContainsKey("CNC601")) { continue }
        if ($seen601.ContainsKey($lineNumber)) { continue }

        $hasClose = $false
        $lookEnd  = [Math]::Min($Lines.Count - 1, $i + 60)
        for ($j = $i + 1; $j -le $lookEnd; $j++) {
            if ($Lines[$j] -match $commitPattern) { $hasClose = $true; break }
        }

        if (-not $hasClose) {
            $seen601[$lineNumber] = $true
            $f601 = New-OneImConcurrencyFinding `
                -RuleId "CNC601" -RuleCatalog $RuleCatalog -SourceLookup $SourceLookup `
                -FilePath $FilePath -RelativePath $RelativePath -Line $lineNumber `
                -Evidence $evidence `
                -TriggeringScenario "BeginTransaction was called but no CommitTransaction, Commit, or Rollback was found within the next 60 lines, which may indicate an unclosed transaction that holds locks." `
                -Remediation "Ensure every BeginTransaction is followed by a CommitTransaction or RollbackTransaction in all code paths, ideally inside a Try/Finally block."
            $findings.Add($f601)
        }
    }

    return $findings.ToArray()
}

# ---------------------------------------------------------------------------
# Internal factory — avoids coupling to New-OneImAuditFinding signature
# ---------------------------------------------------------------------------
function New-OneImConcurrencyFinding {
    param(
        [string]$RuleId, [hashtable]$RuleCatalog, [hashtable]$SourceLookup,
        [string]$FilePath, [string]$RelativePath, [int]$Line,
        [string]$Evidence, [string]$TriggeringScenario, [string]$Remediation
    )

    # Resolve source references from SourceLookup
    $sources = @()
    if ($RuleCatalog.ContainsKey($RuleId)) {
        $rule = $RuleCatalog[$RuleId]
        if ($null -ne $rule.PSObject.Properties["source_ids"]) {
            foreach ($sid in @($rule.source_ids)) {
                if ($SourceLookup.ContainsKey($sid)) {
                    $sources += $SourceLookup[$sid]
                }
            }
        }
    }

    $severity = "medium"
    $title    = $RuleId
    if ($RuleCatalog.ContainsKey($RuleId)) {
        $r = $RuleCatalog[$RuleId]
        if ($null -ne $r.PSObject.Properties["severity"]) { $severity = [string]$r.severity }
        if ($null -ne $r.PSObject.Properties["title"])    { $title    = [string]$r.title    }
    }

    return [pscustomobject]@{
        rule_id              = $RuleId
        title                = $title
        severity             = $severity
        file_path            = $FilePath
        relative_path        = $RelativePath
        line                 = $Line
        evidence             = $Evidence
        triggering_scenario  = $TriggeringScenario
        remediation          = $Remediation
        test_ideas           = @()
        sources              = $sources
    }
}

# ---------------------------------------------------------------------------
# Public entry point: Get-OneImConcurrencyFindings
# Called from Get-OneImFileFindings for CNC-family coded rules.
# ---------------------------------------------------------------------------
function Get-OneImConcurrencyFindings {
    <#
    .SYNOPSIS
    Runs all coded CNC-family concurrency detectors against one file's lines.
    Returns an array of finding objects (may be empty).
    #>
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [string[]]$Lines,

        [Parameter(Mandatory)]
        [string]$FilePath,

        [Parameter(Mandatory)]
        [string]$RelativePath,

        [Parameter(Mandatory)]
        [hashtable]$RuleCatalog,

        [Parameter(Mandatory)]
        [hashtable]$SourceLookup
    )

    $all = New-Object System.Collections.Generic.List[object]

    # CNC601 + CNC602 (transaction balance)
    if ($RuleCatalog.ContainsKey("CNC601") -or $RuleCatalog.ContainsKey("CNC602")) {
        $txFindings = @(Get-OneImCncBeginTransactionFindings `
            -Lines $Lines -FilePath $FilePath -RelativePath $RelativePath `
            -RuleCatalog $RuleCatalog -SourceLookup $SourceLookup)
        foreach ($f in $txFindings) { $all.Add($f) }
    }

    return $all.ToArray()
}

Export-ModuleMember -Function Get-OneImConcurrencyFindings
