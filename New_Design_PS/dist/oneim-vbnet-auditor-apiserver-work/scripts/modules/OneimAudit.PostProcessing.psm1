Set-StrictMode -Version Latest

function Get-OneImAuditSuppressions {
    param(
        [Parameter()]
        [string]$SuppressionsFile
    )

    if ([string]::IsNullOrWhiteSpace($SuppressionsFile)) {
        return @()
    }

    $fullPath = Get-OneImAuditFullPath -Path $SuppressionsFile
    $raw = Get-Content -LiteralPath $fullPath -Raw | ConvertFrom-Json
    if ($null -eq $raw.PSObject.Properties["suppressions"]) {
        throw "Suppressions file '$fullPath' must contain a top-level 'suppressions' array."
    }

    $items = New-Object System.Collections.Generic.List[object]
    foreach ($suppression in @($raw.suppressions)) {
        if ($null -eq $suppression.PSObject.Properties["justification"]) {
            throw "Each suppression entry must include a justification."
        }

        $ruleId = if ($null -ne $suppression.PSObject.Properties["rule_id"]) { [string]$suppression.rule_id } else { "*" }
        $pathGlob = if ($null -ne $suppression.PSObject.Properties["path_glob"]) { [string]$suppression.path_glob } else { "*" }
        $items.Add([pscustomobject]@{
                rule_id = if ([string]::IsNullOrWhiteSpace($ruleId)) { "*" } else { $ruleId }
                path_glob = if ([string]::IsNullOrWhiteSpace($pathGlob)) { "*" } else { $pathGlob }
                justification = [string]$suppression.justification
            })
    }

    return $items.ToArray()
}

function Find-OneImAuditMatchingSuppression {
    param(
        [Parameter(Mandatory)]
        [object]$Finding,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$Suppressions
    )

    $normalizedFindingPath = Normalize-OneImAuditRelativePath -Path $Finding.relative_path

    foreach ($suppression in @($Suppressions)) {
        $ruleMatches = ($suppression.rule_id -eq "*" -or $suppression.rule_id -eq $Finding.rule_id)
        $normalizedGlob = Normalize-OneImAuditRelativePath -Path $suppression.path_glob
        $pathMatches = ($normalizedGlob -eq "*" -or $normalizedFindingPath -like $normalizedGlob)
        if ($ruleMatches -and $pathMatches) {
            return $suppression
        }
    }

    return $null
}

function Copy-OneImAuditFindingWithExtras {
    param(
        [Parameter(Mandatory)]
        [object]$Finding,

        [Parameter()]
        [hashtable]$Extra = @{}
    )

    $copy = [ordered]@{}
    foreach ($property in $Finding.PSObject.Properties) {
        $copy[$property.Name] = $property.Value
    }

    foreach ($key in $Extra.Keys) {
        $copy[$key] = $Extra[$key]
    }

    return [pscustomobject]$copy
}

function Invoke-OneImAuditPostProcessing {
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$Findings,

        [Parameter(Mandatory)]
        [hashtable]$RuleCatalog,

        [Parameter()]
        [AllowEmptyCollection()]
        [object[]]$Suppressions = @()
    )

    $active = New-Object System.Collections.Generic.List[object]
    $suppressed = New-Object System.Collections.Generic.List[object]

    foreach ($finding in @($Findings)) {
        $finding.relative_path = Normalize-OneImAuditRelativePath -Path $finding.relative_path
        $match = Find-OneImAuditMatchingSuppression -Finding $finding -Suppressions $Suppressions
        if ($null -ne $match) {
            $suppressed.Add((Copy-OneImAuditFindingWithExtras -Finding $finding -Extra @{
                        suppressed = $true
                        suppression_justification = $match.justification
                        suppression_rule_id = $match.rule_id
                        suppression_path_glob = $match.path_glob
                    }))
        }
        else {
            $active.Add((Copy-OneImAuditFindingWithExtras -Finding $finding -Extra @{ suppressed = $false }))
        }
    }

    $reported = New-Object System.Collections.Generic.List[object]
    $omitted = New-Object System.Collections.Generic.List[object]
    $grouped = @{}

    foreach ($finding in $active.ToArray()) {
        $groupKey = "{0}|{1}" -f $finding.relative_path, $finding.rule_id
        if (-not $grouped.ContainsKey($groupKey)) {
            $grouped[$groupKey] = New-Object System.Collections.Generic.List[object]
        }

        $grouped[$groupKey].Add($finding)
    }

    foreach ($entry in $grouped.GetEnumerator()) {
        $groupItems = @($entry.Value.ToArray() | Sort-Object line, evidence)
        if ($groupItems.Count -eq 0) {
            continue
        }

        $rule = $RuleCatalog[$groupItems[0].rule_id]
        $limit = 0
        if ($null -ne $rule -and $null -ne $rule.PSObject.Properties["MaxExamplesPerFile"]) {
            $limit = [int]$rule.MaxExamplesPerFile
        }

        if ($limit -gt 0 -and $groupItems.Count -gt $limit) {
            foreach ($item in $groupItems[0..($limit - 1)]) {
                $reported.Add($item)
            }

            $omittedCount = $groupItems.Count - $limit
            $omitted.Add([pscustomobject]@{
                    rule_id = $groupItems[0].rule_id
                    relative_path = $groupItems[0].relative_path
                    total_detected = $groupItems.Count
                    reported_examples = $limit
                    omitted_examples = $omittedCount
                })
        }
        else {
            foreach ($item in $groupItems) {
                $reported.Add($item)
            }
        }
    }

    $omittedExampleCount = 0
    foreach ($summary in $omitted.ToArray()) {
        $omittedExampleCount += [int]$summary.omitted_examples
    }

    return [pscustomobject]@{
        detected_findings = @($Findings)
        reported_findings = @($reported.ToArray() | Sort-Object relative_path, line, rule_id)
        suppressed_findings = @($suppressed.ToArray() | Sort-Object relative_path, line, rule_id)
        omitted_example_summaries = @($omitted.ToArray() | Sort-Object relative_path, rule_id)
        detected_finding_count = @($Findings).Count
        reported_finding_count = $reported.Count
        suppressed_finding_count = $suppressed.Count
        omitted_example_count = $omittedExampleCount
    }
}

Export-ModuleMember -Function `
    Get-OneImAuditSuppressions, `
    Find-OneImAuditMatchingSuppression, `
    Copy-OneImAuditFindingWithExtras, `
    Invoke-OneImAuditPostProcessing
