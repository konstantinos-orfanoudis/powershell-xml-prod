[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$CandidateEntryPath,

    [Parameter(Mandatory)]
    [string]$RejectReason,

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
    $rejectedRoot = Join-Path $versionRoot "rejected"
    $intakeRoot = Join-Path $versionRoot "intake-manifests"
    foreach ($requiredPath in @($rejectedRoot, $intakeRoot)) {
        if (-not (Test-Path -LiteralPath $requiredPath)) {
            throw "Required reference tier path was not found: '$requiredPath'."
        }
    }

    $candidateMetadata = Get-Content -LiteralPath $candidateMetadataPath -Raw | ConvertFrom-Json
    if ([string]$candidateMetadata.status -ne "candidate-custom") {
        throw "Candidate metadata status must be 'candidate-custom', but was '$($candidateMetadata.status)'."
    }

    $entryName = Split-Path -Leaf $candidateFullPath
    $rejectedEntryPath = Join-Path $rejectedRoot $entryName
    if (Test-Path -LiteralPath $rejectedEntryPath) {
        throw "Rejected destination already exists at '$rejectedEntryPath'."
    }

    New-Item -ItemType Directory -Path $rejectedEntryPath -Force | Out-Null
    Get-ChildItem -LiteralPath $candidateFullPath -Force | Copy-Item -Destination $rejectedEntryPath -Recurse -Force

    $rejectedMetadataPath = Join-Path $rejectedEntryPath "metadata.json"
    $rejectedMetadata = Get-Content -LiteralPath $rejectedMetadataPath -Raw | ConvertFrom-Json
    $rejectionTimestamp = Get-Date
    $rejectionStamp = $rejectionTimestamp.ToString("yyyy-MM-dd HH:mm:ss K")
    $validationStamp = $rejectionTimestamp.ToString("yyyy-MM-dd")

    Set-OrAddProperty -Object $rejectedMetadata -Name "status" -Value "rejected"
    Set-OrAddProperty -Object $rejectedMetadata -Name "reason_for_status" -Value ("Rejected from candidate-custom after review. {0}" -f $RejectReason.Trim())
    Set-OrAddProperty -Object $rejectedMetadata -Name "last_validated_at" -Value $validationStamp
    Set-OrAddProperty -Object $rejectedMetadata -Name "rejected_at" -Value $rejectionStamp
    Set-OrAddProperty -Object $rejectedMetadata -Name "rejection_reason" -Value $RejectReason
    Set-OrAddProperty -Object $rejectedMetadata -Name "reviewer" -Value $Reviewer
    Set-OrAddProperty -Object $rejectedMetadata -Name "candidate_entry_path" -Value $candidateFullPath
    Set-OrAddProperty -Object $rejectedMetadata -Name "rejected_entry_path" -Value $rejectedEntryPath

    $updatedTags = New-Object System.Collections.Generic.List[string]
    foreach ($tag in @($rejectedMetadata.tags)) {
        $value = [string]$tag
        if ([string]::IsNullOrWhiteSpace($value) -or $value -eq "candidate-custom" -or $value -eq "promoted-custom") {
            continue
        }

        if (-not $updatedTags.Contains($value)) {
            $updatedTags.Add($value)
        }
    }
    if (-not $updatedTags.Contains("rejected")) {
        $updatedTags.Add("rejected")
    }
    $rejectedMetadata.tags = @($updatedTags.ToArray())

    foreach ($item in @($rejectedMetadata.evidence)) {
        if ($item.PSObject.Properties["copied_to"] -and -not [string]::IsNullOrWhiteSpace([string]$item.copied_to)) {
            $rewrittenPath = [string]$item.copied_to
            if ($rewrittenPath.StartsWith($candidateFullPath, [System.StringComparison]::OrdinalIgnoreCase)) {
                $rewrittenPath = $rejectedEntryPath + $rewrittenPath.Substring($candidateFullPath.Length)
            }
            $item.copied_to = $rewrittenPath
        }
    }

    $rejectedMetadata | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $rejectedMetadataPath -Encoding UTF8

    $manifestPath = Join-Path $intakeRoot ("{0}-rejection-{1}.json" -f $entryName, $rejectionTimestamp.ToString("yyyyMMdd-HHmmss"))
    $manifest = [ordered]@{
        id = "{0}-rejection" -f $entryName
        action = "reject-custom-reference"
        oneim_version = [string]$rejectedMetadata.oneim_version
        entry_id = [string]$rejectedMetadata.id
        from_status = "candidate-custom"
        to_status = "rejected"
        candidate_entry_path = $candidateFullPath
        rejected_entry_path = $rejectedEntryPath
        reviewer = $Reviewer
        rejection_reason = $RejectReason
        rejected_at = $rejectionStamp
    }
    $manifest | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $manifestPath -Encoding UTF8

    Remove-Item -LiteralPath $candidateFullPath -Recurse -Force

    [pscustomobject]@{
        CandidateEntryPath = $candidateFullPath
        RejectedEntryPath = $rejectedEntryPath
        MetadataPath = $rejectedMetadataPath
        ManifestPath = $manifestPath
    }

    exit 0
}
catch {
    Write-Error $_
    exit 1
}
