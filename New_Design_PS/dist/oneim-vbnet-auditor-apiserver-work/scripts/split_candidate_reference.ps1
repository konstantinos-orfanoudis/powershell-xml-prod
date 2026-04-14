[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$CandidateEntryPath,

    [Parameter(Mandatory)]
    [string]$ReviewPlanPath,

    [Parameter()]
    [string]$NewEntryId,

    [Parameter()]
    [ValidateSet("strong-custom", "context-only", "manual-review")]
    [string[]]$Bands = @("strong-custom"),

    [Parameter(Mandatory)]
    [string]$SplitNote,

    [Parameter()]
    [string]$Reviewer
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

function Clone-Object {
    param(
        [Parameter(Mandatory)]
        [object]$InputObject
    )

    return (($InputObject | ConvertTo-Json -Depth 12) | ConvertFrom-Json)
}

function Get-UniqueSurfaceList {
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$EvidenceItems
    )

    $items = New-Object System.Collections.Generic.List[string]
    foreach ($evidence in @($EvidenceItems)) {
        $source = [string]$evidence.source
        if ([string]::IsNullOrWhiteSpace($source)) {
            continue
        }

        $surface = ($source -split '[\\/]')[0]
        if (-not [string]::IsNullOrWhiteSpace($surface) -and -not $items.Contains($surface)) {
            $items.Add($surface)
        }
    }

    return @($items.ToArray())
}

try {
    $candidateFullPath = [System.IO.Path]::GetFullPath((Resolve-Path -LiteralPath $CandidateEntryPath).Path)
    $reviewPlanFullPath = [System.IO.Path]::GetFullPath((Resolve-Path -LiteralPath $ReviewPlanPath).Path)
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

    $reviewPlan = Get-Content -LiteralPath $reviewPlanFullPath -Raw | ConvertFrom-Json
    if ([string]$reviewPlan.entry_id -ne [string]$candidateMetadata.id) {
        throw "Review plan entry id '$($reviewPlan.entry_id)' does not match candidate entry id '$($candidateMetadata.id)'."
    }

    if ([System.IO.Path]::GetFullPath([string]$reviewPlan.candidate_entry_path) -ne $candidateFullPath) {
        throw "Review plan candidate path does not match the requested candidate entry path."
    }

    $selectedPlanItems = @($reviewPlan.items | Where-Object { $_.review_band -in $Bands })
    if ($selectedPlanItems.Count -eq 0) {
        throw "The review plan did not contain any items in the requested review bands: $($Bands -join ', ')."
    }

    $selectedPaths = @{}
    foreach ($item in $selectedPlanItems) {
        $selectedPaths[[System.IO.Path]::GetFullPath([string]$item.copied_to)] = $true
    }

    $selectedEvidence = @($candidateMetadata.evidence | Where-Object {
            $path = [System.IO.Path]::GetFullPath([string]$_.copied_to)
            $selectedPaths.ContainsKey($path)
        })
    $remainingEvidence = @($candidateMetadata.evidence | Where-Object {
            $path = [System.IO.Path]::GetFullPath([string]$_.copied_to)
            -not $selectedPaths.ContainsKey($path)
        })

    if ($selectedEvidence.Count -eq 0) {
        throw "No candidate evidence matched the selected review-plan items."
    }

    if ($remainingEvidence.Count -eq 0) {
        throw "Split would leave the original candidate entry empty. Use promotion or rejection workflows instead of a full split."
    }

    $entryName = Split-Path -Leaf $candidateFullPath
    if ([string]::IsNullOrWhiteSpace($NewEntryId)) {
        $NewEntryId = "{0}-{1}" -f $entryName, (($Bands | Select-Object -First 1) -replace "[^A-Za-z0-9]+", "-")
    }

    $newEntryPath = Join-Path $candidateParent $NewEntryId
    if (Test-Path -LiteralPath $newEntryPath) {
        throw "Split destination already exists at '$newEntryPath'."
    }

    $newFilesPath = Join-Path $newEntryPath "files"
    New-Item -ItemType Directory -Path $newFilesPath -Force | Out-Null

    $splitTimestamp = Get-Date
    $splitStamp = $splitTimestamp.ToString("yyyy-MM-dd HH:mm:ss K")
    $validationStamp = $splitTimestamp.ToString("yyyy-MM-dd")
    $selectedRelativePaths = New-Object System.Collections.Generic.List[string]
    $selectedEvidenceClones = New-Object System.Collections.Generic.List[object]

    foreach ($item in $selectedEvidence) {
        $sourcePath = [System.IO.Path]::GetFullPath([string]$item.copied_to)
        $relativePath = $sourcePath.Substring($candidateFilesPath.Length).TrimStart('\')
        $destinationPath = Join-Path $newFilesPath $relativePath
        $destinationParent = Split-Path -Parent $destinationPath
        if ($destinationParent -and -not (Test-Path -LiteralPath $destinationParent)) {
            New-Item -ItemType Directory -Path $destinationParent -Force | Out-Null
        }

        Copy-Item -LiteralPath $sourcePath -Destination $destinationPath -Force
        $selectedRelativePaths.Add($relativePath)

        $clone = Clone-Object -InputObject $item
        $clone.copied_to = $destinationPath
        $selectedEvidenceClones.Add($clone)
    }

    $newMetadata = Clone-Object -InputObject $candidateMetadata
    $newMetadata.id = $NewEntryId
    $newMetadata.title = ("{0} ({1} split)" -f [string]$candidateMetadata.title, ($Bands -join ", "))
    $newMetadata.status = "candidate-custom"
    $newMetadata.source_classification = "split-from-mixed-export"
    $newMetadata.reason_for_status = ("Split from candidate '{0}' using review-plan band(s) {1}. Requires focused rescoring before promotion. {2}" -f $entryName, ($Bands -join ", "), $SplitNote.Trim())
    $newMetadata.last_validated_at = $validationStamp
    $newMetadata.evidence = @($selectedEvidenceClones.ToArray())
    $newMetadata.surfaces = @(Get-UniqueSurfaceList -EvidenceItems $newMetadata.evidence)
    Set-OrAddProperty -Object $newMetadata -Name "split_from_entry_id" -Value $entryName
    Set-OrAddProperty -Object $newMetadata -Name "split_band_filter" -Value @($Bands)
    Set-OrAddProperty -Object $newMetadata -Name "split_at" -Value $splitStamp
    Set-OrAddProperty -Object $newMetadata -Name "split_note" -Value $SplitNote
    Set-OrAddProperty -Object $newMetadata -Name "split_reviewer" -Value $Reviewer
    Set-OrAddProperty -Object $newMetadata -Name "reviewed_at" -Value $null
    Set-OrAddProperty -Object $newMetadata -Name "reviewer" -Value $null
    Set-OrAddProperty -Object $newMetadata -Name "review_note" -Value $null
    Set-OrAddProperty -Object $newMetadata -Name "review_recommendation" -Value $null
    Set-OrAddProperty -Object $newMetadata -Name "promotion_ready" -Value $false

    $newTags = New-Object System.Collections.Generic.List[string]
    foreach ($tag in @($newMetadata.tags)) {
        $value = [string]$tag
        if ([string]::IsNullOrWhiteSpace($value) -or $value -eq "keep-candidate" -or $value -eq "reviewed" -or $value -eq "promote-ready" -or $value -eq "reject-recommended") {
            continue
        }

        if (-not $newTags.Contains($value)) {
            $newTags.Add($value)
        }
    }
    foreach ($tag in @("candidate-custom", "split-candidate", ($Bands | Select-Object -First 1))) {
        if (-not $newTags.Contains($tag)) {
            $newTags.Add($tag)
        }
    }
    $newMetadata.tags = @($newTags.ToArray())

    $remainingEvidenceClones = New-Object System.Collections.Generic.List[object]
    foreach ($item in $remainingEvidence) {
        $remainingEvidenceClones.Add((Clone-Object -InputObject $item))
    }

    $candidateMetadata.evidence = @($remainingEvidenceClones.ToArray())
    $candidateMetadata.surfaces = @(Get-UniqueSurfaceList -EvidenceItems $candidateMetadata.evidence)
    $candidateMetadata.reason_for_status = ("Retained as lower-confidence residue after splitting {0} into candidate '{1}'. {2}" -f ($Bands -join ", "), $NewEntryId, $SplitNote.Trim())
    $candidateMetadata.last_validated_at = $validationStamp
    Set-OrAddProperty -Object $candidateMetadata -Name "split_child_entry_ids" -Value @($NewEntryId)
    Set-OrAddProperty -Object $candidateMetadata -Name "split_at" -Value $splitStamp
    Set-OrAddProperty -Object $candidateMetadata -Name "split_note" -Value $SplitNote
    Set-OrAddProperty -Object $candidateMetadata -Name "split_reviewer" -Value $Reviewer
    Set-OrAddProperty -Object $candidateMetadata -Name "promotion_ready" -Value $false

    $candidateTags = New-Object System.Collections.Generic.List[string]
    foreach ($tag in @($candidateMetadata.tags)) {
        $value = [string]$tag
        if ([string]::IsNullOrWhiteSpace($value)) {
            continue
        }

        if (-not $candidateTags.Contains($value)) {
            $candidateTags.Add($value)
        }
    }
    if (-not $candidateTags.Contains("context-only-residual")) {
        $candidateTags.Add("context-only-residual")
    }
    $candidateMetadata.tags = @($candidateTags.ToArray())

    $newMetadataPath = Join-Path $newEntryPath "metadata.json"
    $newMetadata | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $newMetadataPath -Encoding UTF8
    $candidateMetadata | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $candidateMetadataPath -Encoding UTF8

    $selectedAbsolutePaths = @($selectedPaths.Keys)
    foreach ($path in $selectedAbsolutePaths) {
        if (Test-Path -LiteralPath $path) {
            Remove-Item -LiteralPath $path -Force
        }
    }

    $manifestPath = Join-Path $intakeRoot ("{0}-split-{1}.json" -f $entryName, $splitTimestamp.ToString("yyyyMMdd-HHmmss"))
    $manifest = [ordered]@{
        id = "{0}-split" -f $entryName
        action = "split-candidate-reference"
        oneim_version = [string]$candidateMetadata.oneim_version
        source_entry_id = $entryName
        new_entry_id = $NewEntryId
        candidate_entry_path = $candidateFullPath
        new_entry_path = $newEntryPath
        review_plan_path = $reviewPlanFullPath
        selected_bands = @($Bands)
        moved_item_count = $selectedEvidence.Count
        remaining_item_count = $remainingEvidence.Count
        reviewer = $Reviewer
        split_note = $SplitNote
        split_at = $splitStamp
    }
    $manifest | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $manifestPath -Encoding UTF8

    [pscustomobject]@{
        SourceEntryPath = $candidateFullPath
        NewEntryPath = $newEntryPath
        NewMetadataPath = $newMetadataPath
        SourceMetadataPath = $candidateMetadataPath
        ManifestPath = $manifestPath
        MovedItemCount = $selectedEvidence.Count
        RemainingItemCount = $remainingEvidence.Count
    }

    exit 0
}
catch {
    Write-Error $_
    exit 1
}
