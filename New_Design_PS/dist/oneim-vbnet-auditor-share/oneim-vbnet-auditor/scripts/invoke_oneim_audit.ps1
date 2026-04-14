<#
.SYNOPSIS
Audits One Identity Manager VB.NET code with a mandatory managed reference repository.

.DESCRIPTION
Runs a local-first correctness, security, and performance audit over OneIM VB.NET files.
The auditor always requires -ReferenceRepoPath. That path must already expose a managed
reference-library layout for the requested OneIM version, or it must be a raw System
Debugger export that can be restructured into that layout.

If the reference path looks like a raw export and the structure is not valid, the script:
- explains what is missing
- offers restructure in interactive runs
- supports explicit bootstrap with -AutoRestructureIfNeeded

.PARAMETER TargetPath
One or more repository roots or individual .vb files to audit. For shell-safe
automation via powershell -File, you can also pass a single | delimited string.

.PARAMETER ReferenceRepoPath
Mandatory path to a managed OneIM reference repo or a raw System Debugger export.

.PARAMETER OneImVersion
Target One Identity Manager version. Defaults to 9.3.1.

.PARAMETER OutputDir
Root output directory for timestamped audit-report.json and audit-report.html files.

.PARAMETER AutoRestructureIfNeeded
If the reference path is a raw export instead of a managed library, restructure it automatically.

.PARAMETER NoPrompt
Disable restructure prompting. Use this for unattended runs.

.PARAMETER SuppressionsFile
Deprecated for this phase. Suppressions are intentionally disabled while the rule
set is being tuned. Supplying this parameter causes the audit to fail fast.

.PARAMETER BenchmarkReportPath
Optional path to a benchmark-report.json produced by invoke_oneim_benchmark.ps1.
When supplied, benchmark timings are surfaced as performance evidence annotations in the
audit report. Threshold overruns become additional performance findings only when
-ThresholdsFile is also provided.

.PARAMETER SchemaSnapshotPath
Optional path to a schema-snapshot.json produced by export_oneim_schema_snapshot.ps1.
When supplied, FK traversal metadata is used to enrich explanations for template-related
findings.

.PARAMETER ThresholdsFile
Optional JSON thresholds file (same format as invoke_oneim_benchmark.ps1 accepts). When
combined with -BenchmarkReportPath, targets that exceed their threshold are promoted to
performance findings in the audit output.

.PARAMETER CascadeReportPath
Optional path to a cascade-<name>.json produced by export_template_cascade_report.ps1.
When supplied, nodes whose concurrency_risk is 'write-cycle' are injected as CNC610 findings
in the audit output, identifying templates that write values inside a circular dependency.

.PARAMETER AuditConfigPath
Optional path to a JSON configuration file that overrides built-in detection thresholds,
confidence bands, and scoring weights. When omitted the auditor looks for
assets/audit-config.json next to the skill root and falls back to built-in defaults.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string[]]$TargetPath,

    [Parameter(Mandatory)]
    [string]$ReferenceRepoPath,

    [Parameter()]
    [string]$OneImVersion = "9.3.1",

    [Parameter()]
    [string]$OutputDir = (Join-Path (Get-Location).Path "output\oneim-vbnet-audit"),

    [Parameter()]
    [switch]$AutoRestructureIfNeeded,

    [Parameter()]
    [switch]$NoPrompt,

    [Parameter()]
    [string]$SuppressionsFile,

    [Parameter()]
    [string]$BenchmarkReportPath,

    [Parameter()]
    [string]$SchemaSnapshotPath,

    [Parameter()]
    [string]$ThresholdsFile,

    [Parameter()]
    [string]$CascadeReportPath,

    [Parameter()]
    [string]$AuditConfigPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$scriptRoot = Split-Path -Parent $PSCommandPath
$skillRoot = Split-Path -Parent $scriptRoot
$moduleRoot = Join-Path $scriptRoot "modules"
$approvedSourcesPath = Join-Path $skillRoot "assets\approved-sources.json"
$ruleCatalogPath = Join-Path $skillRoot "assets\audit-rules.json"
$registerScriptPath = Join-Path $scriptRoot "register_reference_export.ps1"

foreach ($modulePath in @(
    (Join-Path $moduleRoot "OneimAudit.Common.psm1"),
    (Join-Path $moduleRoot "OneimAudit.RuleCatalog.psm1"),
    (Join-Path $moduleRoot "OneimAudit.Reference.psm1"),
    (Join-Path $moduleRoot "OneimAudit.Detectors.psm1"),
    (Join-Path $moduleRoot "OneimAudit.PostProcessing.psm1"),
    (Join-Path $moduleRoot "OneimAudit.Reporting.psm1")
)) {
    if (-not (Test-Path -LiteralPath $modulePath)) {
        throw "Missing module at $modulePath"
    }

    Import-Module $modulePath -Force
}

function Get-OneImAuditCommonRootPath {
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [string[]]$Paths
    )

    $resolvedPaths = @($Paths | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object {
            [System.IO.Path]::GetFullPath($_).TrimEnd('\')
        } | Select-Object -Unique)

    if (@($resolvedPaths).Count -eq 0) {
        throw "At least one target path is required to compute the audit root."
    }

    if (@($resolvedPaths).Count -eq 1) {
        return $resolvedPaths[0]
    }

    $splitPaths = @()
    foreach ($path in $resolvedPaths) {
        $splitPaths += ,($path -split "\\")
    }

    $commonSegments = New-Object System.Collections.Generic.List[string]
    for ($index = 0; $index -lt $splitPaths[0].Length; $index++) {
        $segment = $splitPaths[0][$index]
        $allMatch = $true
        foreach ($segments in $splitPaths) {
            if ($segments.Length -le $index -or -not [System.StringComparer]::OrdinalIgnoreCase.Equals($segments[$index], $segment)) {
                $allMatch = $false
                break
            }
        }

        if (-not $allMatch) {
            break
        }

        $commonSegments.Add($segment)
    }

    if ($commonSegments.Count -eq 0) {
        return [System.IO.Path]::GetPathRoot($resolvedPaths[0])
    }

    if ($commonSegments.Count -eq 1 -and $commonSegments[0] -match "^[A-Za-z]:$") {
        return ($commonSegments[0] + "\")
    }

    return ($commonSegments.ToArray() -join "\")
}

function Expand-OneImAuditTargetPathSelection {
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [string[]]$TargetPath
    )

    $expandedTargets = New-Object System.Collections.Generic.List[string]
    foreach ($rawTarget in @($TargetPath)) {
        if ([string]::IsNullOrWhiteSpace($rawTarget)) {
            continue
        }

        foreach ($candidate in @($rawTarget -split '\r?\n|\|')) {
            $trimmedCandidate = $candidate.Trim()
            if (-not [string]::IsNullOrWhiteSpace($trimmedCandidate)) {
                $expandedTargets.Add($trimmedCandidate)
            }
        }
    }

    return @($expandedTargets.ToArray() | Select-Object -Unique)
}

try {
    if (-not (Test-Path -LiteralPath $approvedSourcesPath)) {
        throw "Missing approved source catalog at $approvedSourcesPath"
    }

    if (-not (Test-Path -LiteralPath $ruleCatalogPath)) {
        throw "Missing audit rule catalog at $ruleCatalogPath"
    }

    if (-not [string]::IsNullOrWhiteSpace($SuppressionsFile)) {
        throw "Suppressions are intentionally disabled during this rule-tuning phase. Remove -SuppressionsFile and rerun the audit."
    }

    $normalizedTargetSelection = @(Expand-OneImAuditTargetPathSelection -TargetPath $TargetPath)
    if (@($normalizedTargetSelection).Count -eq 0) {
        throw "At least one target path is required."
    }

    $resolvedTargetInputs = @($normalizedTargetSelection | ForEach-Object { Get-OneImAuditFullPath -Path $_ } | Select-Object -Unique)
    $targetAuditRoots = @($resolvedTargetInputs | ForEach-Object { Resolve-OneImAuditTargetRoot -TargetPath $_ } | Select-Object -Unique)
    $targetAuditRoot = Get-OneImAuditCommonRootPath -Paths $targetAuditRoots
    $layout = Resolve-OneImReferenceLayoutOrThrow `
        -ReferenceRepoPath $ReferenceRepoPath `
        -OneImVersion $OneImVersion `
        -AutoRestructure:$AutoRestructureIfNeeded.IsPresent `
        -DisablePrompt:$NoPrompt.IsPresent `
        -RegisterScriptPath $registerScriptPath

    $outputRoot = [System.IO.Path]::GetFullPath($OutputDir)
    $runFolder = Join-Path $outputRoot (Get-Date -Format "yyyyMMdd-HHmmss")
    New-OneImAuditDirectory -Path $runFolder

    $ruleCatalog = Get-OneImAuditRuleCatalog -RuleCatalogPath $ruleCatalogPath
    $sourceLookup = Get-OneImAuditSourceLookup -ApprovedSourcesPath $approvedSourcesPath
    $auditConfig = Get-OneImAuditConfig -ConfigPath $AuditConfigPath

    # -----------------------------------------------------------------------
    # Optional: load benchmark report
    # -----------------------------------------------------------------------
    $benchmarkEvidence = @{}   # key: "surface::name", value: result object
    $resolvedBenchmarkPath = $null

    if (-not [string]::IsNullOrWhiteSpace($BenchmarkReportPath)) {
        $resolvedBenchmarkPath = [System.IO.Path]::GetFullPath($BenchmarkReportPath)
        if (-not (Test-Path -LiteralPath $resolvedBenchmarkPath)) {
            Write-Warning ("Benchmark report not found at '{0}'. Benchmark evidence will be skipped." -f $resolvedBenchmarkPath)
            $resolvedBenchmarkPath = $null
        } else {
            $benchRaw = Get-Content -LiteralPath $resolvedBenchmarkPath -Raw | ConvertFrom-Json
            foreach ($r in @($benchRaw.results)) {
                $bKey = ("{0}::{1}" -f [string]$r.surface, [string]$r.name)
                $benchmarkEvidence[$bKey] = $r
            }
            Write-Host ("Loaded {0} benchmark result(s) from: {1}" -f $benchmarkEvidence.Count, $resolvedBenchmarkPath)
        }
    }

    # -----------------------------------------------------------------------
    # Optional: load thresholds
    # -----------------------------------------------------------------------
    $thresholdMap = @{}
    $resolvedThresholdsPath = $null

    if (-not [string]::IsNullOrWhiteSpace($ThresholdsFile)) {
        $resolvedThresholdsPath = [System.IO.Path]::GetFullPath($ThresholdsFile)
        if (-not (Test-Path -LiteralPath $resolvedThresholdsPath)) {
            Write-Warning ("Thresholds file not found at '{0}'." -f $resolvedThresholdsPath)
            $resolvedThresholdsPath = $null
        } else {
            $threshRaw = Get-Content -LiteralPath $resolvedThresholdsPath -Raw | ConvertFrom-Json
            foreach ($t in @($threshRaw)) {
                $tKey = ("{0}::{1}" -f [string]$t.surface, [string]$t.name)
                $thresholdMap[$tKey] = $t
            }
        }
    }

    # -----------------------------------------------------------------------
    # Optional: load schema snapshot for FK-enriched explanations
    # -----------------------------------------------------------------------
    $schemaSnapshot = $null
    $resolvedSchemaPath = $null

    if (-not [string]::IsNullOrWhiteSpace($SchemaSnapshotPath)) {
        $resolvedSchemaPath = [System.IO.Path]::GetFullPath($SchemaSnapshotPath)
        if (-not (Test-Path -LiteralPath $resolvedSchemaPath)) {
            Write-Warning ("Schema snapshot not found at '{0}'. FK enrichment will be skipped." -f $resolvedSchemaPath)
            $resolvedSchemaPath = $null
        } else {
            $schemaSnapshot = Get-Content -LiteralPath $resolvedSchemaPath -Raw | ConvertFrom-Json
            Write-Host ("Loaded schema snapshot ({0} tables, {1} FK edges) from: {2}" -f @($schemaSnapshot.tables).Count, @($schemaSnapshot.fk_relations).Count, $resolvedSchemaPath)
        }
    }
    # -----------------------------------------------------------------------
    # Optional: load cascade report for CNC610 write-cycle findings
    # -----------------------------------------------------------------------
    $cascadeWriteCycleNodes = @()

    if (-not [string]::IsNullOrWhiteSpace($CascadeReportPath)) {
        $resolvedCascadePath = [System.IO.Path]::GetFullPath($CascadeReportPath)
        if (-not (Test-Path -LiteralPath $resolvedCascadePath)) {
            Write-Warning ("Cascade report not found at '{0}'. CNC610 injection will be skipped." -f $resolvedCascadePath)
        } else {
            $cascadeRaw = Get-Content -LiteralPath $resolvedCascadePath -Raw | ConvertFrom-Json
            foreach ($scc in @($cascadeRaw.strongly_connected_components)) {
                if ([string]$scc.concurrency_risk -eq "write-cycle") {
                    foreach ($memberKey in @($scc.members)) {
                        $cascadeWriteCycleNodes += [pscustomobject]@{ key = [string]$memberKey; scc_id = [int]$scc.scc_id; scc_size = [int]$scc.size }
                    }
                }
            }
            Write-Host ("Loaded cascade report: {0} write-cycle node(s) eligible for CNC610." -f $cascadeWriteCycleNodes.Count)
        }
    }

    $primaryOotbRoot = Get-OneImPrimaryOotbRoot -VersionRoot $layout.version_root
    $ootbMap = if ($primaryOotbRoot) { Get-OneImReferenceFileMap -RootPath $primaryOotbRoot } else { @{} }
    $promotedRoots = @(Get-OneImTierRoots -VersionRoot $layout.version_root -TierName "promoted-custom")
    $candidateRoots = @(Get-OneImTierRoots -VersionRoot $layout.version_root -TierName "candidate-custom")
    $targetFiles = New-Object 'System.Collections.Generic.List[string]'
    $seenTargetFiles = @{}
    foreach ($targetInput in $resolvedTargetInputs) {
        foreach ($targetFile in @(Get-OneImTargetFiles -TargetPath $targetInput)) {
            $resolvedTargetFile = Get-OneImAuditFullPath -Path $targetFile
            $targetKey = $resolvedTargetFile.ToLowerInvariant()
            if (-not $seenTargetFiles.ContainsKey($targetKey)) {
                $seenTargetFiles[$targetKey] = $true
                $targetFiles.Add($resolvedTargetFile)
            }
        }
    }
    $targetFiles = @($targetFiles.ToArray() | Sort-Object)

    if (@($targetFiles).Count -eq 0) {
        throw "No VB.NET files were found under the selected target paths after excluding generated and reference-library folders: '$($resolvedTargetInputs -join "', '")'."
    }

    $settings = Get-OneImAuditSettings
    $findings = New-Object 'System.Collections.Generic.List[object]'
    $fileSummaries = New-Object 'System.Collections.Generic.List[object]'
    $unresolvedQuestions = New-Object 'System.Collections.Generic.List[string]'

    foreach ($targetFile in $targetFiles) {
        $relativePath = Get-OneImAuditRelativePath -FullPath $targetFile -RootPath $targetAuditRoot
        $fileFindings = @(Get-OneImFileFindings -FilePath $targetFile -RelativePath $relativePath -RuleCatalog $ruleCatalog -SourceLookup $sourceLookup -Config $auditConfig)
        foreach ($finding in $fileFindings) {
            $findings.Add($finding)
        }

        $comparison = "no-ootb-match"
        $referencePath = $null
        if ($ootbMap.ContainsKey($relativePath)) {
            $referencePath = $ootbMap[$relativePath]
            $comparison = if ((Get-FileHash -Algorithm SHA256 -LiteralPath $targetFile).Hash -eq (Get-FileHash -Algorithm SHA256 -LiteralPath $referencePath).Hash) {
                "matches-ootb-baseline"
            }
            else {
                "differs-from-ootb-baseline"
            }
        }
        elseif ($settings.OneImSurfaceFolders -notcontains (($relativePath -split "\\")[0])) {
            $unresolvedQuestions.Add("File '$relativePath' does not map cleanly to a known OneIM surface folder, so reference comparison is weaker.")
        }

        $fileSummaries.Add([pscustomobject]@{
                file_path = $targetFile
                relative_path = $relativePath
                detected_finding_count = @($fileFindings).Count
                detected_gating_finding_count = @(@($fileFindings) | Where-Object { $_.gating }).Count
                ootb_comparison = $comparison
                ootb_reference_path = $referencePath
            })
    }

    # -----------------------------------------------------------------------
    # Benchmark-derived performance findings (threshold overruns)
    # -----------------------------------------------------------------------
    if ($resolvedBenchmarkPath -and $resolvedThresholdsPath) {
        foreach ($bKey in $benchmarkEvidence.Keys) {
            $bResult = $benchmarkEvidence[$bKey]
            if (-not ($null -ne $bResult.PSObject.Properties["threshold_exceeded"] -and [bool]$bResult.threshold_exceeded)) {
                continue
            }

            $tKey = $bKey
            if (-not $thresholdMap.ContainsKey($tKey)) { continue }
            $threshold = $thresholdMap[$tKey]

            $details = @()
            if ($null -ne $threshold.PSObject.Properties["max_avg_ms"]) {
                $details += ("avg_ms {0} exceeds threshold {1}" -f [double]$bResult.avg_ms, [double]$threshold.max_avg_ms)
            }
            if ($null -ne $threshold.PSObject.Properties["max_p95_ms"]) {
                $details += ("p95_ms {0} exceeds threshold {1}" -f [double]$bResult.p95_ms, [double]$threshold.max_p95_ms)
            }

            $findings.Add([pscustomobject]@{
                rule_id           = "PERF-BENCH-THRESHOLD"
                title             = ("Benchmark threshold exceeded: {0}" -f [string]$bResult.name)
                category          = "performance"
                severity          = "high"
                confidence        = 100
                gating            = $false
                file_path         = ""
                relative_path     = ""
                line              = 0
                snippet           = ""
                message           = ("Benchmark '{0}' ({1}) exceeded its performance threshold. {2}" -f [string]$bResult.name, [string]$bResult.surface, ($details -join "; "))
                source_ids        = @()
                benchmark_surface = [string]$bResult.surface
                benchmark_avg_ms  = if ($null -ne $bResult.PSObject.Properties["avg_ms"]) { [double]$bResult.avg_ms } else { $null }
                benchmark_p95_ms  = if ($null -ne $bResult.PSObject.Properties["p95_ms"]) { [double]$bResult.p95_ms } else { $null }
            })
        }
    }

    # -----------------------------------------------------------------------
    # Cascade-derived CNC610 findings (write-cycle nodes from cascade report)
    # -----------------------------------------------------------------------
    if ($cascadeWriteCycleNodes.Count -gt 0 -and $ruleCatalog.ContainsKey("CNC610")) {
        $cnc610Rule = $ruleCatalog["CNC610"]
        foreach ($node in $cascadeWriteCycleNodes) {
            $findings.Add([pscustomobject]@{
                rule_id           = "CNC610"
                title             = [string]$cnc610Rule.Title
                category          = "concurrency"
                severity          = [string]$cnc610Rule.Severity
                confidence        = [int]$cnc610Rule.Confidence
                gating            = $false
                file_path         = ""
                relative_path     = ""
                line              = 0
                snippet           = ""
                message           = ("Cascade node '{0}' is part of a write-cycle SCC (id={1}, size={2}). Templates that write values inside a circular dependency may trigger cascading re-evaluations, lock contention, or inconsistent field values during provisioning." -f $node.key, $node.scc_id, $node.scc_size)
                source_ids        = @($cnc610Rule.SourceIds)
                cascade_node_key  = $node.key
                cascade_scc_id    = $node.scc_id
                cascade_scc_size  = $node.scc_size
            })
        }
    }

    # Deduplicate by rule_id + relative_path + line before post-processing.
    # Prevents the coded detector and the declarative pass from double-reporting
    # the same location when a rule appears in both engines.
    $seenFindingKeys = @{}
    $dedupedFindings = New-Object 'System.Collections.Generic.List[object]'
    foreach ($f in $findings) {
        $fKey = ("{0}|{1}|{2}" -f $f.rule_id, $f.relative_path, $f.line)
        if (-not $seenFindingKeys.ContainsKey($fKey)) {
            $seenFindingKeys[$fKey] = $true
            $dedupedFindings.Add($f)
        }
    }

    $processed = Invoke-OneImAuditPostProcessing -Findings $dedupedFindings.ToArray() -RuleCatalog $ruleCatalog
    $allFindings = @($processed.reported_findings)
    $omittedExampleSummaries = @($processed.omitted_example_summaries)
    $gatingFindings = @($allFindings | Where-Object { $_.gating })

    # -----------------------------------------------------------------------
    # Per-category risk scoring
    # -----------------------------------------------------------------------
    $filesAudited = [Math]::Max(1, @($targetFiles).Count)
    $severityWeights = $auditConfig.scoring.severity_weights
    $catThresholds   = $auditConfig.scoring.category_thresholds
    $overallThresholds = $auditConfig.scoring.overall_thresholds

    function Get-CategoryScore {
        param([string]$Category, [object[]]$Findings, [int]$FilesAudited, [hashtable]$Weights)
        $catFindings = @($Findings | Where-Object { $_.category -eq $Category })
        $h = @($catFindings | Where-Object { $_.severity -eq "high"   }).Count
        $m = @($catFindings | Where-Object { $_.severity -eq "medium" }).Count
        $l = @($catFindings | Where-Object { $_.severity -eq "low"    }).Count
        return [Math]::Round(($h * $Weights.high + $m * $Weights.medium + $l * $Weights.low) / $FilesAudited, 2)
    }

    $scoreCorrectness  = Get-CategoryScore -Category "correctness"  -Findings $allFindings -FilesAudited $filesAudited -Weights $severityWeights
    $scoreSecurity     = Get-CategoryScore -Category "security"      -Findings $allFindings -FilesAudited $filesAudited -Weights $severityWeights
    $scoreReliability  = Get-CategoryScore -Category "reliability"   -Findings $allFindings -FilesAudited $filesAudited -Weights $severityWeights
    $scorePerformance  = Get-CategoryScore -Category "performance"   -Findings $allFindings -FilesAudited $filesAudited -Weights $severityWeights
    $scoreConcurrency  = Get-CategoryScore -Category "concurrency"   -Findings $allFindings -FilesAudited $filesAudited -Weights $severityWeights
    $scoreOverall      = [Math]::Round($scoreCorrectness + $scoreSecurity + $scoreReliability + $scorePerformance + $scoreConcurrency, 2)

    $categoryScores = [ordered]@{
        correctness = [ordered]@{
            score = $scoreCorrectness
            color = Get-OneImAuditScoreColor -Score $scoreCorrectness -Thresholds $catThresholds
        }
        security = [ordered]@{
            score = $scoreSecurity
            color = Get-OneImAuditScoreColor -Score $scoreSecurity -Thresholds $catThresholds
        }
        reliability = [ordered]@{
            score = $scoreReliability
            color = Get-OneImAuditScoreColor -Score $scoreReliability -Thresholds $catThresholds
        }
        performance = [ordered]@{
            score = $scorePerformance
            color = Get-OneImAuditScoreColor -Score $scorePerformance -Thresholds $catThresholds
        }
        concurrency = [ordered]@{
            score = $scoreConcurrency
            color = Get-OneImAuditScoreColor -Score $scoreConcurrency -Thresholds $catThresholds
        }
        overall = [ordered]@{
            score = $scoreOverall
            color = Get-OneImAuditScoreColor -Score $scoreOverall -Thresholds $overallThresholds
        }
    }

    $reportedByFile = @{}
    foreach ($finding in $allFindings) {
        if (-not $reportedByFile.ContainsKey($finding.relative_path)) {
            $reportedByFile[$finding.relative_path] = [ordered]@{ count = 0; gating = 0 }
        }
        $reportedByFile[$finding.relative_path].count++
        if ($finding.gating) {
            $reportedByFile[$finding.relative_path].gating++
        }
    }

    $omittedByFile = @{}
    foreach ($summary in $omittedExampleSummaries) {
        if (-not $omittedByFile.ContainsKey($summary.relative_path)) {
            $omittedByFile[$summary.relative_path] = 0
        }
        $omittedByFile[$summary.relative_path] += [int]$summary.omitted_examples
    }

    $finalFileSummaries = New-Object 'System.Collections.Generic.List[object]'
    foreach ($fileSummary in $fileSummaries.ToArray()) {
        $reportedCount = if ($reportedByFile.ContainsKey($fileSummary.relative_path)) { [int]$reportedByFile[$fileSummary.relative_path].count } else { 0 }
        $reportedGatingCount = if ($reportedByFile.ContainsKey($fileSummary.relative_path)) { [int]$reportedByFile[$fileSummary.relative_path].gating } else { 0 }
        $omittedCount = if ($omittedByFile.ContainsKey($fileSummary.relative_path)) { [int]$omittedByFile[$fileSummary.relative_path] } else { 0 }

        $finalFileSummaries.Add([pscustomobject]@{
                file_path = $fileSummary.file_path
                relative_path = $fileSummary.relative_path
                detected_finding_count = $fileSummary.detected_finding_count
                reported_finding_count = $reportedCount
                omitted_example_count = $omittedCount
                gating_finding_count = $reportedGatingCount
                ootb_comparison = $fileSummary.ootb_comparison
                ootb_reference_path = $fileSummary.ootb_reference_path
            })
    }

    $report = [ordered]@{
        generated_at = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss K")
        oneim_version = $OneImVersion
        target_path = if (@($resolvedTargetInputs).Count -eq 1) { $resolvedTargetInputs[0] } else { $targetAuditRoot }
        selected_target_paths = @($resolvedTargetInputs)
        target_root = $targetAuditRoot
        reference_repo_path = (Get-OneImAuditFullPath -Path $ReferenceRepoPath)
        audit_config_path     = if ([string]::IsNullOrWhiteSpace($AuditConfigPath)) { $null } else { (Get-OneImAuditFullPath -Path $AuditConfigPath) }
        benchmark_report_path = $resolvedBenchmarkPath
        schema_snapshot_path  = $resolvedSchemaPath
        thresholds_file       = $resolvedThresholdsPath
        reference_validation = [ordered]@{
            mode = $layout.mode
            version_root = $layout.version_root
            primary_ootb_root = $primaryOotbRoot
            ootb_file_count = $layout.ootb_file_count
            promoted_custom_root_count = @($promotedRoots).Count
            candidate_custom_root_count = @($candidateRoots).Count
        }
        summary = [ordered]@{
            files_audited = @($targetFiles).Count
            detected_findings = [int]$processed.detected_finding_count
            reported_findings = $allFindings.Count
            omitted_examples = [int]$processed.omitted_example_count
            total_findings = $allFindings.Count
            gating_findings = $gatingFindings.Count
            correctness_findings  = @($allFindings | Where-Object { $_.category -eq "correctness" }).Count
            security_findings     = @($allFindings | Where-Object { $_.category -eq "security" }).Count
            reliability_findings  = @($allFindings | Where-Object { $_.category -eq "reliability" }).Count
            performance_findings  = @($allFindings | Where-Object { $_.category -eq "performance" }).Count
            concurrency_findings  = @($allFindings | Where-Object { $_.category -eq "concurrency" }).Count
            high_findings         = @($allFindings | Where-Object { $_.severity -eq "high" }).Count
            medium_findings       = @($allFindings | Where-Object { $_.severity -eq "medium" }).Count
            low_findings          = @($allFindings | Where-Object { $_.severity -eq "low" }).Count
        }
        files = $finalFileSummaries.ToArray()
        findings = $allFindings
        omitted_example_summaries = $omittedExampleSummaries
        unresolved_questions = @($unresolvedQuestions.ToArray() | Sort-Object -Unique)
        category_scores = $categoryScores
    }

    $jsonPath = Join-Path $runFolder "audit-report.json"
    $htmlPath = Join-Path $runFolder "audit-report.html"
    $report | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $jsonPath -Encoding UTF8
    ConvertTo-OneImAuditHtmlReport -Report $report | Set-Content -LiteralPath $htmlPath -Encoding UTF8

    Write-Host ("Audit report written to: {0}" -f $runFolder)
    Write-Host ("JSON: {0}" -f $jsonPath)
    Write-Host ("HTML: {0}" -f $htmlPath)

    if ($gatingFindings.Count -gt 0) {
        exit 1
    }

    exit 0
}
catch {
    Write-Error $_
    exit 2
}
