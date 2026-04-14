Set-StrictMode -Version Latest

function Get-OneImAuditSettings {
    return [pscustomobject]@{
        OneImSurfaceFolders = @(
            "Scripts",
            "ProductScripts",
            "Tables",
            "Table",
            "Tmpl",
            "DlgMth",
            "Parameters",
            "TypedWrappers",
            "WebServices"
        )
        ExcludedTargetSegments = @(
            "\reference-library\",
            "\output\",
            "\.agents\",
            "\.codex-skill-work\",
            "\.tmp\",
            "\skills\",
            "\apps\",
            "\bin\",
            "\obj\"
        )
    }
}

function New-OneImAuditDirectory {
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
}

function Get-OneImAuditFullPath {
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    return [System.IO.Path]::GetFullPath((Resolve-Path -LiteralPath $Path).Path)
}

function ConvertTo-OneImAuditSlug {
    param(
        [Parameter(Mandatory)]
        [string]$Value
    )

    $slug = $Value.ToLowerInvariant()
    $slug = [regex]::Replace($slug, "[^a-z0-9]+", "-")
    return $slug.Trim("-")
}

function Get-OneImAuditRelativePathCompat {
    param(
        [Parameter(Mandatory)]
        [string]$BasePath,

        [Parameter(Mandatory)]
        [string]$TargetPath
    )

    $baseFullPath = Get-OneImAuditFullPath -Path $BasePath
    $targetFullPath = Get-OneImAuditFullPath -Path $TargetPath

    if ([System.IO.Path]::GetPathRoot($baseFullPath) -ne [System.IO.Path]::GetPathRoot($targetFullPath)) {
        return $targetFullPath
    }

    $baseUri = New-Object System.Uri(($baseFullPath.TrimEnd('\') + '\'))
    $targetUri = New-Object System.Uri($targetFullPath)
    $relative = $baseUri.MakeRelativeUri($targetUri)
    return [System.Uri]::UnescapeDataString($relative.ToString()).Replace("/", "\")
}

function Resolve-OneImAuditTargetRoot {
    param(
        [Parameter(Mandatory)]
        [string]$TargetPath
    )

    $fullPath = Get-OneImAuditFullPath -Path $TargetPath
    $item = Get-Item -LiteralPath $fullPath
    if ($item -is [System.IO.DirectoryInfo]) {
        return $fullPath
    }

    $settings = Get-OneImAuditSettings
    $current = $item.Directory
    while ($null -ne $current) {
        foreach ($surface in $settings.OneImSurfaceFolders) {
            if ([System.StringComparer]::OrdinalIgnoreCase.Equals($current.Name, $surface)) {
                if ($null -ne $current.Parent) {
                    return $current.Parent.FullName
                }

                return $current.FullName
            }
        }

        $current = $current.Parent
    }

    return $item.Directory.FullName
}

function Normalize-OneImAuditRelativePath {
    param(
        [Parameter()]
        [string]$Path
    )

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return $Path
    }

    return $Path.Replace("/", "\").Trim()
}

function Get-OneImAuditRelativePath {
    param(
        [Parameter(Mandatory)]
        [string]$FullPath,

        [Parameter(Mandatory)]
        [string]$RootPath
    )

    $settings = Get-OneImAuditSettings
    $relative = Get-OneImAuditRelativePathCompat -BasePath $RootPath -TargetPath $FullPath
    $segments = $relative -split "\\"
    for ($index = 0; $index -lt $segments.Length; $index++) {
        foreach ($surface in $settings.OneImSurfaceFolders) {
            if ([System.StringComparer]::OrdinalIgnoreCase.Equals($segments[$index], $surface)) {
                return (($segments[$index..($segments.Length - 1)]) -join "\")
            }
        }
    }

    return $relative
}

function Get-OneImAuditDetectedSurface {
    param(
        [Parameter()]
        [string]$RelativePath
    )

    $normalized = Normalize-OneImAuditRelativePath -Path $RelativePath
    if ([string]::IsNullOrWhiteSpace($normalized)) {
        return "any"
    }

    $firstSegment = ($normalized -split "\\")[0]
    switch -Regex ($firstSegment) {
        '^(Scripts|ProductScripts)$'          { return "script" }
        '^(Table|Tables|Tmpl)$'               { return "template" }
        '^(DlgMth|Parameters|WebServices)$'   { return "process" }
        '^TypedWrappers$'                     { return "formatter" }
        default                               { return "any" }
    }
}

function Get-OneImAuditConfig {
    <#
    .SYNOPSIS
        Loads the auditor configuration from audit-config.json (relative to the assets folder
        next to this module, or from an explicit path), merging with built-in defaults so that
        missing keys always resolve to a sensible value.
    .PARAMETER ConfigPath
        Optional explicit path to a JSON config file. When omitted the function searches for
        assets/audit-config.json relative to the module root, then falls back to all defaults.
    #>
    param(
        [Parameter()]
        [string]$ConfigPath
    )

    # Built-in defaults (same values as in audit-config.json).
    $defaults = @{
        detection = @{
            header_scan_lines              = 40
            mvp_guard_lookback_lines       = 10
            nearby_throw_lookahead_lines   = 6
            nearby_dispose_lookahead_lines = 8
            context_lines                  = 6
            global_max_examples_per_file   = 8
        }
        confidence = @{
            high_threshold   = 80
            medium_threshold = 60
        }
        scoring = @{
            severity_weights = @{ high = 3; medium = 2; low = 1 }
            category_thresholds = @{ green_max = 2.0; yellow_max = 5.0; orange_max = 10.0 }
            overall_thresholds  = @{ green_max = 5.0; yellow_max = 15.0; orange_max = 30.0 }
        }
    }

    # Resolve path: explicit arg > assets/audit-config.json next to module.
    if ([string]::IsNullOrWhiteSpace($ConfigPath)) {
        $assetsDir = Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) "assets"
        $candidate = Join-Path $assetsDir "audit-config.json"
        if (Test-Path -LiteralPath $candidate) { $ConfigPath = $candidate }
    }

    if (-not [string]::IsNullOrWhiteSpace($ConfigPath) -and (Test-Path -LiteralPath $ConfigPath)) {
        try {
            $raw = Get-Content -LiteralPath $ConfigPath -Raw | ConvertFrom-Json
            # Merge detection keys — use PSObject.Properties to avoid strict-mode
            # PropertyNotFoundException when the JSON omits some keys.
            foreach ($key in @($defaults.detection.Keys)) {
                if ($null -ne $raw.detection) {
                    $p = $raw.detection.PSObject.Properties.Match($key)
                    if ($p.Count -gt 0 -and $null -ne $p[0].Value) {
                        $defaults.detection[$key] = [int]$p[0].Value
                    }
                }
            }
            # Merge confidence keys
            foreach ($key in @($defaults.confidence.Keys)) {
                if ($null -ne $raw.confidence) {
                    $p = $raw.confidence.PSObject.Properties.Match($key)
                    if ($p.Count -gt 0 -and $null -ne $p[0].Value) {
                        $defaults.confidence[$key] = [int]$p[0].Value
                    }
                }
            }
            # Merge scoring.severity_weights
            if ($null -ne $raw.scoring -and $null -ne $raw.scoring.severity_weights) {
                foreach ($k in @('high','medium','low')) {
                    $p = $raw.scoring.severity_weights.PSObject.Properties.Match($k)
                    if ($p.Count -gt 0 -and $null -ne $p[0].Value) { $defaults.scoring.severity_weights[$k] = [int]$p[0].Value }
                }
            }
            # Merge scoring.category_thresholds and overall_thresholds
            foreach ($section in @('category_thresholds','overall_thresholds')) {
                if ($null -ne $raw.scoring) {
                    $sp = $raw.scoring.PSObject.Properties.Match($section)
                    if ($sp.Count -gt 0 -and $null -ne $sp[0].Value) {
                        foreach ($k in @('green_max','yellow_max','orange_max')) {
                            $p = $sp[0].Value.PSObject.Properties.Match($k)
                            if ($p.Count -gt 0 -and $null -ne $p[0].Value) { $defaults.scoring[$section][$k] = [double]$p[0].Value }
                        }
                    }
                }
            }
        }
        catch {
            Write-Warning "audit-config.json could not be loaded ($($_.Exception.Message)). Using all defaults."
        }
    }

    return $defaults
}

function Get-OneImAuditScoreColor {
    <#
    .SYNOPSIS
        Returns a CSS class name (score-green / score-yellow / score-orange / score-red)
        for a numeric risk score given a thresholds hashtable with green_max, yellow_max, orange_max.
    #>
    param(
        [double]$Score,
        [hashtable]$Thresholds
    )
    if ($Score -lt $Thresholds.green_max)  { return "score-green" }
    if ($Score -lt $Thresholds.yellow_max) { return "score-yellow" }
    if ($Score -lt $Thresholds.orange_max) { return "score-orange" }
    return "score-red"
}

function Get-OneImAuditConfidenceLabel {
    param(
        [Parameter(Mandatory)]
        [int]$Score,

        [Parameter()]
        [hashtable]$Config
    )

    $highThreshold   = if ($null -ne $Config) { $Config.confidence.high_threshold }   else { 80 }
    $mediumThreshold = if ($null -ne $Config) { $Config.confidence.medium_threshold } else { 60 }

    if ($Score -ge $highThreshold)   { return "high" }
    if ($Score -ge $mediumThreshold) { return "medium" }
    return "low"
}

Export-ModuleMember -Function `
    Get-OneImAuditSettings, `
    New-OneImAuditDirectory, `
    Get-OneImAuditFullPath, `
    ConvertTo-OneImAuditSlug, `
    Get-OneImAuditRelativePathCompat, `
    Resolve-OneImAuditTargetRoot, `
    Normalize-OneImAuditRelativePath, `
    Get-OneImAuditRelativePath, `
    Get-OneImAuditDetectedSurface, `
    Get-OneImAuditConfig, `
    Get-OneImAuditScoreColor, `
    Get-OneImAuditConfidenceLabel
