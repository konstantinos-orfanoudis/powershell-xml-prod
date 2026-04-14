[CmdletBinding()]
param(
    [Parameter()]
    [string]$ExportPath = (Get-Location).Path,

    [Parameter()]
    [string]$ReferenceLibraryRoot = (Join-Path (Get-Location).Path "reference-library"),

    [Parameter()]
    [string]$OneImVersion = "9.3.1",

    [Parameter()]
    [string]$Label = "system-debugger-libary",

    [Parameter()]
    [string]$ExtractOutputPath = (Join-Path (Get-Location).Path "output\custom-vb-extract")
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Ensure-Directory {
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
}

function New-PlaceholderFile {
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        Set-Content -LiteralPath $Path -Value "" -Encoding UTF8
    }
}

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$extractScript = Join-Path $scriptRoot "extract_custom_reference_files.ps1"
$materializeOotbScript = Join-Path $scriptRoot "materialize_sanitized_ootb_export.ps1"
if (-not (Test-Path -LiteralPath $extractScript)) {
    throw "Missing extractor script at $extractScript"
}
if (-not (Test-Path -LiteralPath $materializeOotbScript)) {
    throw "Missing OOTB materializer script at $materializeOotbScript"
}

$exportFullPath = (Resolve-Path -LiteralPath $ExportPath).Path
$referenceRootFullPath = [System.IO.Path]::GetFullPath($ReferenceLibraryRoot)
$extractOutputFullPath = [System.IO.Path]::GetFullPath($ExtractOutputPath)
$versionFolder = "oneim-{0}" -f $OneImVersion
$versionRoot = Join-Path $referenceRootFullPath $versionFolder
$ootbPath = Join-Path $versionRoot "ootb"
$promotedPath = Join-Path $versionRoot "promoted-custom"
$candidatePath = Join-Path $versionRoot "candidate-custom"
$rejectedPath = Join-Path $versionRoot "rejected"
$intakePath = Join-Path $versionRoot "intake-manifests"
$dateStamp = Get-Date -Format "yyyyMMdd"
$entryId = "{0}-custom-{1}" -f $Label, $dateStamp
$entryRoot = Join-Path $candidatePath $entryId
$entryFiles = Join-Path $entryRoot "files"
$ootbEntryId = "{0}-ootb-sanitized-{1}" -f $Label, $dateStamp
$ootbEntryRoot = Join-Path $ootbPath $ootbEntryId

Ensure-Directory -Path $referenceRootFullPath
foreach ($path in @($ootbPath, $promotedPath, $candidatePath, $rejectedPath, $intakePath, $entryRoot, $entryFiles, $ootbEntryRoot)) {
    Ensure-Directory -Path $path
}

foreach ($placeholder in @(
    (Join-Path $ootbPath ".gitkeep"),
    (Join-Path $promotedPath ".gitkeep"),
    (Join-Path $rejectedPath ".gitkeep")
)) {
    New-PlaceholderFile -Path $placeholder
}

powershell -NoProfile -ExecutionPolicy Bypass -File $extractScript -RootPath $exportFullPath -OutputPath $extractOutputFullPath | Out-Null

$indexPath = Join-Path $extractOutputFullPath "custom-index.json"
if (-not (Test-Path -LiteralPath $indexPath)) {
    throw "Custom extraction index not found at $indexPath"
}

powershell -NoProfile -ExecutionPolicy Bypass -File $materializeOotbScript -ExportPath $exportFullPath -IndexPath $indexPath -OutputPath $ootbEntryRoot | Out-Null

$rawIndex = Get-Content -LiteralPath $indexPath -Raw | ConvertFrom-Json
$index = @($rawIndex)
if ($index.Count -eq 1 -and $index[0] -is [System.Array]) {
    $index = @($index[0])
}
if ($null -eq $index) {
    throw "Custom extraction index at $indexPath was empty."
}

$surfaceAccumulator = @()
$evidence = @()

foreach ($item in $index) {
    $sourceParts = $item.source -split '[\\/]'
    if ($sourceParts.Length -gt 0) {
        $surfaceAccumulator += [string]$sourceParts[0]
    }

    $destDir = Join-Path $entryFiles $item.category
    Ensure-Directory -Path $destDir
    $destFile = Join-Path $destDir ([System.IO.Path]::GetFileName($item.output))
    $sourceExtractPath = [string]$item.output
    if (-not [System.IO.Path]::IsPathRooted($sourceExtractPath)) {
        $sourceExtractPath = Join-Path (Get-Location).Path $sourceExtractPath
    }

    Copy-Item -LiteralPath $sourceExtractPath -Destination $destFile -Force

    $evidence += [pscustomobject]@{
        category = $item.category
        source = $item.source
        start_line = $item.start_line
        end_line = $item.end_line
        symbol = $item.symbol
        kind = $item.kind
        copied_to = $destFile
    }
}

$surfaces = @($surfaceAccumulator | Sort-Object -Unique)

$readmePath = Join-Path $referenceRootFullPath "README.md"
if (-not (Test-Path -LiteralPath $readmePath)) {
    $readmeLines = @(
        "# Reference Library",
        "",
        "This folder stores version-aware One Identity Manager VB.NET reference material for the repo-local auditor.",
        "",
        "## Tiers",
        "",
        "- `ootb/`: strongest baseline when the content is known to come from a clean out-of-the-box export",
        "- A heuristic sanitized OOTB copy can be created from a mixed export by removing `CCC`-marked content, but that baseline is weaker than a clean OOTB export from a known pure database.",
        "- `promoted-custom/`: reviewed custom references that passed promotion rules",
        "- `candidate-custom/`: extracted or submitted custom references that still need review and scoring",
        "- `rejected/`: negative examples and anti-patterns",
        "- `intake-manifests/`: manifests that classify raw exports, such as `mixed-export`, before they are trusted as reference baselines",
        "",
        "## Default Version",
        "",
        "- Active scaffolded version: `9.3.1`",
        "",
        "## Important Rule",
        "",
        "A raw System Debugger export must not be treated as pure OOTB unless its provenance proves that it came from a clean OOTB database. Mixed exports should be registered through `intake-manifests/` and any extracted custom snippets should start in `candidate-custom/`."
    )
    Set-Content -LiteralPath $readmePath -Value $readmeLines -Encoding UTF8
}

$metadata = [ordered]@{
    id = $entryId
    title = "Custom snippets extracted from $Label"
    oneim_version = $OneImVersion
    origin = "system-debugger-export"
    status = "candidate-custom"
    source_classification = "mixed-export"
    confidence_score = 45
    correctness_confidence = 55
    security_confidence = 45
    performance_confidence = 40
    context_confidence = 35
    confidence_threshold_at_promotion = 85
    reason_for_status = "Automatically extracted from a mixed System Debugger export. Requires manual scoring and promotion review before it can become trusted custom reference material."
    last_validated_at = (Get-Date).ToString("yyyy-MM-dd")
    source_root = $exportFullPath
    tags = @(
        "oneim",
        "vbnet",
        "candidate-custom",
        "mixed-export",
        "system-debugger-export",
        "bootstrap"
    )
    surfaces = $surfaces
    evidence = @($evidence)
}

$metadataPath = Join-Path $entryRoot "metadata.json"
$metadata | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $metadataPath -Encoding UTF8

$manifest = [ordered]@{
    id = "{0}-mixed-export" -f $Label
    oneim_version = $OneImVersion
    classification = "mixed-export"
    trust_level = "context-only"
    source_root = $exportFullPath
    detected_surfaces = $surfaces
    heuristic_ootb_entry = $ootbEntryId
    heuristic_ootb_path = $ootbEntryRoot
    custom_extract_entry = $entryId
    custom_extract_index = $indexPath
    custom_item_count = @($index).Count
    notes = @(
        "This export contains clear custom markers and must not be treated as a pure OOTB baseline.",
        "A heuristic sanitized OOTB copy was created by removing extracted CCC custom ranges from the exported VB files.",
        "Use it as contextual comparative evidence only until a clean OOTB export is available.",
        "Use the seeded candidate-custom entry for explicit custom comparison and future scoring."
    )
}

$manifestPath = Join-Path $intakePath ("{0}-mixed-export.json" -f $Label)
$manifest | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $manifestPath -Encoding UTF8

[pscustomobject]@{
    ExportPath = $exportFullPath
    ReferenceLibraryRoot = $referenceRootFullPath
    HeuristicOotbEntry = $ootbEntryRoot
    CandidateEntry = $entryRoot
    CandidateMetadata = $metadataPath
    MixedExportManifest = $manifestPath
    ExtractedItemCount = @($index).Count
}
