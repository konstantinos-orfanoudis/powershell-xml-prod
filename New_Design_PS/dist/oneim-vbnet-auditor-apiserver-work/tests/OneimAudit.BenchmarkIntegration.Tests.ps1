#Requires -Version 7
$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

<#
.SYNOPSIS
Integration tests for invoke_oneim_benchmark.ps1 against a live OneIM system.

Driven by tests/fixtures/benchmark-integration-targets.csv. Each row defines one
benchmark scenario. Add trigger-value columns after the fixed columns:

  Fixed columns: surface, name, access_mode, Value, max_avg_ms, max_p95_ms,
                 expected_outcome, notes

  Dynamic trigger-value columns — all three template notations map to the same column name:
    Any column NOT in the fixed set and NOT starting with "var_" is a trigger input.

      GetTriggerValue("Source")  → column header "Source"
      $Source$                   → column header "Source"   ($X$ is shorthand for GetTriggerValue)
      GetTriggerValue("FK(UID_AADRole).Provider") → column "FK(UID_AADRole).Provider"

  Variables columns — both VB.NET forms map to the same var_ prefix:
    Any column starting with "var_" sets a connection variable.

      Variables.Get("FULLSYNC")  → column "var_FULLSYNC"
      Variables("FULLSYNC")      → column "var_FULLSYNC"

  Example (two trigger-value columns):
    surface,name,access_mode,Value,Source,UID_AADRole,max_avg_ms,max_p95_ms,expected_outcome,notes
    template,AADRoleAssignment.ObjectKeyAppScope,Auto,,PIM,,50,,success,PIM short-circuit path
    template,AADRoleAssignment.ObjectKeyAppScope,Auto,,Other,abc-uid-here,50,,success,full evaluation path

Tests are skipped automatically when the CSV has no data rows.

To run:
  powershell.exe -NonInteractive -File scripts/run_auditor_tests.ps1 -Integration
#>

$skillRoot       = Split-Path -Parent $PSScriptRoot
$scriptRoot      = Join-Path $skillRoot "scripts"
$benchmarkScript = Join-Path $scriptRoot "invoke_oneim_benchmark.ps1"
$fixturesDir     = Join-Path $PSScriptRoot "fixtures"
$csvPath         = Join-Path $fixturesDir "benchmark-integration-targets.csv"

# Fixed column names — anything else is a dynamic input column
$fixedColumnNames = @('surface','name','access_mode','Value',
                      'max_avg_ms','max_p95_ms','expected_outcome','notes')

# ---------------------------------------------------------------------------
# Guard: skip entire suite when no rows are configured
# ---------------------------------------------------------------------------
$integrationRows = @()
if (Test-Path $csvPath) {
    $integrationRows = @(Import-Csv $csvPath | Where-Object { $_.surface -ne '' })
}

if ($integrationRows.Count -eq 0) {
    Write-Warning "benchmark-integration-targets.csv has no data rows — no integration tests to run."
    Write-Warning "Add rows to '$csvPath' with real OneIM template/method/process names and inputs."
    return
}

# ---------------------------------------------------------------------------
# Run the benchmark script once for the entire targets file.
# All rows run in a single invocation; the combined report is then inspected.
# ---------------------------------------------------------------------------
$tempOutput = Join-Path ([System.IO.Path]::GetTempPath()) ("bench-integration-{0}" -f [guid]::NewGuid().ToString('N'))
$null = New-Item -ItemType Directory -Path $tempOutput -Force

$benchArgs = @(
    '-NoProfile', '-NonInteractive', '-File', $benchmarkScript,
    '-TargetsFile', $csvPath,
    '-WarmupCount',      '1',
    '-MeasuredRunCount', '3',    # keep fast; shape + outcome verification only
    '-OutputDir', $tempOutput
)

$proc = Start-Process pwsh -ArgumentList $benchArgs -Wait -PassThru -NoNewWindow

$reportPath = Get-ChildItem -Path $tempOutput -Filter 'benchmark-report.json' -Recurse |
              Sort-Object LastWriteTime -Descending |
              Select-Object -First 1 -ExpandProperty FullName

$report  = $null
$results = @()
if ($reportPath -and (Test-Path $reportPath)) {
    $report  = Get-Content $reportPath -Raw | ConvertFrom-Json
    $results = @($report.results)
}

# ---------------------------------------------------------------------------
# Suite-level assertions
# ---------------------------------------------------------------------------
Describe "OneimAudit.Benchmark - Integration (live system)" {

    It "benchmark script exits without catastrophic failure" {
        $proc.ExitCode | Should -Not -Be $null
    }

    It "produces a benchmark-report.json" {
        $reportPath          | Should -Not -BeNullOrEmpty
        Test-Path $reportPath | Should -Be $true
    }

    It "report JSON has required top-level structure" {
        $report                  | Should -Not -BeNullOrEmpty
        $report.report_metadata  | Should -Not -BeNullOrEmpty
        $report.summary          | Should -Not -BeNullOrEmpty
        $report.results          | Should -Not -BeNullOrEmpty
    }

    # ---------------------------------------------------------------------------
    # Per-row assertions
    # ---------------------------------------------------------------------------
    foreach ($row in $integrationRows) {
        $label = "{0} [{1}]" -f $row.name, $row.surface

        # Collect which dynamic input columns this row has (for display in test name)
        $inputCols = @($row.PSObject.Properties |
            Where-Object { $_.Name -notin $fixedColumnNames -and $_.Value -ne '' } |
            ForEach-Object { $_.Name })

        $inputSuffix = if ($inputCols.Count -gt 0) {
            " inputs=[{0}]" -f ($inputCols -join ',')
        } else { "" }

        Context ("{0}{1}" -f $label, $inputSuffix) {

            $entry = $null
            if ($results.Count -gt 0) {
                $entry = @($results | Where-Object {
                    $_.name -eq $row.name -and $_.surface -eq $row.surface
                }) | Select-Object -First 1
            }

            It "report contains a result entry for this target" {
                $entry | Should -Not -BeNullOrEmpty
            }

            if ($row.expected_outcome -eq 'success') {

                It "result has no error field (success path)" {
                    [string]$entry.error | Should -BeNullOrEmpty
                }

                It "result has all required stat fields" {
                    $props = $entry.PSObject.Properties.Name
                    foreach ($p in @('avg_ms','stddev_ms','p50_ms','p75_ms','p95_ms','p99_ms',
                                     'cv_pct','stability','warmup_effect_ratio',
                                     'total_gc_gen0','total_gc_gen1','total_gc_gen2',
                                     'max_thread_delta','raw_samples')) {
                        $props | Should -Contain $p
                    }
                }

                It "execution_mode is mock_entity when seed inputs were supplied" {
                    if ($inputCols.Count -gt 0) {
                        [string]$entry.execution_mode | Should -Be "mock_entity"
                    }
                }
            }

            if ($row.expected_outcome -eq 'error') {
                It "result has an error field (partial failure path)" {
                    [string]$entry.error | Should -Not -BeNullOrEmpty
                }
            }

            if ($row.expected_outcome -eq 'threshold_exceeded') {
                It "result has threshold_exceeded = true" {
                    [bool]$entry.threshold_exceeded | Should -Be $true
                }
            }
        }
    }
}
