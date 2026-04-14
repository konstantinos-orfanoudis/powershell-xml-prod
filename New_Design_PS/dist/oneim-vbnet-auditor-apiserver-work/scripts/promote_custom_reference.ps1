[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$CandidateEntryPath,

    [Parameter(Mandatory)]
    [string]$PromotionNote,

    [Parameter()]
    [string]$Reviewer,

    [Parameter()]
    [switch]$Force
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
    $promotedRoot = Join-Path $versionRoot "promoted-custom"
    $intakeRoot = Join-Path $versionRoot "intake-manifests"
    foreach ($requiredPath in @($promotedRoot, $intakeRoot)) {
        if (-not (Test-Path -LiteralPath $requiredPath)) {
            throw "Required reference tier path was not found: '$requiredPath'."
        }
    }

    $candidateMetadata = Get-Content -LiteralPath $candidateMetadataPath -Raw | ConvertFrom-Json
    if ([string]$candidateMetadata.status -ne "candidate-custom") {
        throw "Candidate metadata status must be 'candidate-custom', but was '$($candidateMetadata.status)'."
    }

    $reviewedAt = if ($candidateMetadata.PSObject.Properties["reviewed_at"]) { [string]$candidateMetadata.reviewed_at } else { "" }
    $reviewer = if ($candidateMetadata.PSObject.Properties["reviewer"]) { [string]$candidateMetadata.reviewer } else { "" }
    $reviewNote = if ($candidateMetadata.PSObject.Properties["review_note"]) { [string]$candidateMetadata.review_note } else { "" }
    $reviewRecommendation = if ($candidateMetadata.PSObject.Properties["review_recommendation"]) { [string]$candidateMetadata.review_recommendation } else { "" }

    $confidenceScore = [int]$candidateMetadata.confidence_score
    $promotionThreshold = if ($candidateMetadata.PSObject.Properties["confidence_threshold_at_promotion"]) {
        [int]$candidateMetadata.confidence_threshold_at_promotion
    }
    else {
        0
    }

    if (-not $Force.IsPresent -and ([string]::IsNullOrWhiteSpace($reviewedAt) -or [string]::IsNullOrWhiteSpace($reviewer) -or [string]::IsNullOrWhiteSpace($reviewNote))) {
        throw "Candidate has not been formally reviewed yet. Run review_custom_reference.ps1 before promotion, or use -Force after manual sign-off."
    }

    if (-not $Force.IsPresent -and $reviewRecommendation -ne "promote-ready") {
        throw "Candidate review recommendation is '$reviewRecommendation'. Update the review to 'promote-ready' before promotion, or use -Force after manual sign-off."
    }

    if (-not $Force.IsPresent -and $confidenceScore -lt $promotionThreshold) {
        throw "Candidate confidence score $confidenceScore is below the promotion threshold $promotionThreshold. Re-run with -Force after review if you want to override the gate."
    }

    $entryName = Split-Path -Leaf $candidateFullPath
    $promotedEntryPath = Join-Path $promotedRoot $entryName
    if (Test-Path -LiteralPath $promotedEntryPath) {
        throw "Promoted destination already exists at '$promotedEntryPath'."
    }

    New-Item -ItemType Directory -Path $promotedEntryPath -Force | Out-Null
    Get-ChildItem -LiteralPath $candidateFullPath -Force | Copy-Item -Destination $promotedEntryPath -Recurse -Force

    $promotedMetadataPath = Join-Path $promotedEntryPath "metadata.json"
    $promotedMetadata = Get-Content -LiteralPath $promotedMetadataPath -Raw | ConvertFrom-Json
    $promotionTimestamp = Get-Date
    $promotionStamp = $promotionTimestamp.ToString("yyyy-MM-dd HH:mm:ss K")
    $validationStamp = $promotionTimestamp.ToString("yyyy-MM-dd")

    Set-OrAddProperty -Object $promotedMetadata -Name "status" -Value "promoted-custom"
    Set-OrAddProperty -Object $promotedMetadata -Name "reason_for_status" -Value ("Promoted from candidate-custom after review. {0}" -f $PromotionNote.Trim())
    Set-OrAddProperty -Object $promotedMetadata -Name "last_validated_at" -Value $validationStamp
    Set-OrAddProperty -Object $promotedMetadata -Name "promoted_at" -Value $promotionStamp
    Set-OrAddProperty -Object $promotedMetadata -Name "promotion_note" -Value $PromotionNote
    Set-OrAddProperty -Object $promotedMetadata -Name "reviewer" -Value $Reviewer
    Set-OrAddProperty -Object $promotedMetadata -Name "force_promoted" -Value ([bool]$Force.IsPresent)
    Set-OrAddProperty -Object $promotedMetadata -Name "candidate_entry_path" -Value $candidateFullPath
    Set-OrAddProperty -Object $promotedMetadata -Name "promoted_entry_path" -Value $promotedEntryPath

    $updatedTags = New-Object System.Collections.Generic.List[string]
    foreach ($tag in @($promotedMetadata.tags)) {
        $value = [string]$tag
        if ([string]::IsNullOrWhiteSpace($value) -or $value -eq "candidate-custom") {
            continue
        }

        if (-not $updatedTags.Contains($value)) {
            $updatedTags.Add($value)
        }
    }
    if (-not $updatedTags.Contains("promoted-custom")) {
        $updatedTags.Add("promoted-custom")
    }
    $promotedMetadata.tags = @($updatedTags.ToArray())

    foreach ($item in @($promotedMetadata.evidence)) {
        if ($item.PSObject.Properties["copied_to"] -and -not [string]::IsNullOrWhiteSpace([string]$item.copied_to)) {
            $rewrittenPath = [string]$item.copied_to
            if ($rewrittenPath.StartsWith($candidateFullPath, [System.StringComparison]::OrdinalIgnoreCase)) {
                $rewrittenPath = $promotedEntryPath + $rewrittenPath.Substring($candidateFullPath.Length)
            }
            $item.copied_to = $rewrittenPath
        }
    }

    $promotedMetadata | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $promotedMetadataPath -Encoding UTF8

    $manifestPath = Join-Path $intakeRoot ("{0}-promotion-{1}.json" -f $entryName, $promotionTimestamp.ToString("yyyyMMdd-HHmmss"))
    $manifest = [ordered]@{
        id = "{0}-promotion" -f $entryName
        action = "promote-custom-reference"
        oneim_version = [string]$promotedMetadata.oneim_version
        entry_id = [string]$promotedMetadata.id
        from_status = "candidate-custom"
        to_status = "promoted-custom"
        candidate_entry_path = $candidateFullPath
        promoted_entry_path = $promotedEntryPath
        confidence_score = $confidenceScore
        confidence_threshold_at_promotion = $promotionThreshold
        reviewer = $Reviewer
        promotion_note = $PromotionNote
        force_promoted = [bool]$Force.IsPresent
        promoted_at = $promotionStamp
    }
    $manifest | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $manifestPath -Encoding UTF8

    Remove-Item -LiteralPath $candidateFullPath -Recurse -Force

    [pscustomobject]@{
        CandidateEntryPath = $candidateFullPath
        PromotedEntryPath = $promotedEntryPath
        MetadataPath = $promotedMetadataPath
        ManifestPath = $manifestPath
        ConfidenceScore = $confidenceScore
        PromotionThreshold = $promotionThreshold
        ForcePromoted = [bool]$Force.IsPresent
    }

    exit 0
}
catch {
    Write-Error $_
    exit 1
}
