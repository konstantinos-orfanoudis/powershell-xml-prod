#Requires -Version 7
$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$skillRoot       = Split-Path -Parent $PSScriptRoot
$scriptRoot      = Join-Path $skillRoot "scripts"
$benchmarkScript = Join-Path $scriptRoot "invoke_oneim_benchmark.ps1"
$moduleRoot      = Join-Path $scriptRoot "modules"
$fixturesDir     = Join-Path $PSScriptRoot "fixtures"
$csvPath         = Join-Path $fixturesDir "benchmark-stats-cases.csv"

Import-Module (Join-Path $moduleRoot "OneimAudit.LiveSession.psm1") -Force

# ---------------------------------------------------------------------------
# Load Get-SampleStats and Get-ThresholdResult from the production script via
# the PS AST. No live DB connection is required.
# ---------------------------------------------------------------------------
$ast = [System.Management.Automation.Language.Parser]::ParseFile(
    $benchmarkScript, [ref]$null, [ref]$null)

$funcDefs = $ast.FindAll(
    { $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)

$loadedFunctions = @{}
foreach ($func in $funcDefs) {
    if ($func.Name -in @('Get-SampleStats', 'Get-ThresholdResult', 'Get-RegressionResult')) {
        . ([scriptblock]::Create($func.Extent.Text))
        $loadedFunctions[$func.Name] = $true
    }
}

foreach ($name in @('Get-SampleStats', 'Get-ThresholdResult', 'Get-RegressionResult')) {
    if (-not $loadedFunctions.ContainsKey($name)) {
        throw "'$name' was not found in '$benchmarkScript'. Ensure the function is defined at script scope."
    }
}

# ---------------------------------------------------------------------------
# Helper: parse the compact sample encoding used in benchmark-stats-cases.csv
#
# Formats:
#   ""                              → @() (empty input)
#   "REPEAT:elapsed:count"          → count samples each with elapsed_ms=elapsed, all others 0
#   "RANGE:start:end:step"          → samples elapsed from start to end (inclusive) by step
#   "legacy:e|m|c;e|m|c"           → PSCustomObjects with only elapsed_ms/memory_delta_bytes/cpu_delta_ms
#   "e|m|c|g0|g1|g2|t;..."         → full sample objects (7 pipe-separated fields per sample)
# ---------------------------------------------------------------------------
function ConvertTo-SamplesFromRow {
    param([string]$SamplesStr)

    if ([string]::IsNullOrEmpty($SamplesStr)) { return @() }

    # REPEAT shorthand: REPEAT:elapsed:count
    if ($SamplesStr -match '^REPEAT:([^:]+):(\d+)$') {
        $elapsed = [double]$Matches[1]
        $count   = [int]$Matches[2]
        return @(1..$count | ForEach-Object {
            [pscustomobject]@{
                elapsed_ms = $elapsed; memory_delta_bytes = 0L; cpu_delta_ms = 0.0
                gc_gen0_delta = 0; gc_gen1_delta = 0; gc_gen2_delta = 0; thread_delta = 0
            }
        })
    }

    # RANGE shorthand: RANGE:start:end:step
    if ($SamplesStr -match '^RANGE:([^:]+):([^:]+):([^:]+)$') {
        $start = [double]$Matches[1]
        $end   = [double]$Matches[2]
        $step  = [double]$Matches[3]
        $out   = New-Object System.Collections.Generic.List[object]
        $v = $start
        while ($v -le $end + 1e-9) {
            $out.Add([pscustomobject]@{
                elapsed_ms = $v; memory_delta_bytes = 0L; cpu_delta_ms = 0.0
                gc_gen0_delta = 0; gc_gen1_delta = 0; gc_gen2_delta = 0; thread_delta = 0
            })
            $v = [Math]::Round($v + $step, 10)
        }
        return $out.ToArray()
    }

    # Legacy shape (no gc/thread fields)
    $isLegacy = $SamplesStr.StartsWith("legacy:")
    $raw      = if ($isLegacy) { $SamplesStr.Substring(7) } else { $SamplesStr }

    return @($raw -split ';' | ForEach-Object {
        $parts = $_ -split '\|'
        if ($isLegacy) {
            [pscustomobject]@{
                elapsed_ms         = [double]$parts[0]
                memory_delta_bytes = [long]$parts[1]
                cpu_delta_ms       = [double]$parts[2]
            }
        } else {
            [pscustomobject]@{
                elapsed_ms         = [double]$parts[0]
                memory_delta_bytes = [long]$parts[1]
                cpu_delta_ms       = [double]$parts[2]
                gc_gen0_delta      = [int]$parts[3]
                gc_gen1_delta      = [int]$parts[4]
                gc_gen2_delta      = [int]$parts[5]
                thread_delta       = [int]$parts[6]
            }
        }
    })
}

# ---------------------------------------------------------------------------
# Load fixture CSV
# ---------------------------------------------------------------------------
if (-not (Test-Path $csvPath)) {
    throw "Fixture not found: '$csvPath'. Ensure the file exists before running tests."
}
$allCases = Import-Csv $csvPath

# ---------------------------------------------------------------------------
# Tests: Get-SampleStats (CSV-driven)
# ---------------------------------------------------------------------------
Describe "OneimAudit.Benchmark - Get-SampleStats" {

    $statsCases = @($allCases | Where-Object { $_.function -eq 'stats' })

    foreach ($case in $statsCases) {
        It $case.test_case {
            $samples = @(ConvertTo-SamplesFromRow $case.samples)
            $s = Get-SampleStats -Samples $samples

            # --- elapsed metrics ---
            if ($case.expected_avg_ms    -ne '') { $s.avg_ms    | Should -Be ([double]$case.expected_avg_ms) }
            if ($case.expected_stddev_ms -ne '') { $s.stddev_ms | Should -Be ([double]$case.expected_stddev_ms) }
            if ($case.expected_min_ms    -ne '') { $s.min_ms    | Should -Be ([double]$case.expected_min_ms) }
            if ($case.expected_max_ms    -ne '') { $s.max_ms    | Should -Be ([double]$case.expected_max_ms) }

            # --- percentiles ---
            if ($case.expected_p50_ms -ne '') { $s.p50_ms | Should -Be ([double]$case.expected_p50_ms) }
            if ($case.expected_p75_ms -ne '') { $s.p75_ms | Should -Be ([double]$case.expected_p75_ms) }
            if ($case.expected_p95_ms -ne '') { $s.p95_ms | Should -Be ([double]$case.expected_p95_ms) }
            if ($case.expected_p99_ms -ne '') { $s.p99_ms | Should -Be ([double]$case.expected_p99_ms) }

            # --- variability ---
            if ($case.expected_cv_pct        -ne '') { $s.cv_pct              | Should -Be ([double]$case.expected_cv_pct) }
            if ($case.expected_stability     -ne '') { $s.stability           | Should -Be $case.expected_stability }
            if ($case.expected_warmup_ratio  -ne '') { $s.warmup_effect_ratio | Should -Be ([double]$case.expected_warmup_ratio) }

            # --- GC ---
            if ($case.expected_total_gc0 -ne '') { $s.total_gc_gen0 | Should -Be ([int]$case.expected_total_gc0) }
            if ($case.expected_total_gc1 -ne '') { $s.total_gc_gen1 | Should -Be ([int]$case.expected_total_gc1) }
            if ($case.expected_total_gc2 -ne '') { $s.total_gc_gen2 | Should -Be ([int]$case.expected_total_gc2) }

            # --- threads ---
            if ($case.expected_max_threads -ne '') { $s.max_thread_delta | Should -Be ([int]$case.expected_max_threads) }

            # --- memory ---
            if ($case.expected_avg_mem -ne '') { $s.avg_mem_bytes | Should -Be ([long]$case.expected_avg_mem) }
            if ($case.expected_min_mem -ne '') { $s.min_mem_bytes | Should -Be ([long]$case.expected_min_mem) }
            if ($case.expected_max_mem -ne '') { $s.max_mem_bytes | Should -Be ([long]$case.expected_max_mem) }

            # --- cpu ---
            if ($case.expected_avg_cpu -ne '') { $s.avg_cpu_ms | Should -Be ([double]$case.expected_avg_cpu) }
            if ($case.expected_min_cpu -ne '') { $s.min_cpu_ms | Should -Be ([double]$case.expected_min_cpu) }
            if ($case.expected_max_cpu -ne '') { $s.max_cpu_ms | Should -Be ([double]$case.expected_max_cpu) }

            # --- output shape guard ---
            if ($case.assert_all_props -eq 'true') {
                $props = $s.PSObject.Properties.Name
                foreach ($p in @('avg_ms','stddev_ms','min_ms','max_ms',
                                 'p50_ms','p75_ms','p95_ms','p99_ms',
                                 'cv_pct','stability','warmup_effect_ratio',
                                 'avg_mem_bytes','min_mem_bytes','max_mem_bytes',
                                 'avg_cpu_ms','min_cpu_ms','max_cpu_ms',
                                 'total_gc_gen0','total_gc_gen1','total_gc_gen2',
                                 'max_thread_delta')) {
                    $props | Should -Contain $p
                }
            }
        }
    }
}

# ---------------------------------------------------------------------------
# Tests: Get-ThresholdResult (CSV-driven)
# ---------------------------------------------------------------------------
Describe "OneimAudit.Benchmark - Get-ThresholdResult" {

    $thresholdCases = @($allCases | Where-Object { $_.function -eq 'threshold' })

    foreach ($case in $thresholdCases) {
        It $case.test_case {
            # Rebuild the $thresholds hashtable that Get-ThresholdResult reads from scope
            $script:thresholds = @{}
            $key = "{0}::{1}" -f $case.threshold_surface, $case.threshold_name

            if ($case.threshold_max_avg_ms -ne '' -and $case.threshold_max_p95_ms -ne '') {
                $script:thresholds[$key] = [pscustomobject]@{
                    max_avg_ms = [double]$case.threshold_max_avg_ms
                    max_p95_ms = [double]$case.threshold_max_p95_ms
                }
            } elseif ($case.threshold_max_avg_ms -ne '') {
                $script:thresholds[$key] = [pscustomobject]@{ max_avg_ms = [double]$case.threshold_max_avg_ms }
            } elseif ($case.threshold_max_p95_ms -ne '') {
                $script:thresholds[$key] = [pscustomobject]@{ max_p95_ms = [double]$case.threshold_max_p95_ms }
            }
            # else: leave $script:thresholds empty — no-entry case

            $mockStats = [pscustomobject]@{
                avg_ms = [double]$case.stats_avg_ms
                p95_ms = [double]$case.stats_p95_ms
            }

            $result = Get-ThresholdResult -Surface $case.threshold_surface -Name $case.threshold_name -Stats $mockStats

            if ($case.expected_threshold_exceeded -ne '') {
                $result.exceeded | Should -Be ([bool]::Parse($case.expected_threshold_exceeded))
            }
        }
    }
}

# ---------------------------------------------------------------------------
# Tests: Get-RegressionResult (inline — depends on $script:baselineIndex and
#        $script:RegressionThreshold, which mirror the script-scope variables
#        populated from -BaselineBenchmarkPath at runtime)
# ---------------------------------------------------------------------------
Describe "OneimAudit.Benchmark - Get-RegressionResult" {

    BeforeEach {
        # Reset scope state before each test
        $script:baselineIndex     = @{}
        $script:RegressionThreshold = 20.0
    }

    It "returns has_baseline=false when no baseline entry exists" {
        $r = Get-RegressionResult -Surface 'template' -Name 'Person.FirstName' -CurrentAvgMs 30.0
        $r.has_baseline    | Should -Be $false
        $r.regressed       | Should -Be $false
        $r.baseline_avg_ms | Should -BeNullOrEmpty
        $r.regression_pct  | Should -BeNullOrEmpty
    }

    It "returns has_baseline=true and regressed=false when below threshold" {
        $script:baselineIndex['template::Person.FirstName'] = [pscustomobject]@{ avg_ms = 100.0 }
        # current = 115 → 15% increase < 20% threshold
        $r = Get-RegressionResult -Surface 'template' -Name 'Person.FirstName' -CurrentAvgMs 115.0
        $r.has_baseline    | Should -Be $true
        $r.baseline_avg_ms | Should -Be 100.0
        $r.regression_pct  | Should -Be 15.0
        $r.regressed       | Should -Be $false
    }

    It "returns regressed=true when avg_ms increase exceeds threshold" {
        $script:baselineIndex['template::Person.FirstName'] = [pscustomobject]@{ avg_ms = 100.0 }
        # current = 125 → 25% increase > 20% threshold
        $r = Get-RegressionResult -Surface 'template' -Name 'Person.FirstName' -CurrentAvgMs 125.0
        $r.has_baseline   | Should -Be $true
        $r.regression_pct | Should -Be 25.0
        $r.regressed      | Should -Be $true
    }

    It "returns regressed=false when avg_ms decreases (negative regression_pct)" {
        $script:baselineIndex['template::Person.LastName'] = [pscustomobject]@{ avg_ms = 200.0 }
        # current = 150 → -25%, improvement, not a regression
        $r = Get-RegressionResult -Surface 'template' -Name 'Person.LastName' -CurrentAvgMs 150.0
        $r.regression_pct | Should -Be -25
        $r.regressed      | Should -Be $false
    }

    It "regression_pct = 0 when baseline avg_ms is zero (divide-by-zero guard)" {
        $script:baselineIndex['process::MyProc'] = [pscustomobject]@{ avg_ms = 0.0 }
        $r = Get-RegressionResult -Surface 'process' -Name 'MyProc' -CurrentAvgMs 50.0
        $r.has_baseline   | Should -Be $true
        $r.regression_pct | Should -Be 0.0
        $r.regressed      | Should -Be $false
    }

    It "uses custom RegressionThreshold when set" {
        $script:RegressionThreshold = 10.0
        $script:baselineIndex['script_method::CalcRoles'] = [pscustomobject]@{ avg_ms = 100.0 }
        # current = 115 → 15% > 10% custom threshold
        $r = Get-RegressionResult -Surface 'script_method' -Name 'CalcRoles' -CurrentAvgMs 115.0
        $r.regressed | Should -Be $true
    }

    It "key lookup is surface-qualified (same name, different surface is no-match)" {
        $script:baselineIndex['template::Shared.Value'] = [pscustomobject]@{ avg_ms = 80.0 }
        # Looking up 'process' surface — different key, no baseline
        $r = Get-RegressionResult -Surface 'process' -Name 'Shared.Value' -CurrentAvgMs 120.0
        $r.has_baseline | Should -Be $false
    }

    It "regression_pct is rounded to one decimal place" {
        $script:baselineIndex['template::Person.Email'] = [pscustomobject]@{ avg_ms = 300.0 }
        # (310 - 300) / 300 * 100 = 3.333... → rounds to 3.3
        $r = Get-RegressionResult -Surface 'template' -Name 'Person.Email' -CurrentAvgMs 310.0
        $r.regression_pct | Should -Be 3.3
    }
}

# ---------------------------------------------------------------------------
# Tests: Get-OneImAuditDmvDelta (pure math — no live DB connection required)
# ---------------------------------------------------------------------------
Describe "OneimAudit.Benchmark - Get-OneImAuditDmvDelta" {

    function New-DmvSnap { param([long]$lr, [long]$lc, [long]$lm)
        [pscustomobject]@{ logical_reads = $lr; lck_wait_count = $lc; lck_wait_ms = $lm }
    }

    It "divides logical read delta by run count" {
        $before = New-DmvSnap -lr 1000 -lc 0 -lm 0
        $after  = New-DmvSnap -lr 1100 -lc 0 -lm 0
        $d = Get-OneImAuditDmvDelta -Before $before -After $after -RunCount 10
        $d.logical_reads_per_run | Should -Be 10
    }

    It "divides lck_wait_count delta by run count" {
        $before = New-DmvSnap -lr 0 -lc 200 -lm 0
        $after  = New-DmvSnap -lr 0 -lc 260 -lm 0
        $d = Get-OneImAuditDmvDelta -Before $before -After $after -RunCount 3
        $d.lck_wait_count_per_run | Should -Be 20
    }

    It "divides lck_wait_ms delta by run count" {
        $before = New-DmvSnap -lr 0 -lc 0 -lm 300
        $after  = New-DmvSnap -lr 0 -lc 0 -lm 600
        $d = Get-OneImAuditDmvDelta -Before $before -After $after -RunCount 5
        $d.lck_wait_ms_per_run | Should -Be 60
    }

    It "returns zeros for all fields when RunCount is 0" {
        $before = New-DmvSnap -lr 100 -lc 50 -lm 20
        $after  = New-DmvSnap -lr 200 -lc 80 -lm 40
        $d = Get-OneImAuditDmvDelta -Before $before -After $after -RunCount 0
        $d.logical_reads_per_run  | Should -Be 0
        $d.lck_wait_count_per_run | Should -Be 0
        $d.lck_wait_ms_per_run    | Should -Be 0
    }

    It "returns zeros when after equals before (no activity)" {
        $snap = New-DmvSnap -lr 500 -lc 100 -lm 50
        $d = Get-OneImAuditDmvDelta -Before $snap -After $snap -RunCount 5
        $d.logical_reads_per_run  | Should -Be 0
        $d.lck_wait_count_per_run | Should -Be 0
        $d.lck_wait_ms_per_run    | Should -Be 0
    }

    It "clamps negative deltas to zero (DMV counter reset or session reuse)" {
        # After < Before should never happen in practice, but clamped to 0 for safety
        $before = New-DmvSnap -lr 1000 -lc 100 -lm 50
        $after  = New-DmvSnap -lr  900 -lc  90 -lm 40
        $d = Get-OneImAuditDmvDelta -Before $before -After $after -RunCount 5
        $d.logical_reads_per_run  | Should -Be 0
        $d.lck_wait_count_per_run | Should -Be 0
        $d.lck_wait_ms_per_run    | Should -Be 0
    }

    It "result has all three required fields" {
        $before = New-DmvSnap -lr 0 -lc 0 -lm 0
        $after  = New-DmvSnap -lr 0 -lc 0 -lm 0
        $d = Get-OneImAuditDmvDelta -Before $before -After $after -RunCount 1
        $d.PSObject.Properties.Name | Should -Contain 'logical_reads_per_run'
        $d.PSObject.Properties.Name | Should -Contain 'lck_wait_count_per_run'
        $d.PSObject.Properties.Name | Should -Contain 'lck_wait_ms_per_run'
    }
}
