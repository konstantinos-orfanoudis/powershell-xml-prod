[CmdletBinding()]
param(
    [Parameter()]
    [string]$ExportPath = (Get-Location).Path,

    [Parameter()]
    [string]$IndexPath = (Join-Path (Get-Location).Path "output\custom-vb-extract\custom-index.json"),

    [Parameter()]
    [string]$OutputPath = (Join-Path (Get-Location).Path "reference-library\oneim-9.3.1\ootb\system-debugger-libary-sanitized")
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

$exportFullPath = (Resolve-Path -LiteralPath $ExportPath).Path
$indexFullPath = (Resolve-Path -LiteralPath $IndexPath).Path
$outputFullPath = [System.IO.Path]::GetFullPath($OutputPath)
Ensure-Directory -Path $outputFullPath

$trackedFiles = @(
    "Scripts\Scripts.vb",
    "ProductScripts\ProductScripts.vb",
    "Tables\Tables.vb",
    "Table\Table.vb",
    "Tmpl\Tmpl.vb",
    "DlgMth\DlgMth.vb",
    "Parameters\Parameters.vb",
    "TypedWrappers\TypedWrappers.vb",
    "WebServices\WebServices.vb"
)

$rawIndex = Get-Content -LiteralPath $indexFullPath -Raw | ConvertFrom-Json
$index = @($rawIndex)
if ($index.Count -eq 1 -and $index[0] -is [System.Array]) {
    $index = @($index[0])
}

$manifestEntries = @()

foreach ($relativePath in $trackedFiles) {
    $sourcePath = Join-Path $exportFullPath $relativePath
    if (-not (Test-Path -LiteralPath $sourcePath)) {
        continue
    }

    $targetPath = Join-Path $outputFullPath $relativePath
    Ensure-Directory -Path (Split-Path -Parent $targetPath)

    $lines = @(Get-Content -LiteralPath $sourcePath)
    $skipLineNumbers = @{}
    $removedBlocks = @()

    $ranges = @($index | Where-Object { $_.source -eq $relativePath })
    foreach ($range in $ranges) {
        $rangeStart = [int]([string](@($range.start_line)[0]))
        $rangeEnd = [int]([string](@($range.end_line)[0]))
        for ($line = $rangeStart; $line -le $rangeEnd; $line++) {
            $skipLineNumbers[$line] = $true
        }

        $removedBlocks += [pscustomobject]@{
            start_line = $rangeStart
            end_line = $rangeEnd
            kind = [string]$range.kind
            symbol = [string]$range.symbol
        }
    }

    $removedCount = 0
    $sanitized = for ($i = 0; $i -lt $lines.Count; $i++) {
        $lineNumber = $i + 1
        if ($skipLineNumbers.ContainsKey($lineNumber)) {
            $removedCount++
            continue
        }

        $lines[$i]
    }

    Set-Content -LiteralPath $targetPath -Value $sanitized -Encoding UTF8

    $manifestEntries += [pscustomobject]@{
        source = $relativePath
        output = $targetPath
        original_line_count = $lines.Count
        removed_line_count = $removedCount
        removed_blocks = $removedBlocks
    }
}

$metadata = [ordered]@{
    source_root = $exportFullPath
    classification = "heuristic-ootb-sanitized"
    trust_level = "baseline-with-caveats"
    basis = "Created by removing ranges mapped from extracted CCC custom snippets and references."
    created_at = (Get-Date).ToString("yyyy-MM-dd")
    tracked_files = $trackedFiles
    files = $manifestEntries
}

$metadataPath = Join-Path $outputFullPath "sanitization-manifest.json"
$metadata | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $metadataPath -Encoding UTF8

[pscustomobject]@{
    ExportPath = $exportFullPath
    OutputPath = $outputFullPath
    ManifestPath = $metadataPath
    FileCount = @($manifestEntries).Count
}
