<#
.SYNOPSIS
Compares two OneIM schema snapshots and reports structural differences.

.DESCRIPTION
Loads a baseline snapshot and a current snapshot (both produced by
export_oneim_schema_snapshot.ps1) and computes the delta across:

  - Tables     : added / removed (by table_name)
  - Columns    : added / removed (by table_name + column_name)
               : has_template changed (column gained or lost a template)
  - FK relations: added / removed (by child_table + child_column + parent_table)

The diff is written as schema-diff.json in the output directory.
A console summary is printed with counts per section.

Exit codes:
  0 — no structural differences found
  1 — one or more differences found
  2 — error loading snapshots or writing output

.PARAMETER BaselinePath
Path to the baseline schema-snapshot.json.

.PARAMETER CurrentPath
Path to the current (newer) schema-snapshot.json.

.PARAMETER OutputDir
Directory to write schema-diff.json. Defaults to the directory containing CurrentPath.

.PARAMETER FailOnDiff
When set, exits with code 1 if any diff is found. Useful in CI pipelines.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$BaselinePath,

    [Parameter(Mandatory)]
    [string]$CurrentPath,

    [Parameter()]
    [string]$OutputDir,

    [Parameter()]
    [switch]$FailOnDiff
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

try {
    # ---------------------------------------------------------------------------
    # Load snapshots
    # ---------------------------------------------------------------------------
    $baselineFullPath = [System.IO.Path]::GetFullPath($BaselinePath)
    $currentFullPath  = [System.IO.Path]::GetFullPath($CurrentPath)

    if (-not (Test-Path -LiteralPath $baselineFullPath)) {
        throw "Baseline snapshot not found: '$baselineFullPath'."
    }
    if (-not (Test-Path -LiteralPath $currentFullPath)) {
        throw "Current snapshot not found: '$currentFullPath'."
    }

    $baseline = Get-Content -LiteralPath $baselineFullPath -Raw | ConvertFrom-Json
    $current  = Get-Content -LiteralPath $currentFullPath  -Raw | ConvertFrom-Json

    # ---------------------------------------------------------------------------
    # Build lookup sets for fast O(1) membership checks
    # ---------------------------------------------------------------------------
    $baseTables = @{}
    foreach ($t in @($baseline.tables)) { $baseTables[[string]$t.table_name] = $t }

    $currTables = @{}
    foreach ($t in @($current.tables)) { $currTables[[string]$t.table_name] = $t }

    $baseCols = @{}
    foreach ($c in @($baseline.columns)) {
        $key = ("{0}.{1}" -f [string]$c.table_name, [string]$c.column_name)
        $baseCols[$key] = $c
    }

    $currCols = @{}
    foreach ($c in @($current.columns)) {
        $key = ("{0}.{1}" -f [string]$c.table_name, [string]$c.column_name)
        $currCols[$key] = $c
    }

    $baseFks = @{}
    foreach ($fk in @($baseline.fk_relations)) {
        $key = ("{0}.{1}->{2}" -f [string]$fk.child_table, [string]$fk.child_column, [string]$fk.parent_table)
        $baseFks[$key] = $fk
    }

    $currFks = @{}
    foreach ($fk in @($current.fk_relations)) {
        $key = ("{0}.{1}->{2}" -f [string]$fk.child_table, [string]$fk.child_column, [string]$fk.parent_table)
        $currFks[$key] = $fk
    }

    # ---------------------------------------------------------------------------
    # Diff: tables
    # ---------------------------------------------------------------------------
    $tablesAdded   = New-Object System.Collections.Generic.List[object]
    $tablesRemoved = New-Object System.Collections.Generic.List[object]

    foreach ($name in $currTables.Keys) {
        if (-not $baseTables.ContainsKey($name)) {
            $tablesAdded.Add([ordered]@{ table_name = $name })
        }
    }
    foreach ($name in $baseTables.Keys) {
        if (-not $currTables.ContainsKey($name)) {
            $tablesRemoved.Add([ordered]@{ table_name = $name })
        }
    }

    # ---------------------------------------------------------------------------
    # Diff: columns
    # ---------------------------------------------------------------------------
    $columnsAdded          = New-Object System.Collections.Generic.List[object]
    $columnsRemoved        = New-Object System.Collections.Generic.List[object]
    $columnsTemplateGained = New-Object System.Collections.Generic.List[object]
    $columnsTemplateLost   = New-Object System.Collections.Generic.List[object]

    foreach ($key in $currCols.Keys) {
        $c = $currCols[$key]
        if (-not $baseCols.ContainsKey($key)) {
            $columnsAdded.Add([ordered]@{
                table_name  = [string]$c.table_name
                column_name = [string]$c.column_name
                has_template = if ($null -ne $c.PSObject.Properties["has_template"]) { [bool]$c.has_template } else { $false }
            })
        } else {
            # Check has_template change
            $baseHas = if ($null -ne $baseCols[$key].PSObject.Properties["has_template"]) { [bool]$baseCols[$key].has_template } else { $false }
            $currHas = if ($null -ne $c.PSObject.Properties["has_template"])              { [bool]$c.has_template }              else { $false }
            if ($baseHas -ne $currHas) {
                $entry = [ordered]@{
                    table_name        = [string]$c.table_name
                    column_name       = [string]$c.column_name
                    baseline_has_template = $baseHas
                    current_has_template  = $currHas
                }
                if ($currHas) { $columnsTemplateGained.Add($entry) } else { $columnsTemplateLost.Add($entry) }
            }
        }
    }
    foreach ($key in $baseCols.Keys) {
        if (-not $currCols.ContainsKey($key)) {
            $c = $baseCols[$key]
            $columnsRemoved.Add([ordered]@{
                table_name  = [string]$c.table_name
                column_name = [string]$c.column_name
            })
        }
    }

    # ---------------------------------------------------------------------------
    # Diff: FK relations
    # ---------------------------------------------------------------------------
    $fksAdded   = New-Object System.Collections.Generic.List[object]
    $fksRemoved = New-Object System.Collections.Generic.List[object]

    foreach ($key in $currFks.Keys) {
        if (-not $baseFks.ContainsKey($key)) {
            $fk = $currFks[$key]
            $fksAdded.Add([ordered]@{
                child_table   = [string]$fk.child_table
                child_column  = [string]$fk.child_column
                parent_table  = [string]$fk.parent_table
                parent_column = if ($null -ne $fk.PSObject.Properties["parent_column"]) { [string]$fk.parent_column } else { "" }
            })
        }
    }
    foreach ($key in $baseFks.Keys) {
        if (-not $currFks.ContainsKey($key)) {
            $fk = $baseFks[$key]
            $fksRemoved.Add([ordered]@{
                child_table   = [string]$fk.child_table
                child_column  = [string]$fk.child_column
                parent_table  = [string]$fk.parent_table
                parent_column = if ($null -ne $fk.PSObject.Properties["parent_column"]) { [string]$fk.parent_column } else { "" }
            })
        }
    }

    # ---------------------------------------------------------------------------
    # Build diff report
    # ---------------------------------------------------------------------------
    $hasDiff = ($tablesAdded.Count   -gt 0 -or $tablesRemoved.Count   -gt 0 -or
                $columnsAdded.Count  -gt 0 -or $columnsRemoved.Count  -gt 0 -or
                $columnsTemplateGained.Count -gt 0 -or $columnsTemplateLost.Count -gt 0 -or
                $fksAdded.Count      -gt 0 -or $fksRemoved.Count      -gt 0)

    $totalDiffs = $tablesAdded.Count + $tablesRemoved.Count +
                  $columnsAdded.Count + $columnsRemoved.Count +
                  $columnsTemplateGained.Count + $columnsTemplateLost.Count +
                  $fksAdded.Count + $fksRemoved.Count

    $report = [ordered]@{
        diff_metadata = [ordered]@{
            generated_at      = (Get-Date -Format "o")
            baseline_path     = $baselineFullPath
            current_path      = $currentFullPath
            baseline_snapshot_at = if ($null -ne $baseline.PSObject.Properties["snapshot_metadata"]) { [string]$baseline.snapshot_metadata.generated_at } else { $null }
            current_snapshot_at  = if ($null -ne $current.PSObject.Properties["snapshot_metadata"])  { [string]$current.snapshot_metadata.generated_at }  else { $null }
            has_diff          = $hasDiff
            total_differences = $totalDiffs
        }
        summary = [ordered]@{
            tables_added              = $tablesAdded.Count
            tables_removed            = $tablesRemoved.Count
            columns_added             = $columnsAdded.Count
            columns_removed           = $columnsRemoved.Count
            columns_template_gained   = $columnsTemplateGained.Count
            columns_template_lost     = $columnsTemplateLost.Count
            fk_relations_added        = $fksAdded.Count
            fk_relations_removed      = $fksRemoved.Count
        }
        tables = [ordered]@{
            added   = $tablesAdded.ToArray()
            removed = $tablesRemoved.ToArray()
        }
        columns = [ordered]@{
            added            = $columnsAdded.ToArray()
            removed          = $columnsRemoved.ToArray()
            template_gained  = $columnsTemplateGained.ToArray()
            template_lost    = $columnsTemplateLost.ToArray()
        }
        fk_relations = [ordered]@{
            added   = $fksAdded.ToArray()
            removed = $fksRemoved.ToArray()
        }
    }

    # ---------------------------------------------------------------------------
    # Write output
    # ---------------------------------------------------------------------------
    $resolvedOutputDir = if (-not [string]::IsNullOrWhiteSpace($OutputDir)) {
        [System.IO.Path]::GetFullPath($OutputDir)
    } else {
        [System.IO.Path]::GetDirectoryName($currentFullPath)
    }

    $null = New-Item -ItemType Directory -Path $resolvedOutputDir -Force

    $diffPath = Join-Path $resolvedOutputDir "schema-diff.json"
    $report | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $diffPath -Encoding UTF8

    # ---------------------------------------------------------------------------
    # Console summary
    # ---------------------------------------------------------------------------
    Write-Host ("Schema diff written to: {0}" -f $diffPath)
    Write-Host ("  Tables  : +{0} / -{1}" -f $tablesAdded.Count, $tablesRemoved.Count)
    Write-Host ("  Columns : +{0} / -{1}  template_gained={2}  template_lost={3}" -f `
        $columnsAdded.Count, $columnsRemoved.Count,
        $columnsTemplateGained.Count, $columnsTemplateLost.Count)
    Write-Host ("  FK rels : +{0} / -{1}" -f $fksAdded.Count, $fksRemoved.Count)

    if (-not $hasDiff) {
        Write-Host "  No structural differences found."
        exit 0
    }

    Write-Host ("  Total differences: {0}" -f $totalDiffs)

    if ($FailOnDiff) {
        exit 1
    }
    exit 0
}
catch {
    $host.UI.WriteErrorLine($_.ToString())
    exit 2
}
