Set-StrictMode -Version Latest

function Test-OneImRawExportShape {
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    $settings = Get-OneImAuditSettings
    $fullPath = Get-OneImAuditFullPath -Path $Path
    $surfaceMatches = @()
    foreach ($surface in $settings.OneImSurfaceFolders) {
        $surfacePath = Join-Path $fullPath $surface
        if (Test-Path -LiteralPath $surfacePath) {
            $surfaceMatches += $surface
        }
    }

    $vbCount = 0
    $topFiles = Get-ChildItem -LiteralPath $fullPath -Recurse -File -Filter "*.vb" -ErrorAction SilentlyContinue
    if ($topFiles) {
        $vbCount = @($topFiles).Count
    }

    return [pscustomobject]@{
        path = $fullPath
        surface_matches = @($surfaceMatches | Sort-Object -Unique)
        surface_count = @($surfaceMatches | Sort-Object -Unique).Count
        vb_file_count = $vbCount
        is_likely_raw_export = (@($surfaceMatches).Count -ge 2 -and $vbCount -ge 1)
    }
}

function Get-OneImTierEntryCount {
    param(
        [Parameter(Mandatory)]
        [string]$TierPath
    )

    if (-not (Test-Path -LiteralPath $TierPath)) {
        return 0
    }

    $files = Get-ChildItem -LiteralPath $TierPath -Recurse -File -Filter "*.vb" -ErrorAction SilentlyContinue
    if (-not $files) {
        return 0
    }

    return @($files).Count
}

function Get-OneImReferenceLayout {
    param(
        [Parameter(Mandatory)]
        [string]$ReferenceRepoPath,

        [Parameter(Mandatory)]
        [string]$OneImVersion
    )

    $referenceFullPath = Get-OneImAuditFullPath -Path $ReferenceRepoPath
    $versionFolder = "oneim-{0}" -f $OneImVersion
    $requiredTiers = @("ootb", "promoted-custom", "candidate-custom", "rejected", "intake-manifests")

    $candidates = @(
        [pscustomobject]@{
            mode = "repo-root"
            reference_root = Join-Path $referenceFullPath "reference-library"
            version_root = Join-Path (Join-Path $referenceFullPath "reference-library") $versionFolder
        }
        [pscustomobject]@{
            mode = "reference-library-root"
            reference_root = $referenceFullPath
            version_root = Join-Path $referenceFullPath $versionFolder
        }
        [pscustomobject]@{
            mode = "version-root"
            reference_root = Split-Path -Parent $referenceFullPath
            version_root = $referenceFullPath
        }
    )

    foreach ($candidate in $candidates) {
        $isVersionRootCandidate = [System.StringComparer]::OrdinalIgnoreCase.Equals(
            [System.IO.Path]::GetFileName($candidate.version_root),
            $versionFolder
        )

        if (-not $isVersionRootCandidate) {
            continue
        }

        if (-not (Test-Path -LiteralPath $candidate.version_root)) {
            continue
        }

        $missing = @()
        foreach ($tier in $requiredTiers) {
            if (-not (Test-Path -LiteralPath (Join-Path $candidate.version_root $tier))) {
                $missing += $tier
            }
        }

        $ootbCount = Get-OneImTierEntryCount -TierPath (Join-Path $candidate.version_root "ootb")
        return [pscustomobject]@{
            mode = $candidate.mode
            reference_root = $candidate.reference_root
            version_root = $candidate.version_root
            version_folder = $versionFolder
            missing_tiers = @($missing)
            ootb_file_count = $ootbCount
            is_valid = (@($missing).Count -eq 0 -and $ootbCount -gt 0)
        }
    }

    return $null
}

function Invoke-OneImReferenceRestructure {
    param(
        [Parameter(Mandatory)]
        [string]$ReferenceRepoPath,

        [Parameter(Mandatory)]
        [string]$OneImVersion,

        [Parameter(Mandatory)]
        [string]$RegisterScriptPath
    )

    if (-not (Test-Path -LiteralPath $RegisterScriptPath)) {
        throw "Missing reference registration script at $RegisterScriptPath"
    }

    $referenceFullPath = Get-OneImAuditFullPath -Path $ReferenceRepoPath
    $label = ConvertTo-OneImAuditSlug -Value ([System.IO.Path]::GetFileName($referenceFullPath))
    if ([string]::IsNullOrWhiteSpace($label)) {
        $label = "reference-export"
    }

    & $RegisterScriptPath `
        -ExportPath $referenceFullPath `
        -ReferenceLibraryRoot (Join-Path $referenceFullPath "reference-library") `
        -OneImVersion $OneImVersion `
        -Label $label | Out-Null
}

function Resolve-OneImReferenceLayoutOrThrow {
    param(
        [Parameter(Mandatory)]
        [string]$ReferenceRepoPath,

        [Parameter(Mandatory)]
        [string]$OneImVersion,

        [Parameter(Mandatory)]
        [bool]$AutoRestructure,

        [Parameter(Mandatory)]
        [bool]$DisablePrompt,

        [Parameter(Mandatory)]
        [string]$RegisterScriptPath
    )

    $layout = Get-OneImReferenceLayout -ReferenceRepoPath $ReferenceRepoPath -OneImVersion $OneImVersion
    if ($layout -and $layout.is_valid) {
        return $layout
    }

    $referenceFullPath = Get-OneImAuditFullPath -Path $ReferenceRepoPath
    $rawExport = Test-OneImRawExportShape -Path $referenceFullPath
    $expectedLines = @(
        "Expected one of these layouts for OneIM ${OneImVersion}:",
        "  <repo-root>\reference-library\oneim-$OneImVersion\ootb\...",
        "  <reference-library-root>\oneim-$OneImVersion\ootb\...",
        "  <version-root>\ootb\..."
    )

    if ($rawExport.is_likely_raw_export) {
        $messageLines = @(
            "Reference repo path '$referenceFullPath' is not a valid managed reference library yet.",
            "Detected raw System Debugger export indicators: $($rawExport.surface_matches -join ', ').",
            "The auditor needs a managed reference layout before it can run reliably.",
            ""
        ) + $expectedLines

        $message = $messageLines -join [Environment]::NewLine

        if ($AutoRestructure) {
            Write-Warning $message
            Write-Host "Restructuring the raw export into a managed reference library..." -ForegroundColor Yellow
            Invoke-OneImReferenceRestructure -ReferenceRepoPath $referenceFullPath -OneImVersion $OneImVersion -RegisterScriptPath $RegisterScriptPath
            $retryLayout = Get-OneImReferenceLayout -ReferenceRepoPath $referenceFullPath -OneImVersion $OneImVersion
            if ($retryLayout -and $retryLayout.is_valid) {
                return $retryLayout
            }

            throw "Restructuring completed, but the managed reference layout is still not valid under '$referenceFullPath'."
        }

        if (-not $DisablePrompt) {
            Write-Warning $message
            $answer = Read-Host "Do you want to restructure this export now so the auditor can run successfully? [Y/N]"
            if ($answer -match "^(y|yes)$") {
                Invoke-OneImReferenceRestructure -ReferenceRepoPath $referenceFullPath -OneImVersion $OneImVersion -RegisterScriptPath $RegisterScriptPath
                $retryLayout = Get-OneImReferenceLayout -ReferenceRepoPath $referenceFullPath -OneImVersion $OneImVersion
                if ($retryLayout -and $retryLayout.is_valid) {
                    return $retryLayout
                }

                throw "Restructuring completed, but the managed reference layout is still not valid under '$referenceFullPath'."
            }
        }

        throw "$message`nRestructuring was not performed. Re-run with -AutoRestructureIfNeeded or answer Y when prompted."
    }

    if ($layout) {
        $missingText = if (@($layout.missing_tiers).Count -gt 0) { $layout.missing_tiers -join ", " } else { "none" }
        throw (@(
                "Reference repo path '$referenceFullPath' has a partial managed layout for OneIM $OneImVersion, but it is not valid.",
                "Missing tiers: $missingText",
                "OOTB VB file count: $($layout.ootb_file_count)",
                ""
            ) + $expectedLines) -join [Environment]::NewLine
    }

    throw (@(
            "Reference repo path '$referenceFullPath' does not match a managed reference layout and does not look like a raw System Debugger export.",
            ""
        ) + $expectedLines) -join [Environment]::NewLine
}

function Get-OneImTierRoots {
    param(
        [Parameter(Mandatory)]
        [string]$VersionRoot,

        [Parameter(Mandatory)]
        [string]$TierName
    )

    $tierPath = Join-Path $VersionRoot $TierName
    if (-not (Test-Path -LiteralPath $tierPath)) {
        return @()
    }

    $roots = New-Object System.Collections.Generic.List[string]
    $tierFiles = Get-ChildItem -LiteralPath $tierPath -Recurse -File -Filter "*.vb" -ErrorAction SilentlyContinue
    if ($tierFiles) {
        $directFiles = Get-ChildItem -LiteralPath $tierPath -File -Filter "*.vb" -ErrorAction SilentlyContinue
        if ($directFiles) {
            $roots.Add($tierPath)
        }
    }

    $childDirs = Get-ChildItem -LiteralPath $tierPath -Directory -ErrorAction SilentlyContinue
    foreach ($childDir in $childDirs) {
        $vbFiles = Get-ChildItem -LiteralPath $childDir.FullName -Recurse -File -Filter "*.vb" -ErrorAction SilentlyContinue
        if ($vbFiles) {
            $roots.Add($childDir.FullName)
        }
    }

    return @($roots | Sort-Object -Unique)
}

function Get-OneImPrimaryOotbRoot {
    param(
        [Parameter(Mandatory)]
        [string]$VersionRoot
    )

    $roots = @(Get-OneImTierRoots -VersionRoot $VersionRoot -TierName "ootb")
    if ($roots.Count -eq 0) {
        return $null
    }

    $bestRoot = $null
    $bestCount = -1
    foreach ($root in $roots) {
        $count = Get-OneImTierEntryCount -TierPath $root
        if ($count -gt $bestCount) {
            $bestCount = $count
            $bestRoot = $root
        }
    }

    return $bestRoot
}

function Get-OneImReferenceFileMap {
    param(
        [Parameter(Mandatory)]
        [string]$RootPath
    )

    $map = @{}
    if (-not $RootPath) {
        return $map
    }

    $files = Get-ChildItem -LiteralPath $RootPath -Recurse -File -Filter "*.vb" -ErrorAction SilentlyContinue
    foreach ($file in $files) {
        $relative = Get-OneImAuditRelativePath -FullPath $file.FullName -RootPath $RootPath
        if (-not $map.ContainsKey($relative)) {
            $map[$relative] = $file.FullName
        }
    }

    return $map
}

function Get-OneImTargetFiles {
    param(
        [Parameter(Mandatory)]
        [string]$TargetPath
    )

    $settings = Get-OneImAuditSettings
    $fullPath = Get-OneImAuditFullPath -Path $TargetPath
    if ((Get-Item -LiteralPath $fullPath) -is [System.IO.FileInfo]) {
        if ([System.IO.Path]::GetExtension($fullPath) -ieq ".vb") {
            return @($fullPath)
        }

        return @()
    }

    $files = Get-ChildItem -LiteralPath $fullPath -Recurse -File -Filter "*.vb" -ErrorAction SilentlyContinue
    $results = New-Object System.Collections.Generic.List[string]
    foreach ($file in $files) {
        $normalized = $file.FullName.Replace("/", "\").ToLowerInvariant()
        $skip = $false
        foreach ($segment in $settings.ExcludedTargetSegments) {
            if ($normalized.Contains($segment.ToLowerInvariant())) {
                $skip = $true
                break
            }
        }

        if (-not $skip) {
            $results.Add($file.FullName)
        }
    }

    return @($results)
}

Export-ModuleMember -Function `
    Test-OneImRawExportShape, `
    Get-OneImTierEntryCount, `
    Get-OneImReferenceLayout, `
    Invoke-OneImReferenceRestructure, `
    Resolve-OneImReferenceLayoutOrThrow, `
    Get-OneImTierRoots, `
    Get-OneImPrimaryOotbRoot, `
    Get-OneImReferenceFileMap, `
    Get-OneImTargetFiles
