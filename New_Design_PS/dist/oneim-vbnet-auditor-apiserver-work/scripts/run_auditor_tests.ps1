[CmdletBinding()]
param(
    # When set, also runs OneimAudit.BenchmarkIntegration.Tests.ps1 which requires
    # a live OneIM connection and rows in tests/fixtures/benchmark-integration-targets.csv.
    [switch]$Integration
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$scriptRoot = Split-Path -Parent $PSCommandPath
$skillRoot  = Split-Path -Parent $scriptRoot
$testDir    = Join-Path $skillRoot "tests"

# ---------------------------------------------------------------------------
# Lane 1 tests — PS5.1 (run in the current shell, which may be PS5.1 or PS7)
# ---------------------------------------------------------------------------
$lane1TestPath = Join-Path $testDir "Oneim.VbNet.Auditor.Tests.ps1"

if (-not (Test-Path -LiteralPath $lane1TestPath)) {
    throw "Lane 1 test file not found at $lane1TestPath"
}

$pester = Get-Command Invoke-Pester -ErrorAction SilentlyContinue
if ($null -eq $pester) {
    throw "Invoke-Pester was not found. Install or enable Pester before running the auditor test suite."
}

Write-Host ""
Write-Host "=== Lane 1: Static analysis tests (PS5.1) ==="
$lane1Result = Invoke-Pester -Script $lane1TestPath -PassThru
if ($null -eq $lane1Result) {
    throw "Invoke-Pester did not return a result object."
}

$anyFailed = [int]$lane1Result.FailedCount -gt 0

# ---------------------------------------------------------------------------
# Lane 2 + Lane 3 tests — require PS7 (pwsh)
# ---------------------------------------------------------------------------
$ps7Tests = @(
    @{ Label = "Lane 2: Schema index tests";    Path = Join-Path $testDir "OneimAudit.Schema.Tests.ps1" }
    @{ Label = "Lane 3: Benchmark stats tests"; Path = Join-Path $testDir "OneimAudit.Benchmark.Tests.ps1" }
    @{ Label = "Lane 3: Graph module tests";    Path = Join-Path $testDir "OneimAudit.Graph.Tests.ps1" }
)

if ($Integration) {
    $ps7Tests += @{ Label = "Lane 3: Benchmark integration tests (live)"; Path = Join-Path $testDir "OneimAudit.BenchmarkIntegration.Tests.ps1" }
}

$pwshCmd = Get-Command pwsh -ErrorAction SilentlyContinue
if ($null -eq $pwshCmd) {
    Write-Warning "pwsh (PowerShell 7) not found. Skipping Lane 2 and Lane 3 tests."
}
else {
    $pwshExe = $pwshCmd.Source

    foreach ($entry in $ps7Tests) {
        $testPath = $entry.Path
        $label    = $entry.Label

        if (-not (Test-Path -LiteralPath $testPath)) {
            Write-Warning ("Test file not found, skipping: {0}" -f $testPath)
            continue
        }

        Write-Host ""
        Write-Host ("=== {0} (PS7) ===" -f $label)

        # Escape single quotes in the path for the -Command string
        $escaped = $testPath -replace "'", "''"

        # Pester 4.10.1 lives in the WindowsPowerShell path, invisible to PS7 by default.
        # Load it explicitly by path so the PS7 process uses the same Pester version.
        $pester4Path = "C:\Users\aiuser\Documents\WindowsPowerShell\Modules\Pester\4.10.1\Pester.psd1"

        & $pwshExe -NoProfile -NonInteractive -Command "
            `$ErrorActionPreference = 'Stop'
            if (Test-Path -LiteralPath '$pester4Path') {
                Import-Module '$pester4Path' -Force
            }
            `$r = Invoke-Pester -Script '$escaped' -PassThru
            if ([int]`$r.FailedCount -gt 0) { exit 1 }
            exit 0
        "

        if ($LASTEXITCODE -ne 0) {
            Write-Host ("FAILED: {0}" -f $label) -ForegroundColor Red
            $anyFailed = $true
        }
    }
}

# ---------------------------------------------------------------------------
# Final exit
# ---------------------------------------------------------------------------
if ($anyFailed) {
    exit 1
}

exit 0
