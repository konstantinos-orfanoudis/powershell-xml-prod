[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$CandidateEntryPath,

    [Parameter(Mandatory)]
    [ValidateRange(0, 100)]
    [int]$ConfidenceScore,

    [Parameter()]
    [ValidateRange(0, 100)]
    [int]$CorrectnessConfidence,

    [Parameter()]
    [ValidateRange(0, 100)]
    [int]$SecurityConfidence,

    [Parameter()]
    [ValidateRange(0, 100)]
    [int]$PerformanceConfidence,

    [Parameter()]
    [ValidateRange(0, 100)]
    [int]$ContextConfidence,

    [Parameter(Mandatory)]
    [string]$ReviewNote,

    [Parameter(Mandatory)]
    [string]$Reviewer,

    [Parameter()]
    [ValidateSet("keep-candidate", "promote-ready", "reject-recommended")]
    [string]$Recommendation = "keep-candidate",

    [Parameter()]
    [ValidateRange(0, 100)]
    [int]$ConfidenceThresholdAtPromotion
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Set-OrAddProperty {
    param(
        [Parameter(Mandatory)]
        [object]$Object,

        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter()]
        $Value
    )

    $property = $Object.PSObject.Properties[$Name]
    if ($null -ne $property) {
        $property.Value = $Value
    }
    else {
        $Object | Add-Member -NotePropertyName $Name -NotePropertyValue $Value
    }
}

try {
    $candidateFullPath = [System.IO.Path]::GetFullPath((Resolve-Path -LiteralPath $CandidateEntryPath).Path)
    $candidateMetadataPath = Join-Path $candidateFullPath "metadata.json"
    $candidateFilesPath = Join-Path $candidateFullPath "files"

    if (-not (Test-Path -LiteralPath $candidateMetadataPath)) {
        throw "Candidate metadata was not found at '$candidateMetadataPath'."
    }

    if (-not (Test-Path -LiteralPath $candidateFilesPath)) {
        throw "Candidate files folder was not found at '$candidateFilesPath'."
    }

    $candidateParent = Split-Path -Parent $candidateFullPath
    if (-not [System.StringComparer]::OrdinalIgnoreCase.Equals((Split-Path -Leaf $candidateParent), "candidate-custom")) {
        throw "Candidate entry path must live directly under a 'candidate-custom' tier."
    }

    $versionRoot = Split-Path -Parent $candidateParent
    $intakeRoot = Join-Path $versionRoot "intake-manifests"
    if (-not (Test-Path -LiteralPath $intakeRoot)) {
        throw "Required reference tier path was not found: '$intakeRoot'."
    }

    $candidateMetadata = Get-Content -LiteralPath $candidateMetadataPath -Raw | ConvertFrom-Json
    if ([string]$candidateMetadata.status -ne "candidate-custom") {
        throw "Candidate metadata status must be 'candidate-custom', but was '$($candidateMetadata.status)'."
    }

    $effectiveThreshold = if ($PSBoundParameters.ContainsKey("ConfidenceThresholdAtPromotion")) {
        $ConfidenceThresholdAtPromotion
    }
    elseif ($candidateMetadata.PSObject.Properties["confidence_threshold_at_promotion"]) {
        [int]$candidateMetadata.confidence_threshold_at_promotion
    }
    else {
        85
    }

    if (-not $PSBoundParameters.ContainsKey("CorrectnessConfidence")) {
        $CorrectnessConfidence = $ConfidenceScore
    }
    if (-not $PSBoundParameters.ContainsKey("SecurityConfidence")) {
        $SecurityConfidence = $ConfidenceScore
    }
    if (-not $PSBoundParameters.ContainsKey("PerformanceConfidence")) {
        $PerformanceConfidence = $ConfidenceScore
    }
    if (-not $PSBoundParameters.ContainsKey("ContextConfidence")) {
        $ContextConfidence = $ConfidenceScore
    }

    if ($Recommendation -eq "promote-ready" -and $ConfidenceScore -lt $effectiveThreshold) {
        throw "Recommendation 'promote-ready' requires confidence score $ConfidenceScore to meet or exceed the promotion threshold $effectiveThreshold."
    }

    $reviewTimestamp = Get-Date
    $reviewStamp = $reviewTimestamp.ToString("yyyy-MM-dd HH:mm:ss K")
    $validationStamp = $reviewTimestamp.ToString("yyyy-MM-dd")
    $promotionReady = ($Recommendation -eq "promote-ready" -and $ConfidenceScore -ge $effectiveThreshold)

    $reasonForStatus = switch ($Recommendation) {
        "promote-ready" { "Reviewed and kept in candidate-custom pending explicit promotion. Ready for promotion. $($ReviewNote.Trim())" }
        "reject-recommended" { "Reviewed and kept in candidate-custom pending explicit rejection. Reject recommended. $($ReviewNote.Trim())" }
        default { "Reviewed and retained in candidate-custom pending more evidence. $($ReviewNote.Trim())" }
    }

    Set-OrAddProperty -Object $candidateMetadata -Name "confidence_score" -Value $ConfidenceScore
    Set-OrAddProperty -Object $candidateMetadata -Name "correctness_confidence" -Value $CorrectnessConfidence
    Set-OrAddProperty -Object $candidateMetadata -Name "security_confidence" -Value $SecurityConfidence
    Set-OrAddProperty -Object $candidateMetadata -Name "performance_confidence" -Value $PerformanceConfidence
    Set-OrAddProperty -Object $candidateMetadata -Name "context_confidence" -Value $ContextConfidence
    Set-OrAddProperty -Object $candidateMetadata -Name "confidence_threshold_at_promotion" -Value $effectiveThreshold
    Set-OrAddProperty -Object $candidateMetadata -Name "last_validated_at" -Value $validationStamp
    Set-OrAddProperty -Object $candidateMetadata -Name "reviewed_at" -Value $reviewStamp
    Set-OrAddProperty -Object $candidateMetadata -Name "reviewer" -Value $Reviewer
    Set-OrAddProperty -Object $candidateMetadata -Name "review_note" -Value $ReviewNote
    Set-OrAddProperty -Object $candidateMetadata -Name "review_recommendation" -Value $Recommendation
    Set-OrAddProperty -Object $candidateMetadata -Name "promotion_ready" -Value $promotionReady
    Set-OrAddProperty -Object $candidateMetadata -Name "reason_for_status" -Value $reasonForStatus

    $updatedTags = New-Object System.Collections.Generic.List[string]
    foreach ($tag in @($candidateMetadata.tags)) {
        $value = [string]$tag
        if ([string]::IsNullOrWhiteSpace($value) -or $value -eq "reviewed" -or $value -eq "promote-ready" -or $value -eq "reject-recommended" -or $value -eq "keep-candidate") {
            continue
        }

        if (-not $updatedTags.Contains($value)) {
            $updatedTags.Add($value)
        }
    }
    $updatedTags.Add("reviewed")
    $updatedTags.Add($Recommendation)
    $candidateMetadata.tags = @($updatedTags.ToArray() | Select-Object -Unique)

    $candidateMetadata | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $candidateMetadataPath -Encoding UTF8

    $entryName = Split-Path -Leaf $candidateFullPath
    $manifestPath = Join-Path $intakeRoot ("{0}-review-{1}.json" -f $entryName, $reviewTimestamp.ToString("yyyyMMdd-HHmmss"))
    $manifest = [ordered]@{
        id = "{0}-review" -f $entryName
        action = "review-custom-reference"
        oneim_version = [string]$candidateMetadata.oneim_version
        entry_id = [string]$candidateMetadata.id
        status = "candidate-custom"
        candidate_entry_path = $candidateFullPath
        reviewer = $Reviewer
        review_note = $ReviewNote
        review_recommendation = $Recommendation
        confidence_score = $ConfidenceScore
        correctness_confidence = $CorrectnessConfidence
        security_confidence = $SecurityConfidence
        performance_confidence = $PerformanceConfidence
        context_confidence = $ContextConfidence
        confidence_threshold_at_promotion = $effectiveThreshold
        promotion_ready = $promotionReady
        reviewed_at = $reviewStamp
    }
    $manifest | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $manifestPath -Encoding UTF8

    [pscustomobject]@{
        CandidateEntryPath = $candidateFullPath
        MetadataPath = $candidateMetadataPath
        ManifestPath = $manifestPath
        ConfidenceScore = $ConfidenceScore
        PromotionThreshold = $effectiveThreshold
        PromotionReady = $promotionReady
        Recommendation = $Recommendation
    }

    exit 0
}
catch {
    Write-Error $_
    exit 1
}
