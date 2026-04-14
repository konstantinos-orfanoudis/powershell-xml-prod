Set-StrictMode -Version Latest

function Get-OneImAuditSourceLookup {
    param(
        [Parameter(Mandatory)]
        [string]$ApprovedSourcesPath
    )

    $approvedSourcesRoot = Split-Path -Parent $ApprovedSourcesPath
    $raw = Get-Content -LiteralPath $ApprovedSourcesPath -Raw | ConvertFrom-Json
    $lookup = @{}

    $allSources = New-Object 'System.Collections.Generic.List[object]'
    foreach ($source in @($raw.sources)) {
        $allSources.Add($source)
    }

    if ($null -ne $raw.PSObject.Properties["source_index_files"]) {
        foreach ($indexFile in @($raw.source_index_files)) {
            $indexFilePath = [string]$indexFile
            if ([string]::IsNullOrWhiteSpace($indexFilePath)) {
                continue
            }

            $resolvedIndexPath = if ([System.IO.Path]::IsPathRooted($indexFilePath)) {
                $indexFilePath
            } else {
                Join-Path $approvedSourcesRoot $indexFilePath
            }

            if (-not (Test-Path -LiteralPath $resolvedIndexPath)) {
                Write-Warning ("Approved source index file not found: {0}" -f $resolvedIndexPath)
                continue
            }

            $indexRaw = Get-Content -LiteralPath $resolvedIndexPath -Raw | ConvertFrom-Json
            foreach ($source in @($indexRaw.sources)) {
                $allSources.Add($source)
            }
        }
    }

    foreach ($source in $allSources) {
        if ($null -eq $source.PSObject.Properties["id"] -or [string]::IsNullOrWhiteSpace([string]$source.id)) {
            continue
        }

        $lookup[[string]$source.id] = $source
    }

    return $lookup
}

function Get-OneImAuditRuleEffectiveState {
    param(
        [Parameter(Mandatory)]
        [object]$Rule
    )

    if ($null -ne $Rule.PSObject.Properties["state"]) {
        $s = [string]$Rule.state
        if ($s -in @("active", "draft", "disabled")) {
            return $s
        }
    }

    # Backward compat: derive from enabled
    if ($null -ne $Rule.PSObject.Properties["enabled"]) {
        return if ([bool]$Rule.enabled) { "active" } else { "disabled" }
    }

    return "active"
}

function Get-OneImAuditRuleCatalog {
    param(
        [Parameter(Mandatory)]
        [string]$RuleCatalogPath,

        [Parameter()]
        [ValidateSet("All", "Active", "Draft", "Disabled")]
        [string]$RuleState = "Active"
    )

    $raw = Get-Content -LiteralPath $RuleCatalogPath -Raw | ConvertFrom-Json
    $lookup = @{}
    $ruleIndex = 0
    foreach ($rule in @($raw.rules)) {
        $ruleIndex++
        $effectiveState = Get-OneImAuditRuleEffectiveState -Rule $rule

        $include = switch ($RuleState) {
            "All"      { $true }
            "Active"   { $effectiveState -eq "active" }
            "Draft"    { $effectiveState -eq "draft" }
            "Disabled" { $effectiveState -eq "disabled" }
        }

        if (-not $include) {
            continue
        }

        foreach ($requiredField in @("id", "title", "category", "severity", "confidence", "why", "source_ids")) {
            if ($null -eq $rule.PSObject.Properties[$requiredField]) {
                throw ("Rule entry #{0} is missing required field '{1}'." -f $ruleIndex, $requiredField)
            }
        }
        if ($effectiveState -eq "active") {
            foreach ($requiredField in @("detector_family", "remediation", "test_ideas", "surface_scope", "match_confidence")) {
                if ($null -eq $rule.PSObject.Properties[$requiredField]) {
                    throw ("Rule entry #{0} ({1}) is missing active-rule field '{2}'." -f $ruleIndex, [string]$rule.id, $requiredField)
                }
            }
        }

        $engine = if ($null -ne $rule.PSObject.Properties["engine"]) { [string]$rule.engine } else { "coded" }

        $ruleObj = [ordered]@{
            Id                 = [string]$rule.id
            Title              = [string]$rule.title
            Category           = [string]$rule.category
            Severity           = [string]$rule.severity
            Confidence         = [int]$rule.confidence
            Enabled            = [bool]($null -ne $rule.PSObject.Properties["enabled"] -and [bool]$rule.enabled)
            State              = $effectiveState
            Engine             = $engine
            DetectorFamily     = if ($null -ne $rule.PSObject.Properties["detector_family"]) { [string]$rule.detector_family } else { "" }
            MaxExamplesPerFile = if ($null -ne $rule.PSObject.Properties["max_examples_per_file"]) { [int]$rule.max_examples_per_file } else { 0 }
            Why                = [string]$rule.why
            ReviewNotes        = if ($null -ne $rule.PSObject.Properties["review_notes"]) { [string]$rule.review_notes } else { "" }
            SourceIds          = @($rule.source_ids)
            SurfaceScope       = @()
            MatchConfidence    = if ($null -ne $rule.PSObject.Properties["match_confidence"]) { [string]$rule.match_confidence } else { "" }
            # Declarative rule fields (populated below for engine=declarative; empty defaults for coded)
            MatchKind          = ""
            Pattern            = ""
            TriggeringScenario = ""
            Remediation        = if ($null -ne $rule.PSObject.Properties["remediation"]) { [string]$rule.remediation } else { "" }
            TestIdeas          = if ($null -ne $rule.PSObject.Properties["test_ideas"]) { @($rule.test_ideas) } else { @() }
            IncludePaths       = @()
            ExcludePaths       = @()
        }

        if ($null -ne $rule.PSObject.Properties["surface_scope"]) {
            $surfaceRaw = $rule.surface_scope
            if ($surfaceRaw -is [System.Collections.IEnumerable] -and -not ($surfaceRaw -is [string])) {
                $ruleObj.SurfaceScope = @($surfaceRaw | ForEach-Object { [string]$_ } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
            } elseif (-not [string]::IsNullOrWhiteSpace([string]$surfaceRaw)) {
                $ruleObj.SurfaceScope = @([string]$surfaceRaw)
            }
        }

        if ($engine -eq "declarative") {
            $ruleObj.MatchKind          = if ($null -ne $rule.PSObject.Properties["match_kind"]) { [string]$rule.match_kind } else { "" }
            $ruleObj.Pattern            = if ($null -ne $rule.PSObject.Properties["pattern"]) { [string]$rule.pattern } else { "" }
            $ruleObj.TriggeringScenario = if ($null -ne $rule.PSObject.Properties["triggering_scenario"]) { [string]$rule.triggering_scenario } else { "" }
            $ruleObj.IncludePaths       = if ($null -ne $rule.PSObject.Properties["include_paths"]) { @($rule.include_paths) } else { @() }
            $ruleObj.ExcludePaths       = if ($null -ne $rule.PSObject.Properties["exclude_paths"]) { @($rule.exclude_paths) } else { @() }
        }

        $lookup[[string]$rule.id] = [pscustomobject]$ruleObj
    }

    return $lookup
}

function Get-OneImAuditRuleList {
    param(
        [Parameter(Mandatory)]
        [hashtable]$RuleCatalog
    )

    return @($RuleCatalog.GetEnumerator() | Sort-Object Name | ForEach-Object { $_.Value })
}

function Resolve-OneImAuditRuleSources {
    param(
        [Parameter(Mandatory)]
        [object]$Rule,

        [Parameter(Mandatory)]
        [hashtable]$SourceLookup
    )

    $items = @()
    foreach ($sourceId in $Rule.SourceIds) {
        if ($SourceLookup.ContainsKey($sourceId)) {
            $items += [pscustomobject]@{
                id    = $sourceId
                title = [string]$SourceLookup[$sourceId].title
                url   = [string]$SourceLookup[$sourceId].url
            }
        }
    }

    return $items
}

function Test-OneImAuditRuleSurfaceMatch {
    param(
        [Parameter(Mandatory)]
        [object]$Rule,

        [Parameter()]
        [string]$Surface = "any"
    )

    $normalizedSurface = if ([string]::IsNullOrWhiteSpace($Surface)) { "any" } else { $Surface.ToLowerInvariant() }
    $allowed = @($Rule.SurfaceScope | ForEach-Object { [string]$_ } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object { $_.ToLowerInvariant() })
    if ($allowed.Count -eq 0 -or $allowed -contains "any") {
        return $true
    }

    return ($allowed -contains $normalizedSurface)
}

function Test-OneImAuditGatingFinding {
    param(
        [Parameter(Mandatory)]
        [AllowNull()]
        [object]$Finding
    )

    return (
        $Finding.severity -in @("high", "medium") -and
        $Finding.confidence_label -in @("high", "medium")
    )
}

function New-OneImAuditFinding {
    param(
        [Parameter(Mandatory)]
        [string]$RuleId,

        [Parameter(Mandatory)]
        [hashtable]$RuleCatalog,

        [Parameter(Mandatory)]
        [hashtable]$SourceLookup,

        [Parameter(Mandatory)]
        [string]$FilePath,

        [Parameter(Mandatory)]
        [string]$RelativePath,

        [Parameter(Mandatory)]
        [int]$Line,

        [Parameter(Mandatory)]
        [string]$Evidence,

        [Parameter(Mandatory)]
        [string]$TriggeringScenario,

        [Parameter(Mandatory)]
        [string]$Remediation,

        [Parameter(Mandatory)]
        [string[]]$TestIdeas,

        [Parameter()]
        [string[]]$UnresolvedQuestions = @(),

        [Parameter()]
        [hashtable]$Extra = @{}
    )

    $rule = $RuleCatalog[$RuleId]
    if ($null -eq $rule) {
        throw "Unknown rule id: $RuleId"
    }

    $fileSurface = Get-OneImAuditDetectedSurface -RelativePath $RelativePath
    if (-not (Test-OneImAuditRuleSurfaceMatch -Rule $rule -Surface $fileSurface)) {
        return $null
    }

    $resolvedConfidence = [int]$rule.Confidence
    if ($Extra.ContainsKey("confidence_score")) {
        $resolvedConfidence = [int]$Extra["confidence_score"]
    }

    $resolvedRemediation = if ([string]::IsNullOrWhiteSpace($Remediation)) { [string]$rule.Remediation } else { $Remediation }
    $resolvedTestIdeas = if ($null -eq $TestIdeas -or @($TestIdeas).Count -eq 0) { @($rule.TestIdeas) } else { @($TestIdeas) }

    $finding = [ordered]@{
        rule_id             = $rule.Id
        title               = $rule.Title
        category            = $rule.Category
        severity            = $rule.Severity
        confidence_score    = $resolvedConfidence
        confidence_label    = Get-OneImAuditConfidenceLabel -Score $resolvedConfidence
        gating              = $false
        detector_family     = $rule.DetectorFamily
        surface_scope       = @($rule.SurfaceScope)
        match_confidence    = $rule.MatchConfidence
        file_path           = $FilePath
        relative_path       = $RelativePath
        line                = $Line
        evidence            = $Evidence
        triggering_scenario = $TriggeringScenario
        remediation         = $resolvedRemediation
        test_ideas          = @($resolvedTestIdeas)
        unresolved_questions = @($UnresolvedQuestions)
        rationale           = $rule.Why
        review_notes        = $rule.ReviewNotes
        sources             = Resolve-OneImAuditRuleSources -Rule $rule -SourceLookup $SourceLookup
    }

    foreach ($key in $Extra.Keys) {
        $finding[$key] = $Extra[$key]
    }

    $object = [pscustomobject]$finding
    $object.gating = Test-OneImAuditGatingFinding -Finding $object
    return $object
}

function Add-OneImAuditFinding {
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [System.Collections.Generic.List[object]]$Findings,

        [Parameter(Mandatory)]
        [hashtable]$Seen,

        [Parameter(Mandatory)]
        [AllowNull()]
        [object]$Finding
    )

    if ($null -eq $Finding) {
        return
    }

    $key = "{0}|{1}|{2}|{3}" -f $Finding.rule_id, $Finding.relative_path, $Finding.line, $Finding.evidence
    if (-not $Seen.ContainsKey($key)) {
        $Seen[$key] = $true
        $Findings.Add($Finding)
    }
}

function ConvertTo-OneImAuditRuleMarkdown {
    param(
        [Parameter(Mandatory)]
        [hashtable]$RuleCatalog,

        [Parameter(Mandatory)]
        [hashtable]$SourceLookup
    )

    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add("# OneIM Audit Rules")
    $lines.Add("")
    $lines.Add("| Id | State | Engine | Category | Severity | Confidence | Match Confidence | Surface Scope | Max Examples/File | Detector Family | Why | Match Kind | Pattern | Triggering Scenario | Remediation | Sources | Notes |")
    $lines.Add("|---|---|---|---|---|---:|---|---|---:|---|---|---|---|---|---|---|---|")

    foreach ($rule in Get-OneImAuditRuleList -RuleCatalog $RuleCatalog) {
        $sources = @()
        foreach ($source in Resolve-OneImAuditRuleSources -Rule $rule -SourceLookup $SourceLookup) {
            $sources += "[{0}]({1})" -f $source.id, $source.url
        }

        $row = "| {0} | {1} | {2} | {3} | {4} | {5} | {6} | {7} | {8} | {9} | {10} | {11} | {12} | {13} | {14} | {15} | {16} |" -f `
            $rule.Id, `
            $rule.State, `
            $rule.Engine, `
            $rule.Category, `
            $rule.Severity, `
            $rule.Confidence, `
            $rule.MatchConfidence, `
            (($rule.SurfaceScope | Sort-Object) -join ", "), `
            $rule.MaxExamplesPerFile, `
            $rule.DetectorFamily, `
            ($rule.Why         -replace "\|", "/"), `
            $rule.MatchKind, `
            ($rule.Pattern     -replace "\|", "/"), `
            ($rule.TriggeringScenario -replace "\|", "/"), `
            ($rule.Remediation -replace "\|", "/"), `
            ($sources -join "<br>"), `
            ($rule.ReviewNotes -replace "\|", "/")
        $lines.Add($row)
    }

    $lines.Add("")
    return ($lines -join [Environment]::NewLine)
}

function Export-OneImAuditRuleSet {
    param(
        [Parameter(Mandatory)]
        [hashtable]$RuleCatalog,

        [Parameter(Mandatory)]
        [hashtable]$SourceLookup,

        [Parameter(Mandatory)]
        [ValidateSet("Markdown", "Json", "Csv")]
        [string]$Format
    )

    $rules = Get-OneImAuditRuleList -RuleCatalog $RuleCatalog

    switch ($Format) {
        "Markdown" {
            return ConvertTo-OneImAuditRuleMarkdown -RuleCatalog $RuleCatalog -SourceLookup $SourceLookup
        }
        "Json" {
            return ($rules | ConvertTo-Json -Depth 6)
        }
        "Csv" {
            return ($rules | Select-Object Id, Title, State, Engine, Category, Severity, Confidence, MatchConfidence, @{Name="SurfaceScope";Expression={ ($_.SurfaceScope -join ";") }}, MaxExamplesPerFile, DetectorFamily, Why, MatchKind, Pattern, TriggeringScenario, Remediation, ReviewNotes | ConvertTo-Csv -NoTypeInformation) -join [Environment]::NewLine
        }
    }
}

Export-ModuleMember -Function `
    Get-OneImAuditSourceLookup, `
    Get-OneImAuditRuleEffectiveState, `
    Get-OneImAuditRuleCatalog, `
    Get-OneImAuditRuleList, `
    Resolve-OneImAuditRuleSources, `
    Test-OneImAuditRuleSurfaceMatch, `
    Test-OneImAuditGatingFinding, `
    New-OneImAuditFinding, `
    Add-OneImAuditFinding, `
    ConvertTo-OneImAuditRuleMarkdown, `
    Export-OneImAuditRuleSet
