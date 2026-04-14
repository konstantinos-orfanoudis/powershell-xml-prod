[CmdletBinding()]
param(
    [Parameter()]
    [string]$RootPath = (Get-Location).Path,

    [Parameter()]
    [string]$OutputPath = (Join-Path (Get-Location).Path "output\custom-vb-extract")
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

function ConvertTo-SafeFileName {
    param(
        [Parameter(Mandatory)]
        [string]$Name
    )

    $safe = [regex]::Replace($Name, "[^A-Za-z0-9._-]+", "_")
    return $safe.Trim("_")
}

function New-SnippetFile {
    param(
        [Parameter(Mandatory)]
        [string]$Category,

        [Parameter(Mandatory)]
        [string]$Name,

        [Parameter(Mandatory)]
        [string]$RelativeSourcePath,

        [Parameter(Mandatory)]
        [int]$StartLine,

        [Parameter(Mandatory)]
        [int]$EndLine,

        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [AllowEmptyCollection()]
        [string[]]$Lines,

        [Parameter(Mandatory)]
        [hashtable]$Metadata
    )

    $categoryPath = Join-Path $OutputPath $Category
    Ensure-Directory -Path $categoryPath

    $filePath = Join-Path $categoryPath ("{0}.vb" -f (ConvertTo-SafeFileName -Name $Name))
    $content = New-Object System.Collections.Generic.List[string]
    $content.Add("' Extracted from OneIM System Debugger export")
    $content.Add(("' Source: {0}:{1}-{2}" -f $RelativeSourcePath, $StartLine, $EndLine))
    foreach ($entry in $Metadata.GetEnumerator() | Sort-Object Name) {
        $content.Add(("' {0}: {1}" -f $entry.Key, $entry.Value))
    }
    $content.Add("")
    foreach ($line in $Lines) {
        $content.Add($line)
    }

    Set-Content -LiteralPath $filePath -Value $content -Encoding UTF8
    return $filePath
}

function Find-NextIndex {
    param(
        [Parameter(Mandatory)]
        [int[]]$Indices,

        [Parameter(Mandatory)]
        [int]$Current
    )

    foreach ($index in $Indices) {
        if ($index -gt $Current) {
            return $index
        }
    }

    return $null
}

function Get-CustomViKeyBlocks {
    param(
        [Parameter(Mandatory)]
        [string]$FilePath,

        [Parameter(Mandatory)]
        [string]$RelativeSourcePath
    )

    $lines = @(Get-Content -LiteralPath $FilePath)
    $markerIndices = @()
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match "VI-KEY\(<Key><T>.*<P>(CCC-[^<]+)</P></Key>,\s*([^)]+)\)") {
            $markerIndices += ($i + 1)
        }
    }

    $results = New-Object System.Collections.Generic.List[object]
    foreach ($start in $markerIndices) {
        $nextMarker = Find-NextIndex -Indices $markerIndices -Current $start
        $endClass = $null
        for ($lineIndex = $start + 1; $lineIndex -le $lines.Count; $lineIndex++) {
            if ($lines[$lineIndex - 1] -match "^\s*End Class\s*$") {
                $endClass = $lineIndex
                break
            }
        }

        if ($nextMarker) {
            $end = $nextMarker - 1
        }
        elseif ($endClass) {
            $end = $endClass - 1
        }
        else {
            $end = $lines.Count
        }

        $lineText = $lines[$start - 1]
        $null = $lineText -match "VI-KEY\(<Key><T>.*<P>(CCC-[^<]+)</P></Key>,\s*([^)]+)\)"
        $key = $matches[1]
        $symbol = $matches[2]
        $snippetLines = $lines[($start - 1)..($end - 1)]

        $results.Add([pscustomobject]@{
            Name = ("{0}__{1}" -f $key, $symbol)
            RelativeSourcePath = $RelativeSourcePath
            StartLine = $start
            EndLine = $end
            Kind = "custom-vikey-block"
            Symbol = $symbol
            SnippetLines = $snippetLines
            Metadata = @{
                kind = "custom-vikey-block"
                source_key = $key
                symbol = $symbol
            }
        })
    }

    return $results
}

function Get-TypedWrapperClassBlocks {
    param(
        [Parameter(Mandatory)]
        [string]$FilePath,

        [Parameter(Mandatory)]
        [string]$RelativeSourcePath
    )

    $lines = @(Get-Content -LiteralPath $FilePath)
    $results = New-Object System.Collections.Generic.List[object]

    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match "^\s*Public Class \[(CCC_[^\]]+)\]") {
            $className = $matches[1]
            $start = $i + 1
            if ($start -gt 1 -and $lines[$start - 2] -match "EditorBrowsable") {
                $start--
            }

            $end = $null
            for ($j = $i + 1; $j -lt $lines.Count; $j++) {
                if ($lines[$j] -match "^\s*End Class\s*$") {
                    $end = $j + 1
                    break
                }
            }

            if (-not $end) {
                continue
            }

            $results.Add([pscustomobject]@{
                Name = ("TypedWrappers__{0}" -f $className)
                RelativeSourcePath = $RelativeSourcePath
                StartLine = $start
                EndLine = $end
                Kind = "typed-wrapper-class"
                Symbol = $className
                SnippetLines = $lines[($start - 1)..($end - 1)]
                Metadata = @{
                    kind = "typed-wrapper-class"
                    symbol = $className
                }
            })
        }
    }

    $customRootLine = $null
    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match 'Return "Custom"') {
            $customRootLine = $i + 1
            break
        }
    }

    if ($customRootLine) {
        $classStart = $null
        $className = $null
        for ($i = $customRootLine; $i -ge 1; $i--) {
            if ($lines[$i - 1] -match "^\s*Public Class \[(.+?)\]") {
                $classStart = $i
                $className = $matches[1]
                break
            }
        }

        $classEnd = $null
        for ($i = $customRootLine; $i -le $lines.Count; $i++) {
            if ($lines[$i - 1] -match "^\s*End Class\s*$") {
                $classEnd = $i
                break
            }
        }

        if ($classStart -and $classEnd) {
            if ($classStart -gt 1 -and $lines[$classStart - 2] -match "EditorBrowsable") {
                $classStart--
            }

            $results.Add([pscustomobject]@{
                Name = "TypedWrappers__Custom_Root"
                RelativeSourcePath = $RelativeSourcePath
                StartLine = $classStart
                EndLine = $classEnd
                Kind = "typed-wrapper-custom-root"
                Symbol = $className
                SnippetLines = $lines[($classStart - 1)..($classEnd - 1)]
                Metadata = @{
                    kind = "typed-wrapper-custom-root"
                    symbol = $className
                    logical_name = "Custom"
                }
            })
        }
    }

    return $results
}

function Get-EnclosingMemberReferenceBlocks {
    param(
        [Parameter(Mandatory)]
        [string]$FilePath,

        [Parameter(Mandatory)]
        [string]$RelativeSourcePath
    )

    $lines = @(Get-Content -LiteralPath $FilePath)
    $results = New-Object System.Collections.Generic.List[object]
    $captured = @{}

    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -notmatch "CCC_") {
            continue
        }

        $signatureStart = $null
        $signatureName = $null
        for ($j = $i + 1; $j -ge 1; $j--) {
            if ($lines[$j - 1] -match "^\s*(Public|Private|Friend|Protected)(\s+Overridable)?\s+(Function|Sub|Property)\s+([A-Za-z0-9_]+)") {
                $signatureStart = $j
                $signatureName = $matches[4]
                break
            }
            if ($lines[$j - 1] -match "^\s*End (Function|Sub|Property)\s*$") {
                break
            }
        }

        if (-not $signatureStart) {
            continue
        }

        if ($captured.ContainsKey($signatureStart)) {
            continue
        }

        $start = $signatureStart
        for ($j = $signatureStart - 1; $j -ge 1; $j--) {
            if ($lines[$j - 1] -match "^\s*' VI-KEY\(") {
                $start = $j
                continue
            }
            if ($lines[$j - 1] -match "^\s*#If\b|^\s*#End If\b|^\s*Imports\s+") {
                $start = $j
                continue
            }
            if ($lines[$j - 1] -match "^\s*$") {
                if ($start -ne $signatureStart) {
                    $start = $j + 1
                }
                break
            }
            break
        }

        $end = $null
        for ($j = $signatureStart; $j -le $lines.Count; $j++) {
            if ($lines[$j - 1] -match "^\s*End (Function|Sub|Property)\s*$") {
                $end = $j
                break
            }
        }

        if (-not $end) {
            continue
        }

        $captured[$signatureStart] = $true
        $matchValues = [regex]::Matches($lines[$i], "CCC_[A-Za-z0-9_]+") | ForEach-Object { $_.Value } | Select-Object -Unique
        $tokenSummary = ($matchValues -join "_")

        $results.Add([pscustomobject]@{
            Name = ("{0}__{1}" -f $signatureName, (ConvertTo-SafeFileName -Name $tokenSummary))
            RelativeSourcePath = $RelativeSourcePath
            StartLine = $start
            EndLine = $end
            Kind = "custom-reference-block"
            Symbol = $signatureName
            SnippetLines = $lines[($start - 1)..($end - 1)]
            Metadata = @{
                kind = "custom-reference-block"
                symbol = $signatureName
                custom_tokens = ($matchValues -join ",")
            }
        })
    }

    return $results
}

$rootFullPath = (Resolve-Path -LiteralPath $RootPath).Path
Ensure-Directory -Path $OutputPath

$allResults = New-Object System.Collections.Generic.List[object]

$viKeyFiles = @(
    "Scripts\Scripts.vb",
    "ProductScripts\ProductScripts.vb",
    "Tables\Tables.vb",
    "Table\Table.vb",
    "Tmpl\Tmpl.vb",
    "DlgMth\DlgMth.vb",
    "Parameters\Parameters.vb",
    "WebServices\WebServices.vb"
)

foreach ($relativePath in $viKeyFiles) {
    $fullPath = Join-Path $rootFullPath $relativePath
    if (-not (Test-Path -LiteralPath $fullPath)) {
        continue
    }

    foreach ($entry in Get-CustomViKeyBlocks -FilePath $fullPath -RelativeSourcePath $relativePath) {
        $outPath = New-SnippetFile -Category "definitions" -Name $entry.Name -RelativeSourcePath $entry.RelativeSourcePath -StartLine $entry.StartLine -EndLine $entry.EndLine -Lines $entry.SnippetLines -Metadata $entry.Metadata
        $allResults.Add([pscustomobject]@{
            category = "definitions"
            output = $outPath
            source = $entry.RelativeSourcePath
            start_line = $entry.StartLine
            end_line = $entry.EndLine
            kind = $entry.Kind
            symbol = $entry.Symbol
        })
    }
}

$typedWrapperPath = Join-Path $rootFullPath "TypedWrappers\TypedWrappers.vb"
if (Test-Path -LiteralPath $typedWrapperPath) {
    foreach ($entry in Get-TypedWrapperClassBlocks -FilePath $typedWrapperPath -RelativeSourcePath "TypedWrappers\TypedWrappers.vb") {
        $outPath = New-SnippetFile -Category "typed-wrappers" -Name $entry.Name -RelativeSourcePath $entry.RelativeSourcePath -StartLine $entry.StartLine -EndLine $entry.EndLine -Lines $entry.SnippetLines -Metadata $entry.Metadata
        $allResults.Add([pscustomobject]@{
            category = "typed-wrappers"
            output = $outPath
            source = $entry.RelativeSourcePath
            start_line = $entry.StartLine
            end_line = $entry.EndLine
            kind = $entry.Kind
            symbol = $entry.Symbol
        })
    }
}

$referenceFiles = @(
    "ProductScripts\ProductScripts.vb",
    "Scripts\Scripts.vb",
    "Tables\Tables.vb",
    "Table\Table.vb",
    "Tmpl\Tmpl.vb",
    "DlgMth\DlgMth.vb",
    "Parameters\Parameters.vb",
    "WebServices\WebServices.vb"
)

foreach ($relativePath in $referenceFiles) {
    $fullPath = Join-Path $rootFullPath $relativePath
    if (-not (Test-Path -LiteralPath $fullPath)) {
        continue
    }

    foreach ($entry in Get-EnclosingMemberReferenceBlocks -FilePath $fullPath -RelativeSourcePath $relativePath) {
        $sourceLeafBase = [System.IO.Path]::GetFileNameWithoutExtension($relativePath)
        $outPath = New-SnippetFile -Category "references" -Name ("{0}__{1}" -f $sourceLeafBase, $entry.Name) -RelativeSourcePath $entry.RelativeSourcePath -StartLine $entry.StartLine -EndLine $entry.EndLine -Lines $entry.SnippetLines -Metadata $entry.Metadata
        $allResults.Add([pscustomobject]@{
            category = "references"
            output = $outPath
            source = $entry.RelativeSourcePath
            start_line = $entry.StartLine
            end_line = $entry.EndLine
            kind = $entry.Kind
            symbol = $entry.Symbol
        })
    }
}

$indexPath = Join-Path $OutputPath "custom-index.json"
$allResults | Sort-Object category, source, start_line | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $indexPath -Encoding UTF8

[pscustomobject]@{
    RootPath = $rootFullPath
    OutputPath = $OutputPath
    ExtractedCount = $allResults.Count
    IndexPath = $indexPath
}
