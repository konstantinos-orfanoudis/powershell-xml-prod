Set-StrictMode -Version Latest

function Get-OneImAuditOIM520Finding {
    param(
        [Parameter(Mandatory)]
        [string]$LineText,

        [Parameter(Mandatory)]
        [int]$LineNumber,

        [Parameter(Mandatory)]
        [string]$FilePath,

        [Parameter(Mandatory)]
        [string]$RelativePath,

        [Parameter(Mandatory)]
        [hashtable]$RuleCatalog,

        [Parameter(Mandatory)]
        [hashtable]$SourceLookup
    )

    if (-not $RuleCatalog.ContainsKey("OIM520")) { return $null }
    if ($LineText.TrimStart().StartsWith("'")) { return $null }
    if ($LineText -notmatch '(?i)\b(GetListFor|GetSingleProperty)\s*\(') { return $null }

    return New-OneImAuditFinding -RuleId "OIM520" -RuleCatalog $RuleCatalog -SourceLookup $SourceLookup -FilePath $FilePath -RelativePath $RelativePath -Line $LineNumber `
        -Evidence $LineText.Trim() `
        -TriggeringScenario "GetListFor and GetSingleProperty each issue at least one database round-trip per loop iteration, which creates an N+1 pattern in OneIM hot paths." `
        -Remediation "Load the needed values before the loop or switch to a bulk-read pattern so the loop works against in-memory data instead of repeated database calls." `
        -TestIdeas @(
            "Enable SQL trace logging and confirm the loop no longer issues one query per iteration.",
            "Benchmark the code path before and after moving the lookup outside the loop."
        )
}

function Get-OneImAuditPER451Finding {
    param(
        [Parameter(Mandatory)]
        [string]$LineText,

        [Parameter(Mandatory)]
        [int]$LineNumber,

        [Parameter(Mandatory)]
        [string]$FilePath,

        [Parameter(Mandatory)]
        [string]$RelativePath,

        [Parameter(Mandatory)]
        [hashtable]$RuleCatalog,

        [Parameter(Mandatory)]
        [hashtable]$SourceLookup
    )

    if (-not $RuleCatalog.ContainsKey("PER451")) { return $null }
    if ($LineText.TrimStart().StartsWith("'")) { return $null }
    if ($LineText -notmatch '(?i)\.Create\s*\(\s*Session\b') { return $null }

    return New-OneImAuditFinding -RuleId "PER451" -RuleCatalog $RuleCatalog -SourceLookup $SourceLookup -FilePath $FilePath -RelativePath $RelativePath -Line $LineNumber `
        -Evidence $LineText.Trim() `
        -TriggeringScenario "Calling .Create(Session) inside a loop inflates each row into a full entity with an extra database round-trip per iteration." `
        -Remediation "Select the needed columns up front and read them from the collection element directly instead of calling .Create(Session) inside the loop." `
        -TestIdeas @(
            "Compare elapsed time and SQL round-trip count before and after removing .Create(Session) from the loop.",
            "Verify the query now selects only the columns the loop actually reads."
        )
}

function Get-OneImAuditOIM597Finding {
    param(
        [Parameter(Mandatory)]
        [string]$LineText,

        [Parameter(Mandatory)]
        [int]$LineNumber,

        [Parameter(Mandatory)]
        [string]$FilePath,

        [Parameter(Mandatory)]
        [string]$RelativePath,

        [Parameter(Mandatory)]
        [hashtable]$RuleCatalog,

        [Parameter(Mandatory)]
        [hashtable]$SourceLookup
    )

    if (-not $RuleCatalog.ContainsKey("OIM597")) { return $null }
    if ($LineText.TrimStart().StartsWith("'")) { return $null }
    if ($LineText -notmatch '(?i)\b(TryGet|TryGetSingleValue|TryGetSingleFiltered)\s*\(') { return $null }

    $callName = $Matches[1]
    return New-OneImAuditFinding -RuleId "OIM597" -RuleCatalog $RuleCatalog -SourceLookup $SourceLookup -FilePath $FilePath -RelativePath $RelativePath -Line $LineNumber `
        -Evidence $LineText.Trim() `
        -TriggeringScenario ("'$callName' is called inside a loop, issuing one SELECT per object and creating an N+1 read pattern.") `
        -Remediation "Move the lookup outside the loop with GetCollection or GetCollectionFiltered, then use an in-memory lookup inside the loop." `
        -TestIdeas @(
            "Enable SQL logging and confirm the loop now produces one bulk read instead of N individual lookups.",
            "Benchmark the loop with a larger input set and compare elapsed time before and after the refactor."
        )
}

function Get-OneImAuditOIM555Finding {
    param(
        [Parameter(Mandatory)]
        [string]$LineText,

        [Parameter(Mandatory)]
        [int]$LineNumber,

        [Parameter(Mandatory)]
        [string]$FilePath,

        [Parameter(Mandatory)]
        [string]$RelativePath,

        [Parameter(Mandatory)]
        [hashtable]$RuleCatalog,

        [Parameter(Mandatory)]
        [hashtable]$SourceLookup
    )

    if (-not $RuleCatalog.ContainsKey("OIM555")) { return $null }
    if ($LineText.TrimStart().StartsWith("'")) { return $null }
    if ($LineText -notmatch '(?i)\.Save\s*\(\s*Session\b') { return $null }

    return New-OneImAuditFinding -RuleId "OIM555" -RuleCatalog $RuleCatalog -SourceLookup $SourceLookup -FilePath $FilePath -RelativePath $RelativePath -Line $LineNumber `
        -Evidence $LineText.Trim() `
        -TriggeringScenario "Calling .Save(Session) inside a loop issues one write per object instead of batching the work, multiplying round-trips with the object count." `
        -Remediation "Collect the changes in a UnitOfWork and commit once after the loop so the database work is batched." `
        -TestIdeas @(
            "Enable SQL logging and compare statement count before and after switching to UnitOfWork.",
            "Measure elapsed time with a representative object set before and after the batching change."
        )
}

Export-ModuleMember -Function `
    Get-OneImAuditOIM520Finding, `
    Get-OneImAuditPER451Finding, `
    Get-OneImAuditOIM597Finding, `
    Get-OneImAuditOIM555Finding
