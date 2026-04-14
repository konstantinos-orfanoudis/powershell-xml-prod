[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$CandidateEntryPath,

    [Parameter()]
    [string]$OutputDir = (Join-Path (Get-Location).Path "output\oneim-candidate-review-plan")
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function New-DirectoryIfMissing {
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
}

function Get-EvidencePreview {
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        return "[file missing]"
    }

    foreach ($line in @(Get-Content -LiteralPath $Path -ErrorAction Stop)) {
        $trimmed = $line.Trim()
        if ([string]::IsNullOrWhiteSpace($trimmed)) {
            continue
        }

        if ($trimmed.StartsWith("'")) {
            continue
        }

        return $trimmed
    }

    return "[no non-comment content]"
}

function Get-EvidenceAssessment {
    param(
        [Parameter(Mandatory)]
        [object]$Evidence
    )

    switch ([string]$Evidence.kind) {
        "typed-wrapper-custom-root" {
            return [ordered]@{
                review_band = "strong-custom"
                suggested_confidence_score = 92
                suggested_action = "split-for-focused-review"
                rationale = "The custom typed-wrapper root explicitly maps the Custom namespace and is a strong custom indicator."
            }
        }
        "typed-wrapper-class" {
            return [ordered]@{
                review_band = "strong-custom"
                suggested_confidence_score = 90
                suggested_action = "split-for-focused-review"
                rationale = "A CCC-named typed wrapper class is a strong indicator of custom extension material."
            }
        }
        "custom-vikey-block" {
            return [ordered]@{
                review_band = "strong-custom"
                suggested_confidence_score = 88
                suggested_action = "split-for-focused-review"
                rationale = "A VI-KEY block with a CCC key usually points at a directly custom script definition."
            }
        }
        "custom-reference-block" {
            return [ordered]@{
                review_band = "context-only"
                suggested_confidence_score = 55
                suggested_action = "keep-as-context-or-reject"
                rationale = "An enclosing member that merely references a CCC token is weaker evidence and may be mixed with broadly shared logic."
            }
        }
        default {
            return [ordered]@{
                review_band = "manual-review"
                suggested_confidence_score = 50
                suggested_action = "inspect-manually"
                rationale = "This evidence kind does not have a stronger heuristic yet and needs manual review."
            }
        }
    }
}

function ConvertTo-ReviewPlanMarkdown {
    param(
        [Parameter(Mandatory)]
        [object]$Plan
    )

    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add("# Candidate Review Plan")
    $lines.Add("")
    $lines.Add(("Entry id: {0}" -f $Plan.entry_id))
    $lines.Add(("Candidate entry: {0}" -f $Plan.candidate_entry_path))
    $lines.Add(("Source classification: {0}" -f $Plan.source_classification))
    $lines.Add(("Current status: {0}" -f $Plan.status))
    $lines.Add(("Current confidence score: {0}" -f $Plan.current_confidence_score))
    $lines.Add("")
    $lines.Add("## Summary")
    $lines.Add("")
    $lines.Add(("- Total evidence items: {0}" -f $Plan.summary.total_items))
    $lines.Add(("- Strong custom indicators: {0}" -f $Plan.summary.strong_custom_count))
    $lines.Add(("- Context-only references: {0}" -f $Plan.summary.context_only_count))
    $lines.Add(("- Manual-review items: {0}" -f $Plan.summary.manual_review_count))
    $lines.Add("")
    $lines.Add("## Suggested Next Steps")
    $lines.Add("")
    foreach ($step in @($Plan.suggested_next_steps)) {
        $lines.Add(("- {0}" -f $step))
    }
    $lines.Add("")
    $lines.Add("## Evidence")
    $lines.Add("")
    $lines.Add("| Band | Kind | Symbol | Source | Suggested Action | Suggested Score | Preview |")
    $lines.Add("|---|---|---|---|---|---:|---|")
    foreach ($item in @($Plan.items)) {
        $preview = [string]$item.preview
        $preview = $preview -replace "\|", "/"
        $lines.Add((
            "| {0} | {1} | {2} | {3}:{4}-{5} | {6} | {7} | {8} |" -f
            $item.review_band,
            $item.kind,
            $item.symbol,
            $item.source,
            $item.start_line,
            $item.end_line,
            $item.suggested_action,
            $item.suggested_confidence_score,
            $preview
        ))
    }

    $lines.Add("")
    return ($lines -join [Environment]::NewLine)
}

try {
    $candidateFullPath = [System.IO.Path]::GetFullPath((Resolve-Path -LiteralPath $CandidateEntryPath).Path)
    $metadataPath = Join-Path $candidateFullPath "metadata.json"
    if (-not (Test-Path -LiteralPath $metadataPath)) {
        throw "Candidate metadata was not found at '$metadataPath'."
    }

    $candidateParent = Split-Path -Parent $candidateFullPath
    if (-not [System.StringComparer]::OrdinalIgnoreCase.Equals((Split-Path -Leaf $candidateParent), "candidate-custom")) {
        throw "Candidate entry path must live directly under a 'candidate-custom' tier."
    }

    $metadata = Get-Content -LiteralPath $metadataPath -Raw | ConvertFrom-Json
    if ([string]$metadata.status -ne "candidate-custom") {
        throw "Candidate metadata status must be 'candidate-custom', but was '$($metadata.status)'."
    }

    $outputRoot = [System.IO.Path]::GetFullPath($OutputDir)
    $entryOutputRoot = Join-Path $outputRoot ([string]$metadata.id)
    New-DirectoryIfMissing -Path $entryOutputRoot

    $reviewItems = New-Object System.Collections.Generic.List[object]
    foreach ($evidence in @($metadata.evidence)) {
        $assessment = Get-EvidenceAssessment -Evidence $evidence
        $reviewItems.Add([pscustomobject]@{
                category = [string]$evidence.category
                kind = [string]$evidence.kind
                symbol = [string]$evidence.symbol
                source = [string]$evidence.source
                start_line = [int]$evidence.start_line
                end_line = [int]$evidence.end_line
                copied_to = [string]$evidence.copied_to
                preview = Get-EvidencePreview -Path ([string]$evidence.copied_to)
                review_band = [string]$assessment.review_band
                suggested_action = [string]$assessment.suggested_action
                suggested_confidence_score = [int]$assessment.suggested_confidence_score
                rationale = [string]$assessment.rationale
            })
    }

    $items = @($reviewItems.ToArray() | Sort-Object review_band, category, source, start_line)
    $strongCustomCount = @($items | Where-Object { $_.review_band -eq "strong-custom" }).Count
    $contextOnlyCount = @($items | Where-Object { $_.review_band -eq "context-only" }).Count
    $manualReviewCount = @($items | Where-Object { $_.review_band -eq "manual-review" }).Count

    $nextSteps = New-Object System.Collections.Generic.List[string]
    if ($strongCustomCount -gt 0) {
        $nextSteps.Add("Split the strong custom indicators into a dedicated candidate entry so they can be rescored without inheriting the weak mixed-export context of the broader bundle.")
    }
    if ($contextOnlyCount -gt 0) {
        $nextSteps.Add("Keep the context-only reference blocks out of promotion unless cleaner corroborating evidence is found, or reject them if they remain ambiguous.")
    }
    if ($manualReviewCount -gt 0) {
        $nextSteps.Add("Inspect the manual-review items directly because they do not yet have a strong heuristic classification.")
    }
    if ($nextSteps.Count -eq 0) {
        $nextSteps.Add("No evidence items were found to review.")
    }

    $plan = [ordered]@{
        entry_id = [string]$metadata.id
        candidate_entry_path = $candidateFullPath
        metadata_path = $metadataPath
        source_classification = [string]$metadata.source_classification
        status = [string]$metadata.status
        current_confidence_score = [int]$metadata.confidence_score
        current_review_recommendation = if ($metadata.PSObject.Properties["review_recommendation"]) { [string]$metadata.review_recommendation } else { $null }
        summary = [ordered]@{
            total_items = $items.Count
            strong_custom_count = $strongCustomCount
            context_only_count = $contextOnlyCount
            manual_review_count = $manualReviewCount
        }
        suggested_next_steps = @($nextSteps.ToArray())
        items = $items
    }

    $jsonPath = Join-Path $entryOutputRoot "candidate-review-plan.json"
    $markdownPath = Join-Path $entryOutputRoot "candidate-review-plan.md"
    $plan | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $jsonPath -Encoding UTF8
    ConvertTo-ReviewPlanMarkdown -Plan $plan | Set-Content -LiteralPath $markdownPath -Encoding UTF8

    [pscustomobject]@{
        CandidateEntryPath = $candidateFullPath
        JsonPath = $jsonPath
        MarkdownPath = $markdownPath
        StrongCustomCount = $strongCustomCount
        ContextOnlyCount = $contextOnlyCount
        ManualReviewCount = $manualReviewCount
    }

    exit 0
}
catch {
    Write-Error $_
    exit 1
}
