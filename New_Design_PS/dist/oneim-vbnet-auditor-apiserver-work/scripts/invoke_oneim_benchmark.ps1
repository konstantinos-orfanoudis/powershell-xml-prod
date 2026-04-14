<#
.SYNOPSIS
Benchmarks OneIM templates, script methods, and/or processes.

.DESCRIPTION
Connects to a live OneIM system via TestAssist and measures execution characteristics
for one or more surfaces:

  Templates     — creates a mock entity via New-OimObject with the supplied seed values
                  (which become the GetTriggerValue() inputs), reloads it to trigger
                  template evaluation, and times each call inside a rolled-back transaction.
  Script methods — invokes the method via Invoke-OimScriptMethod with supplied parameters
                  and times each call.
  Processes      — locates the process definition and times a Find-QObject lookup per call.

CSV-driven mode (recommended):
  Use -TargetsFile to point at a benchmark-integration-targets.csv file. Each row defines
  one benchmark scenario including surface, name, seed/trigger values, Variables inputs,
  and performance thresholds. Any CSV column that is not a fixed column and does not start
  with "var_" is treated as a seed value (GetTriggerValue input). Columns prefixed "var_"
  set connection variables (Variables.Get inputs). The "Value" column seeds the target
  column itself (format/check script input).

  Fixed columns: surface, name, access_mode, Value, max_avg_ms, max_p95_ms,
                 expected_outcome, notes

  Example CSV row (template, two trigger values, one Variables entry):
    surface,name,access_mode,Value,Source,UID_AADRole,var_FULLSYNC,max_avg_ms,...
    template,AADRoleAssignment.ObjectKeyAppScope,Auto,,PIM,abc-uid,,50,...

Inline mode (backward compatible):
  Supply -TemplateNames / -ScriptMethodNames / -ProcessNames directly. No seed values
  are injected; templates fall back to a schema-metadata lookup.

Output: benchmark-report.json in the output directory.

.PARAMETER TargetsFile
Path to a benchmark-integration-targets.csv. When supplied, all targets and their inputs
are read from the file. May be combined with inline name parameters.

.PARAMETER TemplateNames
One or more "Table.Column" names to benchmark (inline; no seed inputs).

.PARAMETER TemplateNamesFile
Path to a text file with one "Table.Column" entry per line (no seed inputs).

.PARAMETER ScriptMethodNames
One or more script method names to benchmark (inline; no parameters).

.PARAMETER ScriptMethodNamesFile
Path to a text file with one method name per line (no parameters).

.PARAMETER ProcessNames
One or more process names to benchmark (inline).

.PARAMETER ProcessNamesFile
Path to a text file with one process name per line.

.PARAMETER TestAssistRoot
Path to the TestAssist installation directory.

.PARAMETER ProjectConfigPath
Path to projectConfig.xml.

.PARAMETER AccessMode
Database access mode: Auto (default), Session, or Direct.

.PARAMETER WarmupCount
Number of unmeasured warm-up runs before measurement begins. Defaults to 1.

.PARAMETER MeasuredRunCount
Number of measured runs per benchmark target. Defaults to 10.

.PARAMETER OutputDir
Destination directory for the benchmark report.

.PARAMETER ThresholdsFile
Optional JSON file containing threshold definitions.

.PARAMETER SchemaSnapshotPath
Optional path to a schema-snapshot.json for column metadata enrichment.

.PARAMETER BaselineBenchmarkPath
Optional path to a previous benchmark-report.json. When supplied, each target also
present in the baseline has its avg_ms compared and regression_pct computed.
Targets where regression_pct exceeds RegressionThreshold are flagged regressed=true
and listed in the report summary regressions array.

.PARAMETER RegressionThreshold
Percentage increase in avg_ms that is considered a regression. Defaults to 20 (%).
Only used when BaselineBenchmarkPath is supplied.

.PARAMETER CollectSqlMetrics
When set, captures SQL DMV snapshots (sys.dm_exec_sessions logical_reads and
sys.dm_os_wait_stats LCK* waits) before and after the measured runs for each target.
Per-run deltas are written to each result entry as sql_logical_reads_per_run,
sql_lck_wait_count_per_run, and sql_lck_wait_ms_per_run.
Requires a live OneIM database connection via the configured AccessMode.
#>
[CmdletBinding()]
param(
    [Parameter()]
    [string]$TargetsFile,

    [Parameter()]
    [string[]]$TemplateNames = @(),

    [Parameter()]
    [string]$TemplateNamesFile,

    [Parameter()]
    [string[]]$ScriptMethodNames = @(),

    [Parameter()]
    [string]$ScriptMethodNamesFile,

    [Parameter()]
    [string[]]$ProcessNames = @(),

    [Parameter()]
    [string]$ProcessNamesFile,

    [Parameter()]
    [string]$TestAssistRoot,

    [Parameter()]
    [string]$ProjectConfigPath,

    [Parameter()]
    [ValidateSet("Auto", "Session", "Direct")]
    [string]$AccessMode = "Auto",

    [Parameter()]
    [ValidateRange(0, 100)]
    [int]$WarmupCount = 1,

    [Parameter()]
    [ValidateRange(1, 1000)]
    [int]$MeasuredRunCount = 10,

    [Parameter()]
    [string]$OutputDir,

    [Parameter()]
    [string]$ThresholdsFile,

    [Parameter()]
    [string]$SchemaSnapshotPath,

    [Parameter()]
    [string]$BaselineBenchmarkPath,

    [Parameter()]
    [ValidateRange(1, 1000)]
    [double]$RegressionThreshold = 20.0,

    [Parameter()]
    [switch]$CollectSqlMetrics
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$scriptRoot = Split-Path -Parent $PSCommandPath
$moduleRoot = Join-Path $scriptRoot "modules"

Import-Module (Join-Path $moduleRoot "OneimAudit.LiveSession.psm1") -Force

# ---------------------------------------------------------------------------
# Column names that are NOT dynamic inputs in a TargetsFile row
# ---------------------------------------------------------------------------
$fixedColumns = [System.Collections.Generic.HashSet[string]]::new(
    [System.StringComparer]::OrdinalIgnoreCase)
foreach ($c in @('surface','name','access_mode','Value',
                  'max_avg_ms','max_p95_ms','expected_outcome','notes')) {
    [void]$fixedColumns.Add($c)
}

# ---------------------------------------------------------------------------
# Target lists — each entry is an ordered dict with:
#   name        : string
#   seed_values : [ordered]@{}  — trigger inputs (column name -> value)
#                                  GetTriggerValue("X") and $X$ both map to column "X"
#   conn_vars   : [ordered]@{}  — Variables inputs (var name -> value)
#                                  Variables.Get("X") and Variables("X") both map to column "var_X"
#   has_inputs  : bool          — whether real execution (true) or fallback (false)
# ---------------------------------------------------------------------------
$allTemplates = New-Object 'System.Collections.Generic.List[object]'
$allMethods   = New-Object 'System.Collections.Generic.List[object]'
$allProcesses = New-Object 'System.Collections.Generic.List[object]'
$seenT = @{}; $seenM = @{}; $seenP = @{}

function New-TargetEntry {
    param([string]$Name, [object]$SeedValues, [object]$ConnVars)
    [ordered]@{
        name        = $Name
        seed_values = if ($SeedValues) { $SeedValues } else { [ordered]@{} }
        conn_vars   = if ($ConnVars)   { $ConnVars   } else { [ordered]@{} }
        has_inputs  = ($SeedValues -and $SeedValues.Count -gt 0)
    }
}

# ---------------------------------------------------------------------------
# Load from TargetsFile (CSV-driven mode)
# ---------------------------------------------------------------------------
if (-not [string]::IsNullOrWhiteSpace($TargetsFile)) {
    $tfPath = [System.IO.Path]::GetFullPath($TargetsFile)
    if (-not (Test-Path -LiteralPath $tfPath)) {
        throw "TargetsFile not found: '$tfPath'."
    }

    $csvRows = @(Import-Csv -LiteralPath $tfPath | Where-Object { $_.surface -ne '' })

    foreach ($row in $csvRows) {
        $seed  = [ordered]@{}
        $cvars = [ordered]@{}

        foreach ($prop in $row.PSObject.Properties) {
            if ($fixedColumns.Contains($prop.Name)) { continue }
            if ([string]::IsNullOrWhiteSpace($prop.Value)) { continue }

            if ($prop.Name -like 'var_*') {
                $cvars[$prop.Name.Substring(4)] = $prop.Value
            } else {
                $seed[$prop.Name] = $prop.Value
            }
        }

        # "Value" column seeds the target column itself (format/check script input)
        if (-not [string]::IsNullOrWhiteSpace($row.Value)) {
            $colPart = ($row.name -split '\.', 2)
            if ($colPart.Count -ge 2) {
                $seed[$colPart[1]] = $row.Value
            }
        }

        # Row-level thresholds override the ThresholdsFile for this target
        if (-not [string]::IsNullOrWhiteSpace($row.max_avg_ms) -or
            -not [string]::IsNullOrWhiteSpace($row.max_p95_ms)) {

            $tkey = ("{0}::{1}" -f $row.surface, $row.name)
            if (-not $thresholds) { $script:thresholds = @{} }
            $entry = [ordered]@{}
            if (-not [string]::IsNullOrWhiteSpace($row.max_avg_ms)) {
                $entry.max_avg_ms = [double]$row.max_avg_ms
            }
            if (-not [string]::IsNullOrWhiteSpace($row.max_p95_ms)) {
                $entry.max_p95_ms = [double]$row.max_p95_ms
            }
            $script:thresholds[$tkey] = [pscustomobject]$entry
        }

        $entry = New-TargetEntry -Name $row.name -SeedValues $seed -ConnVars $cvars

        switch ($row.surface) {
            'template'      {
                if (-not $seenT.ContainsKey($row.name)) {
                    $seenT[$row.name] = $true; $allTemplates.Add($entry)
                }
            }
            'script_method' {
                if (-not $seenM.ContainsKey($row.name)) {
                    $seenM[$row.name] = $true; $allMethods.Add($entry)
                }
            }
            'process'       {
                if (-not $seenP.ContainsKey($row.name)) {
                    $seenP[$row.name] = $true; $allProcesses.Add($entry)
                }
            }
            default { Write-Warning ("Unknown surface '{0}' in TargetsFile row for '{1}' — skipping." -f $row.surface, $row.name) }
        }
    }
}

# ---------------------------------------------------------------------------
# Load inline / file-based names (backward compatible — no seed inputs)
# ---------------------------------------------------------------------------
function Add-InlineTargets {
    param(
        [System.Collections.Generic.List[object]]$List,
        [hashtable]$Seen,
        [string[]]$Inline,
        [string]$FilePath
    )
    $names = New-Object System.Collections.Generic.List[string]
    foreach ($n in @($Inline)) {
        if (-not [string]::IsNullOrWhiteSpace($n)) { $names.Add($n.Trim()) }
    }
    if (-not [string]::IsNullOrWhiteSpace($FilePath)) {
        $fp = [System.IO.Path]::GetFullPath($FilePath)
        if (-not (Test-Path -LiteralPath $fp)) { throw "Names file not found: '$fp'." }
        foreach ($line in (Get-Content -LiteralPath $fp)) {
            if (-not [string]::IsNullOrWhiteSpace($line)) { $names.Add($line.Trim()) }
        }
    }
    foreach ($n in $names) {
        if (-not $Seen.ContainsKey($n)) {
            $Seen[$n] = $true
            $List.Add((New-TargetEntry -Name $n -SeedValues $null -ConnVars $null))
        }
    }
}

Add-InlineTargets -List $allTemplates -Seen $seenT -Inline $TemplateNames    -FilePath $TemplateNamesFile
Add-InlineTargets -List $allMethods   -Seen $seenM -Inline $ScriptMethodNames -FilePath $ScriptMethodNamesFile
Add-InlineTargets -List $allProcesses -Seen $seenP -Inline $ProcessNames      -FilePath $ProcessNamesFile

if ($allTemplates.Count -eq 0 -and $allMethods.Count -eq 0 -and $allProcesses.Count -eq 0) {
    Write-Error "No targets found. Supply -TargetsFile, -TemplateNames, -ScriptMethodNames, or -ProcessNames."
    exit 1
}

# ---------------------------------------------------------------------------
# Resolve settings and session
# ---------------------------------------------------------------------------
$settings = Get-OneImAuditSessionSettings `
    -TestAssistRoot    $TestAssistRoot `
    -ProjectConfigPath $ProjectConfigPath

Write-Host "Bootstrapping TestAssist session..."
$session = Ensure-OneImAuditSession -Settings $settings -ProjectConfigPath $settings.ProjectConfigPath

# ---------------------------------------------------------------------------
# Detect BenchmarkDotNet
# ---------------------------------------------------------------------------
$bdnPath = Join-Path $settings.TestAssistRoot "BenchmarkDotNet.dll"
$useBdN  = Test-Path -LiteralPath $bdnPath

$backendName = if ($useBdN) {
    Add-Type -Path $bdnPath -ErrorAction SilentlyContinue
    "BenchmarkDotNet"
} else {
    "BuiltinSampler"
}

Write-Host ("Measurement backend: {0}" -f $backendName)

# ---------------------------------------------------------------------------
# Resolve schema snapshot
# ---------------------------------------------------------------------------
$resolvedSchemaPath = $null

if (-not [string]::IsNullOrWhiteSpace($SchemaSnapshotPath)) {
    $resolvedSchemaPath = [System.IO.Path]::GetFullPath($SchemaSnapshotPath)
    if (-not (Test-Path -LiteralPath $resolvedSchemaPath)) {
        Write-Warning ("Schema snapshot not found at '{0}'. Proceeding without column metadata." -f $resolvedSchemaPath)
        $resolvedSchemaPath = $null
    }
}

if (-not $resolvedSchemaPath) {
    $schemaSearchRoot = Join-Path (Get-Location).Path "output\oneim-schema"
    if (Test-Path -LiteralPath $schemaSearchRoot) {
        $candidate = Get-ChildItem -Path $schemaSearchRoot -Filter "schema-snapshot.json" -Recurse |
            Sort-Object LastWriteTime -Descending |
            Select-Object -First 1
        if ($candidate) {
            $resolvedSchemaPath = $candidate.FullName
            Write-Host ("Using schema snapshot: {0}" -f $resolvedSchemaPath)
        }
    }
}

$schemaSnapshot = $null
if ($resolvedSchemaPath) {
    $schemaSnapshot = Get-Content -LiteralPath $resolvedSchemaPath -Raw | ConvertFrom-Json
}

# ---------------------------------------------------------------------------
# Load thresholds from file (row-level thresholds already injected above)
# ---------------------------------------------------------------------------
$thresholds = @{}
if (-not [string]::IsNullOrWhiteSpace($ThresholdsFile)) {
    $threshFullPath = [System.IO.Path]::GetFullPath($ThresholdsFile)
    if (-not (Test-Path -LiteralPath $threshFullPath)) {
        throw "Thresholds file not found: '$threshFullPath'."
    }
    $threshRaw = Get-Content -LiteralPath $threshFullPath -Raw | ConvertFrom-Json
    foreach ($t in @($threshRaw)) {
        $key = ("{0}::{1}" -f [string]$t.surface, [string]$t.name)
        $thresholds[$key] = $t
    }
}

# ---------------------------------------------------------------------------
# Load baseline for regression comparison
# ---------------------------------------------------------------------------
# $baselineIndex: hashtable keyed "surface::name" -> baseline result object
$baselineIndex = @{}
if (-not [string]::IsNullOrWhiteSpace($BaselineBenchmarkPath)) {
    $blFullPath = [System.IO.Path]::GetFullPath($BaselineBenchmarkPath)
    if (-not (Test-Path -LiteralPath $blFullPath)) {
        throw "BaselineBenchmarkPath not found: '$blFullPath'."
    }
    $blReport = Get-Content -LiteralPath $blFullPath -Raw | ConvertFrom-Json
    foreach ($r in @($blReport.results)) {
        if ($null -ne $r.avg_ms -and -not $r.error) {
            $blKey = ("{0}::{1}" -f [string]$r.surface, [string]$r.name)
            $baselineIndex[$blKey] = $r
        }
    }
    Write-Host ("Baseline loaded: {0} entries from '{1}'" -f $baselineIndex.Count, $blFullPath)
}

function Get-RegressionResult {
    param([string]$Surface, [string]$Name, [double]$CurrentAvgMs)
    $key = ("{0}::{1}" -f $Surface, $Name)
    if (-not $baselineIndex.ContainsKey($key)) {
        return [pscustomobject]@{
            has_baseline    = $false
            baseline_avg_ms = $null
            regression_pct  = $null
            regressed       = $false
        }
    }
    $baselineAvg  = [double]$baselineIndex[$key].avg_ms
    $regressionPct = if ($baselineAvg -gt 0) {
        [Math]::Round(($CurrentAvgMs - $baselineAvg) / $baselineAvg * 100, 1)
    } else { 0.0 }
    return [pscustomobject]@{
        has_baseline    = $true
        baseline_avg_ms = [Math]::Round($baselineAvg, 3)
        regression_pct  = $regressionPct
        regressed       = $regressionPct -gt $RegressionThreshold
    }
}

# ---------------------------------------------------------------------------
# Built-in sampler
# ---------------------------------------------------------------------------
function Invoke-BuiltinSampler {
    param([scriptblock]$ScriptBlock, [int]$Warmups, [int]$Runs)

    for ($i = 0; $i -lt $Warmups; $i++) { try { & $ScriptBlock | Out-Null } catch { } }

    $samples = New-Object System.Collections.Generic.List[pscustomobject]
    for ($i = 0; $i -lt $Runs; $i++) {
        $memBefore     = [System.GC]::GetTotalMemory($false)
        $gcBefore0     = [System.GC]::CollectionCount(0)
        $gcBefore1     = [System.GC]::CollectionCount(1)
        $gcBefore2     = [System.GC]::CollectionCount(2)
        $proc          = [System.Diagnostics.Process]::GetCurrentProcess()
        $cpuBefore     = $proc.TotalProcessorTime.TotalMilliseconds
        $threadsBefore = $proc.Threads.Count

        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        try { & $ScriptBlock | Out-Null } catch { }
        $sw.Stop()

        $proc.Refresh()
        $samples.Add([pscustomobject]@{
            elapsed_ms         = [Math]::Round($sw.Elapsed.TotalMilliseconds, 3)
            memory_delta_bytes = [System.GC]::GetTotalMemory($false) - $memBefore
            cpu_delta_ms       = [Math]::Round($proc.TotalProcessorTime.TotalMilliseconds - $cpuBefore, 3)
            gc_gen0_delta      = [System.GC]::CollectionCount(0) - $gcBefore0
            gc_gen1_delta      = [System.GC]::CollectionCount(1) - $gcBefore1
            gc_gen2_delta      = [System.GC]::CollectionCount(2) - $gcBefore2
            thread_delta       = $proc.Threads.Count - $threadsBefore
        })
    }
    return $samples.ToArray()
}

function Get-SampleStats {
    param([object[]]$Samples)
    $elapsed = @($Samples | ForEach-Object { $_.elapsed_ms })
    $count   = $elapsed.Count
    if ($count -eq 0) {
        return [pscustomobject]@{
            avg_ms = 0; stddev_ms = 0; min_ms = 0; max_ms = 0
            p50_ms = 0; p75_ms = 0; p95_ms = 0; p99_ms = 0
            cv_pct = 0; stability = "stable"; warmup_effect_ratio = 1.0
            avg_mem_bytes = 0; min_mem_bytes = 0; max_mem_bytes = 0
            avg_cpu_ms = 0; min_cpu_ms = 0; max_cpu_ms = 0
            total_gc_gen0 = 0; total_gc_gen1 = 0; total_gc_gen2 = 0
            max_thread_delta = 0
        }
    }

    $avg      = ($elapsed | Measure-Object -Average).Average
    $min      = ($elapsed | Measure-Object -Minimum).Minimum
    $max      = ($elapsed | Measure-Object -Maximum).Maximum
    $variance = ($elapsed | ForEach-Object { [Math]::Pow($_ - $avg, 2) } | Measure-Object -Average).Average
    $stddev   = [Math]::Sqrt($variance)

    $sorted = @($elapsed | Sort-Object)
    function Get-Percentile([double]$pct) {
        $idx = [Math]::Ceiling($count * $pct) - 1
        if ($idx -lt 0)      { $idx = 0 }
        if ($idx -ge $count) { $idx = $count - 1 }
        return $sorted[$idx]
    }

    $cv_pct    = if ($avg -gt 0) { [Math]::Round($stddev / $avg * 100, 1) } else { 0 }
    $stability = if ($cv_pct -lt 10) { "stable" } elseif ($cv_pct -le 30) { "variable" } else { "unstable" }
    $warmupR   = if ($avg -gt 0) { [Math]::Round($elapsed[0] / $avg, 3) } else { 1.0 }

    $memVals    = @($Samples | ForEach-Object { $_.memory_delta_bytes })
    $cpuVals    = @($Samples | ForEach-Object { $_.cpu_delta_ms })
    $gc0Vals    = @($Samples | ForEach-Object { if ($_.PSObject.Properties.Name -contains 'gc_gen0_delta') { $_.gc_gen0_delta } else { 0 } })
    $gc1Vals    = @($Samples | ForEach-Object { if ($_.PSObject.Properties.Name -contains 'gc_gen1_delta') { $_.gc_gen1_delta } else { 0 } })
    $gc2Vals    = @($Samples | ForEach-Object { if ($_.PSObject.Properties.Name -contains 'gc_gen2_delta') { $_.gc_gen2_delta } else { 0 } })
    $thVals     = @($Samples | ForEach-Object { if ($_.PSObject.Properties.Name -contains 'thread_delta')  { $_.thread_delta  } else { 0 } })

    return [pscustomobject]@{
        avg_ms              = [Math]::Round($avg,    3)
        stddev_ms           = [Math]::Round($stddev, 3)
        min_ms              = [Math]::Round($min,    3)
        max_ms              = [Math]::Round($max,    3)
        p50_ms              = [Math]::Round((Get-Percentile 0.50), 3)
        p75_ms              = [Math]::Round((Get-Percentile 0.75), 3)
        p95_ms              = [Math]::Round((Get-Percentile 0.95), 3)
        p99_ms              = [Math]::Round((Get-Percentile 0.99), 3)
        cv_pct              = $cv_pct
        stability           = $stability
        warmup_effect_ratio = $warmupR
        avg_mem_bytes       = [long][Math]::Round(($memVals | Measure-Object -Average).Average, 0)
        min_mem_bytes       = [long]($memVals | Measure-Object -Minimum).Minimum
        max_mem_bytes       = [long]($memVals | Measure-Object -Maximum).Maximum
        avg_cpu_ms          = [Math]::Round(($cpuVals | Measure-Object -Average).Average, 3)
        min_cpu_ms          = [Math]::Round(($cpuVals | Measure-Object -Minimum).Minimum, 3)
        max_cpu_ms          = [Math]::Round(($cpuVals | Measure-Object -Maximum).Maximum, 3)
        total_gc_gen0       = ($gc0Vals | Measure-Object -Sum).Sum
        total_gc_gen1       = ($gc1Vals | Measure-Object -Sum).Sum
        total_gc_gen2       = ($gc2Vals | Measure-Object -Sum).Sum
        max_thread_delta    = ($thVals  | Measure-Object -Maximum).Maximum
    }
}

function Get-ThresholdResult {
    param([string]$Surface, [string]$Name, [object]$Stats)
    $key = ("{0}::{1}" -f $Surface, $Name)
    if (-not $thresholds.ContainsKey($key)) {
        return [pscustomobject]@{ exceeded = $false; details = $null }
    }
    $t = $thresholds[$key]
    $exceeded = $false; $details = @()
    if ($t.PSObject.Properties.Name.Contains("max_avg_ms") -and $Stats.avg_ms -gt [double]$t.max_avg_ms) {
        $exceeded = $true
        $details += ("avg_ms {0} > threshold {1}" -f $Stats.avg_ms, $t.max_avg_ms)
    }
    if ($t.PSObject.Properties.Name.Contains("max_p95_ms") -and $Stats.p95_ms -gt [double]$t.max_p95_ms) {
        $exceeded = $true
        $details += ("p95_ms {0} > threshold {1}" -f $Stats.p95_ms, $t.max_p95_ms)
    }
    return [pscustomobject]@{ exceeded = $exceeded; details = ($details -join "; ") }
}

# ---------------------------------------------------------------------------
# Helper: apply / remove connection variables around a script block
# ---------------------------------------------------------------------------
function Invoke-WithConnVars {
    param([hashtable]$ConnVars, [scriptblock]$Body)
    foreach ($kv in $ConnVars.GetEnumerator()) {
        Add-OimConnectionVariable -ConnVar @{ $kv.Key = $kv.Value }
    }
    try   { & $Body }
    finally {
        foreach ($kv in $ConnVars.GetEnumerator()) {
            Remove-OimConnectionVariable -ConnVar $kv.Key
        }
    }
}

# ---------------------------------------------------------------------------
# Helper: build the standard stats result ordered dict
# ---------------------------------------------------------------------------
function Build-ResultEntry {
    param([string]$Name, [string]$Surface, [object]$Stats, [object]$Thresh,
          [object]$Samples, [hashtable]$Extra)
    $regression = Get-RegressionResult -Surface $Surface -Name $Name -CurrentAvgMs $Stats.avg_ms
    $entry = [ordered]@{
        name                = $Name
        surface             = $Surface
        warmup_count        = $WarmupCount
        measured_run_count  = $MeasuredRunCount
        backend             = $backendName
        avg_ms              = $Stats.avg_ms
        stddev_ms           = $Stats.stddev_ms
        min_ms              = $Stats.min_ms
        max_ms              = $Stats.max_ms
        p50_ms              = $Stats.p50_ms
        p75_ms              = $Stats.p75_ms
        p95_ms              = $Stats.p95_ms
        p99_ms              = $Stats.p99_ms
        cv_pct              = $Stats.cv_pct
        stability           = $Stats.stability
        warmup_effect_ratio = $Stats.warmup_effect_ratio
        avg_mem_bytes       = $Stats.avg_mem_bytes
        min_mem_bytes       = $Stats.min_mem_bytes
        max_mem_bytes       = $Stats.max_mem_bytes
        avg_cpu_ms          = $Stats.avg_cpu_ms
        min_cpu_ms          = $Stats.min_cpu_ms
        max_cpu_ms          = $Stats.max_cpu_ms
        total_gc_gen0       = $Stats.total_gc_gen0
        total_gc_gen1       = $Stats.total_gc_gen1
        total_gc_gen2       = $Stats.total_gc_gen2
        max_thread_delta    = $Stats.max_thread_delta
        raw_samples         = @($Samples)
        threshold_exceeded  = $Thresh.exceeded
        threshold_details   = $Thresh.details
        baseline_avg_ms     = $regression.baseline_avg_ms
        regression_pct      = $regression.regression_pct
        regressed           = $regression.regressed
        error               = $null
    }
    foreach ($kv in $Extra.GetEnumerator()) { $entry[$kv.Key] = $kv.Value }
    return $entry
}

# ---------------------------------------------------------------------------
# Benchmark: Templates
# ---------------------------------------------------------------------------
$templateResults = New-Object System.Collections.Generic.List[object]

foreach ($target in $allTemplates) {
    $templateName = $target.name
    $seedValues   = $target.seed_values   # [ordered]@{ColumnName->value,...}
    $connVars     = $target.conn_vars     # [ordered]@{VarName->value,...}
    $hasInputs    = $target.has_inputs

    Write-Host ("Benchmarking template: {0}{1}" -f $templateName,
        $(if ($hasInputs) { " [with seed inputs]" } else { " [schema lookup]" }))

    $parts      = $templateName -split '\.', 2
    $tableName  = $parts[0]
    $columnName = if ($parts.Count -ge 2) { $parts[1] } else { "" }

    $columnUid   = $null
    $hasTemplate = $false
    if ($schemaSnapshot -and $tableName -and $columnName) {
        $matchingCol = @($schemaSnapshot.columns | Where-Object {
            [string]$_.table_name -eq $tableName -and [string]$_.column_name -eq $columnName
        })
        if ($matchingCol.Count -gt 0) {
            $columnUid   = [string]$matchingCol[0].column_uid
            $hasTemplate = [bool]$matchingCol[0].has_template
        }
    }

    try {
        if ($hasInputs) {
            # --- Real execution: create mock entity, reload triggers template evaluation ---
            $capturedTable  = $tableName
            $capturedSeed   = $seedValues
            $capturedCVars  = $connVars

            $benchBlock = {
                Invoke-WithConnVars -ConnVars $using:capturedCVars -Body {
                    Invoke-OimRolledbackTransaction {
                        $obj = New-OimObject -TableName $using:capturedTable -Values $using:capturedSeed
                        $null = $obj | Reload-OimObject
                    }
                }
            }
        } else {
            # --- Fallback: schema metadata lookup (no seed values supplied) ---
            $capturedTable  = $tableName
            $capturedCol    = $columnName

            if ($columnName -eq "") { throw ("Template name '{0}' must be 'Table.Column' format." -f $templateName) }

            $benchBlock = {
                $null = Find-QSql -Dictionary -Query (
                    "SELECT Template FROM DialogColumn WHERE ColumnName = '{0}'" +
                    " AND UID_DialogTable IN (SELECT UID_DialogTable FROM DialogTable WHERE TableName = '{1}')" -f
                    $using:capturedCol, $using:capturedTable)
            }
        }

        $dmvBefore = if ($CollectSqlMetrics) {
            Get-OneImAuditDmvSnapshot -AccessMode $AccessMode -ProjectConfigPath $settings.ProjectConfigPath
        } else { $null }
        $samples = Invoke-BuiltinSampler -ScriptBlock $benchBlock -Warmups $WarmupCount -Runs $MeasuredRunCount
        $dmvAfter = if ($CollectSqlMetrics) {
            Get-OneImAuditDmvSnapshot -AccessMode $AccessMode -ProjectConfigPath $settings.ProjectConfigPath
        } else { $null }
        $dmvMetrics = if ($CollectSqlMetrics -and $dmvBefore -and $dmvAfter) {
            Get-OneImAuditDmvDelta -Before $dmvBefore -After $dmvAfter -RunCount $MeasuredRunCount
        } else { $null }

        $stats   = Get-SampleStats -Samples $samples
        $thresh  = Get-ThresholdResult -Surface "template" -Name $templateName -Stats $stats

        $extra = [ordered]@{
            table_name   = $tableName
            column_name  = $columnName
            column_uid   = $columnUid
            has_template = $hasTemplate
            seed_inputs  = if ($hasInputs) { $seedValues } else { $null }
            execution_mode = if ($hasInputs) { "mock_entity" } else { "schema_lookup" }
            sql_logical_reads_per_run  = if ($dmvMetrics) { $dmvMetrics.logical_reads_per_run  } else { $null }
            sql_lck_wait_count_per_run = if ($dmvMetrics) { $dmvMetrics.lck_wait_count_per_run } else { $null }
            sql_lck_wait_ms_per_run    = if ($dmvMetrics) { $dmvMetrics.lck_wait_ms_per_run    } else { $null }
        }
        $templateResults.Add((Build-ResultEntry -Name $templateName -Surface "template" `
            -Stats $stats -Thresh $thresh -Samples $samples -Extra $extra))
    }
    catch {
        $errMsg = $_.Exception.Message
        Write-Warning ("Template benchmark '{0}' failed: {1}" -f $templateName, $errMsg)
        $templateResults.Add([ordered]@{
            name = $templateName; surface = "template"
            seed_inputs = if ($hasInputs) { $seedValues } else { $null }
            execution_mode = if ($hasInputs) { "mock_entity" } else { "schema_lookup" }
            threshold_exceeded = $false; error = $errMsg
        })
    }
}

# ---------------------------------------------------------------------------
# Benchmark: Script Methods
# ---------------------------------------------------------------------------
$methodResults = New-Object System.Collections.Generic.List[object]

foreach ($target in $allMethods) {
    $methodName  = $target.name
    $seedValues  = $target.seed_values
    $connVars    = $target.conn_vars
    $hasInputs   = $target.has_inputs

    Write-Host ("Benchmarking script method: {0}{1}" -f $methodName,
        $(if ($hasInputs) { " [with parameters]" } else { " [object lookup]" }))

    try {
        if ($hasInputs) {
            # --- Real execution: invoke the method with supplied parameters ---
            # Parameters are the values from seed_values in CSV column order.
            $capturedMethod  = $methodName
            $capturedParams  = @($seedValues.Values)
            $capturedCVars   = $connVars

            $benchBlock = {
                Invoke-WithConnVars -ConnVars $using:capturedCVars -Body {
                    $null = Invoke-OimScriptMethod `
                        -MethodName       $using:capturedMethod `
                        -MethodParameters $using:capturedParams
                }
            }
        } else {
            # --- Fallback: object lookup (no parameters supplied) ---
            $capturedMethod = $methodName

            $benchBlock = {
                $null = Find-QObject -Type "DialogScriptMethod" `
                    -Properties @{ MethodName = $using:capturedMethod } `
                    -ErrorAction SilentlyContinue
            }
        }

        $dmvBefore = if ($CollectSqlMetrics) {
            Get-OneImAuditDmvSnapshot -AccessMode $AccessMode -ProjectConfigPath $settings.ProjectConfigPath
        } else { $null }
        $samples = Invoke-BuiltinSampler -ScriptBlock $benchBlock -Warmups $WarmupCount -Runs $MeasuredRunCount
        $dmvAfter = if ($CollectSqlMetrics) {
            Get-OneImAuditDmvSnapshot -AccessMode $AccessMode -ProjectConfigPath $settings.ProjectConfigPath
        } else { $null }
        $dmvMetrics = if ($CollectSqlMetrics -and $dmvBefore -and $dmvAfter) {
            Get-OneImAuditDmvDelta -Before $dmvBefore -After $dmvAfter -RunCount $MeasuredRunCount
        } else { $null }

        $stats   = Get-SampleStats -Samples $samples
        $thresh  = Get-ThresholdResult -Surface "script_method" -Name $methodName -Stats $stats

        $extra = [ordered]@{
            method_parameters = if ($hasInputs) { @($seedValues.Values) } else { $null }
            execution_mode    = if ($hasInputs) { "invoke" } else { "object_lookup" }
            sql_logical_reads_per_run  = if ($dmvMetrics) { $dmvMetrics.logical_reads_per_run  } else { $null }
            sql_lck_wait_count_per_run = if ($dmvMetrics) { $dmvMetrics.lck_wait_count_per_run } else { $null }
            sql_lck_wait_ms_per_run    = if ($dmvMetrics) { $dmvMetrics.lck_wait_ms_per_run    } else { $null }
        }
        $methodResults.Add((Build-ResultEntry -Name $methodName -Surface "script_method" `
            -Stats $stats -Thresh $thresh -Samples $samples -Extra $extra))
    }
    catch {
        $errMsg = $_.Exception.Message
        Write-Warning ("Script method benchmark '{0}' failed: {1}" -f $methodName, $errMsg)
        $methodResults.Add([ordered]@{
            name = $methodName; surface = "script_method"
            method_parameters = if ($hasInputs) { @($seedValues.Values) } else { $null }
            execution_mode    = if ($hasInputs) { "invoke" } else { "object_lookup" }
            threshold_exceeded = $false; error = $errMsg
        })
    }
}

# ---------------------------------------------------------------------------
# Benchmark: Processes
# ---------------------------------------------------------------------------
$processResults = New-Object System.Collections.Generic.List[object]

foreach ($target in $allProcesses) {
    $processName = $target.name
    $connVars    = $target.conn_vars

    Write-Host ("Benchmarking process: {0}" -f $processName)

    try {
        $capturedProcess = $processName
        $capturedCVars   = $connVars

        $benchBlock = {
            Invoke-WithConnVars -ConnVars $using:capturedCVars -Body {
                $null = Find-QObject -Type "JobEventGen" `
                    -Properties @{ EventName = $using:capturedProcess } `
                    -ErrorAction SilentlyContinue
            }
        }

        $dmvBefore = if ($CollectSqlMetrics) {
            Get-OneImAuditDmvSnapshot -AccessMode $AccessMode -ProjectConfigPath $settings.ProjectConfigPath
        } else { $null }
        $samples = Invoke-BuiltinSampler -ScriptBlock $benchBlock -Warmups $WarmupCount -Runs $MeasuredRunCount
        $dmvAfter = if ($CollectSqlMetrics) {
            Get-OneImAuditDmvSnapshot -AccessMode $AccessMode -ProjectConfigPath $settings.ProjectConfigPath
        } else { $null }
        $dmvMetrics = if ($CollectSqlMetrics -and $dmvBefore -and $dmvAfter) {
            Get-OneImAuditDmvDelta -Before $dmvBefore -After $dmvAfter -RunCount $MeasuredRunCount
        } else { $null }

        $stats   = Get-SampleStats -Samples $samples
        $thresh  = Get-ThresholdResult -Surface "process" -Name $processName -Stats $stats

        $processResults.Add((Build-ResultEntry -Name $processName -Surface "process" `
            -Stats $stats -Thresh $thresh -Samples $samples -Extra @{
                sql_logical_reads_per_run  = if ($dmvMetrics) { $dmvMetrics.logical_reads_per_run  } else { $null }
                sql_lck_wait_count_per_run = if ($dmvMetrics) { $dmvMetrics.lck_wait_count_per_run } else { $null }
                sql_lck_wait_ms_per_run    = if ($dmvMetrics) { $dmvMetrics.lck_wait_ms_per_run    } else { $null }
            }))
    }
    catch {
        $errMsg = $_.Exception.Message
        Write-Warning ("Process benchmark '{0}' failed: {1}" -f $processName, $errMsg)
        $processResults.Add([ordered]@{
            name = $processName; surface = "process"
            threshold_exceeded = $false; error = $errMsg
        })
    }
}

# ---------------------------------------------------------------------------
# Write output
# ---------------------------------------------------------------------------
$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$resolvedOutputDir = if (-not [string]::IsNullOrWhiteSpace($OutputDir)) {
    [System.IO.Path]::GetFullPath($OutputDir)
} else {
    Join-Path (Get-Location).Path "output\oneim-benchmark\$timestamp"
}

if (-not (Test-Path -LiteralPath $resolvedOutputDir)) {
    $null = New-Item -ItemType Directory -Path $resolvedOutputDir -Force
}

$allResultsRaw  = @($templateResults.ToArray()) + @($methodResults.ToArray()) + @($processResults.ToArray())
$successResults = @($allResultsRaw | Where-Object { -not $_.error } | Sort-Object { [double]$_.avg_ms } -Descending)
$errorResults   = @($allResultsRaw | Where-Object { $_.error })
$allResults     = $successResults + $errorResults

$report = [ordered]@{
    report_metadata = [ordered]@{
        generated_at         = (Get-Date -Format "o")
        backend              = $backendName
        warmup_count         = $WarmupCount
        measured_run_count   = $MeasuredRunCount
        access_mode          = $AccessMode
        project_config_path  = $settings.ProjectConfigPath
        schema_snapshot_path = if ($resolvedSchemaPath) { $resolvedSchemaPath } else { $null }
        targets_file         = if (-not [string]::IsNullOrWhiteSpace($TargetsFile)) { [System.IO.Path]::GetFullPath($TargetsFile) } else { $null }
        thresholds_file      = if (-not [string]::IsNullOrWhiteSpace($ThresholdsFile)) { [System.IO.Path]::GetFullPath($ThresholdsFile) } else { $null }
        sql_metrics_collected = $CollectSqlMetrics.IsPresent
    }
    summary = [ordered]@{
        total_benchmarks   = $allResults.Count
        total_errors       = $errorResults.Count
        threshold_failures = @($allResults | Where-Object { $_.threshold_exceeded -eq $true }).Count
        regressions        = @($allResults | Where-Object { $_.regressed -eq $true } |
                               ForEach-Object {
                                   [ordered]@{
                                       name           = $_.name
                                       surface        = $_.surface
                                       avg_ms         = $_.avg_ms
                                       baseline_avg_ms = $_.baseline_avg_ms
                                       regression_pct = $_.regression_pct
                                   }
                               })
    }
    results = $allResults
}

$reportPath = Join-Path $resolvedOutputDir "benchmark-report.json"
$report | ConvertTo-Json -Depth 15 | Set-Content -LiteralPath $reportPath -Encoding UTF8

# ---------------------------------------------------------------------------
# Console summary
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host ("Benchmark report written to: {0}" -f $reportPath)
$regressionCount = $report.summary.regressions.Count
Write-Host ("  Benchmarks : {0}  |  Errors : {1}  |  Threshold failures : {2}  |  Regressions : {3}" -f `
    $report.summary.total_benchmarks, $report.summary.total_errors,
    $report.summary.threshold_failures, $regressionCount)
Write-Host ""

if ($successResults.Count -gt 0) {
    $colW = @{ name=40; surface=13; avg=9; p95=9; cv=7; stab=10; mem=12; gc2=6; mode=14 }
    $hdr  = ("  {0,-$($colW.name)} {1,-$($colW.surface)} {2,$($colW.avg)} {3,$($colW.p95)} {4,$($colW.cv)} {5,-$($colW.stab)} {6,$($colW.mem)} {7,$($colW.gc2)} {8,-$($colW.mode)}" -f `
        "Name", "Surface", "avg_ms", "p95_ms", "cv%", "stability", "avg_mem_KB", "gc2", "exec_mode")
    $sep  = "  " + ("-" * ($hdr.Length - 2))
    Write-Host $hdr
    Write-Host $sep
    $rank = 1
    foreach ($r in $successResults) {
        $marker      = if ($rank -eq 1) { "* " } else { "  " }
        $memKB       = [Math]::Round($r.avg_mem_bytes / 1KB, 1)
        $displayName = if ($r.name.Length -gt $colW.name) { $r.name.Substring(0, $colW.name) } else { $r.name }
        $gc2         = if ($null -ne $r.total_gc_gen2) { $r.total_gc_gen2 } else { "-" }
        $mode        = if ($r.execution_mode) { $r.execution_mode } else { "-" }
        $line        = ("{0}{1,-$($colW.name)} {2,-$($colW.surface)} {3,$($colW.avg)} {4,$($colW.p95)} {5,$($colW.cv)} {6,-$($colW.stab)} {7,$($colW.mem)} {8,$($colW.gc2)} {9,-$($colW.mode)}" -f `
            $marker, $displayName, $r.surface,
            $r.avg_ms, $r.p95_ms, $r.cv_pct, $r.stability, $memKB, $gc2, $mode)
        $flag = if ($r.threshold_exceeded) { " [THRESHOLD]" } else { "" }
        Write-Host ($line + $flag)
        $rank++
    }
    Write-Host $sep
    Write-Host "  * = bottleneck   cv% = coefficient of variation   gc2 = Gen2 GC collections"
    Write-Host "  exec_mode: mock_entity = real template eval with mocked inputs | schema_lookup = metadata only"
}

if ($errorResults.Count -gt 0) {
    Write-Host ""
    Write-Host "  Errors:"
    foreach ($r in $errorResults) {
        Write-Host ("    [{0}] {1}: {2}" -f $r.surface, $r.name, $r.error)
    }
}

if ($regressionCount -gt 0) {
    Write-Host ""
    Write-Host ("  Regressions (threshold: +{0}%):" -f $RegressionThreshold)
    foreach ($reg in $report.summary.regressions) {
        Write-Host ("    [{0}] {1}: {2}ms vs baseline {3}ms (+{4}%)" -f `
            $reg.surface, $reg.name, $reg.avg_ms, $reg.baseline_avg_ms, $reg.regression_pct)
    }
}
exit 0
