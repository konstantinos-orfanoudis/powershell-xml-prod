<#
.SYNOPSIS
Exports a structural snapshot of the OneIM database schema.

.DESCRIPTION
Connects to the OneIM database (via TestAssist session or direct ADO.NET) and extracts
table definitions, column metadata, and foreign-key relationships from the OneIM dictionary
tables (DialogTable, DialogColumn, ForeignKey / ColumnRelation).

The snapshot is written as schema-snapshot.json in the output directory. On subsequent runs
without -Force, an existing snapshot is reused (prints the cached path and exits 0).

The JSON contains:
  - snapshot_metadata  : run provenance
  - tables             : all non-generated DialogTable rows
  - columns            : all DialogColumn rows with table name and template flag
  - fk_relations       : all FK edges (child table+column -> parent table+column)
  - indexes            : pre-built lookup maps for fast cascade resolution

.PARAMETER TestAssistRoot
Path to the TestAssist installation. Defaults to the known DeploymentManager default.

.PARAMETER ProjectConfigPath
Path to projectConfig.xml. Defaults to the known DMWorkshop2 default.

.PARAMETER AccessMode
How to reach the database: Auto (try Direct first, fall back to Session), Session, or Direct.
Defaults to Auto.

.PARAMETER OutputDir
Root directory for snapshot output. The snapshot is written to a sub-folder named after
the environment fingerprint. Defaults to output\oneim-schema\ under the current directory.

.PARAMETER Force
Regenerate the snapshot even when a cached version already exists.
#>
[CmdletBinding()]
param(
    [Parameter()]
    [string]$TestAssistRoot,

    [Parameter()]
    [string]$ProjectConfigPath,

    [Parameter()]
    [ValidateSet("Auto", "Session", "Direct")]
    [string]$AccessMode = "Auto",

    [Parameter()]
    [string]$OutputDir,

    [Parameter()]
    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$scriptRoot = Split-Path -Parent $PSCommandPath
$moduleRoot = Join-Path $scriptRoot "modules"

Import-Module (Join-Path $moduleRoot "OneimAudit.LiveSession.psm1") -Force

# ---------------------------------------------------------------------------
# Resolve settings
# ---------------------------------------------------------------------------
$settings = Get-OneImAuditSessionSettings `
    -TestAssistRoot     $TestAssistRoot `
    -ProjectConfigPath  $ProjectConfigPath

$config = Get-OneImAuditProjectConfig -ProjectConfigPath $settings.ProjectConfigPath

# Build a short, path-safe environment fingerprint from the data source and database.
# When DataSource contains a full connection string, extract just the server and catalog.
$dsRaw = [string]$config.DataSource
$fpServer = $dsRaw
$fpDb     = [string]$config.Database

if ($dsRaw -match '(?i)(?:Data Source|Server)\s*=\s*([^;]+)') {
    $fpServer = $Matches[1].Trim()
}
if ($dsRaw -match '(?i)Initial Catalog\s*=\s*([^;]+)') {
    $fpDb = $Matches[1].Trim()
}

$fingerprintRaw = ("{0}_{1}" -f $fpServer, $fpDb) -replace '[\\/:*?"<>|=; ]', '_'
$envFingerprint = if ([string]::IsNullOrWhiteSpace($fingerprintRaw.Trim('_'))) { "unknown" } else { $fingerprintRaw.Trim('_') }

$resolvedOutputDir = if (-not [string]::IsNullOrWhiteSpace($OutputDir)) {
    [System.IO.Path]::GetFullPath($OutputDir)
} else {
    Join-Path (Get-Location).Path "output\oneim-schema\$envFingerprint"
}

$snapshotPath = Join-Path $resolvedOutputDir "schema-snapshot.json"

# ---------------------------------------------------------------------------
# Cache check
# ---------------------------------------------------------------------------
if (-not $Force -and (Test-Path -LiteralPath $snapshotPath)) {
    Write-Host ("Reusing cached schema snapshot: {0}" -f $snapshotPath)
    Write-Host "Use -Force to regenerate."
    exit 0
}

if (-not (Test-Path -LiteralPath $resolvedOutputDir)) {
    $null = New-Item -ItemType Directory -Path $resolvedOutputDir -Force
}

# ---------------------------------------------------------------------------
# SQL helpers — run via the shared module
# ---------------------------------------------------------------------------
function Invoke-SchemaQuery {
    param([string]$Sql)
    return Invoke-OneImAuditSqlQuery `
        -Query             $Sql `
        -AccessMode        $AccessMode `
        -Settings          $settings `
        -ProjectConfigPath $settings.ProjectConfigPath
}

# ---------------------------------------------------------------------------
# Detect which FK metadata table is available
# Prefer QBMRelation (present in OneIM 9.x), then legacy alternatives.
# ---------------------------------------------------------------------------
Write-Host "Detecting FK metadata table..."

$fkTableName = $null

$detectFkSql = @"
SELECT TOP 1 TABLE_NAME
FROM INFORMATION_SCHEMA.TABLES
WHERE TABLE_TYPE = 'BASE TABLE'
  AND TABLE_NAME IN ('QBMRelation','ForeignKey','ColumnRelation','DialogColumn_FK')
ORDER BY
  CASE TABLE_NAME
    WHEN 'QBMRelation'     THEN 1
    WHEN 'ForeignKey'      THEN 2
    WHEN 'ColumnRelation'  THEN 3
    WHEN 'DialogColumn_FK' THEN 4
    ELSE 9
  END
"@

try {
    $fkDetect = @(Invoke-SchemaQuery -Sql $detectFkSql)
    if ($fkDetect.Count -gt 0) {
        $fkTableName = [string]($fkDetect[0].TABLE_NAME)
    }
}
catch {
    Write-Warning ("FK metadata table detection failed: {0}" -f $_.Exception.Message)
}

# ---------------------------------------------------------------------------
# Fetch tables
# ---------------------------------------------------------------------------
Write-Host "Fetching table list from DialogTable..."

# Note: OneIM does not have an IsGenerated column on DialogTable.
# Fetch all tables; views (TableType='V') and union tables (TableType='U') are
# included so FK resolution can traverse the full dictionary graph.
$tablesSql = @"
SELECT UID_DialogTable, TableName, TableType
FROM DialogTable
ORDER BY TableName
"@

$tableRows = @(Invoke-SchemaQuery -Sql $tablesSql)
Write-Host ("  {0} tables found." -f $tableRows.Count)

$tablesList = New-Object 'System.Collections.Generic.List[object]'
foreach ($r in $tableRows) {
    $tablesList.Add([pscustomobject]@{
        table_name = [string]$r.TableName
        uid        = [string]$r.UID_DialogTable
        table_type = [string]$r.TableType
    })
}
$tables = $tablesList.ToArray()

# ---------------------------------------------------------------------------
# Fetch columns
# ---------------------------------------------------------------------------
Write-Host "Fetching column metadata from DialogColumn..."

# The template expression column in OneIM is named 'Template', not 'TemplateValue'.
$columnsSql = @"
SELECT
    c.UID_DialogColumn,
    t.TableName,
    c.ColumnName,
    c.DataType,
    CASE WHEN c.Template IS NOT NULL AND LEN(c.Template) > 0 THEN 1 ELSE 0 END AS HasTemplate
FROM DialogColumn c
JOIN DialogTable t ON c.UID_DialogTable = t.UID_DialogTable
ORDER BY t.TableName, c.ColumnName
"@

$columnRows = @(Invoke-SchemaQuery -Sql $columnsSql)
Write-Host ("  {0} columns found." -f $columnRows.Count)

$columnsList = New-Object 'System.Collections.Generic.List[object]'
foreach ($r in $columnRows) {
    $columnsList.Add([pscustomobject]@{
        table_name     = [string]$r.TableName
        column_name    = [string]$r.ColumnName
        column_uid     = [string]$r.UID_DialogColumn
        data_type_hint = [string]$r.DataType
        has_template   = ([int]$r.HasTemplate -eq 1)
    })
}
$columns = $columnsList.ToArray()

# ---------------------------------------------------------------------------
# Fetch FK relations
# ---------------------------------------------------------------------------
$fkRelationsList = New-Object 'System.Collections.Generic.List[object]'

if ($fkTableName) {
    Write-Host ("Fetching FK relations from '{0}'..." -f $fkTableName)

    $fkSql = switch ($fkTableName) {
        "QBMRelation" {
@"
SELECT
    ct.TableName  AS ChildTable,
    cc.ColumnName AS ChildColumn,
    pt.TableName  AS ParentTable,
    pc.ColumnName AS ParentColumn
FROM QBMRelation fk
JOIN DialogColumn cc ON fk.UID_ChildColumn  = cc.UID_DialogColumn
JOIN DialogColumn pc ON fk.UID_ParentColumn = pc.UID_DialogColumn
JOIN DialogTable  ct ON cc.UID_DialogTable   = ct.UID_DialogTable
JOIN DialogTable  pt ON pc.UID_DialogTable   = pt.UID_DialogTable
ORDER BY ct.TableName, cc.ColumnName
"@
        }
        "ForeignKey" {
@"
SELECT
    ct.TableName  AS ChildTable,
    cc.ColumnName AS ChildColumn,
    pt.TableName  AS ParentTable,
    pc.ColumnName AS ParentColumn
FROM ForeignKey fk
JOIN DialogColumn cc ON fk.UID_ChildColumn  = cc.UID_DialogColumn
JOIN DialogColumn pc ON fk.UID_ParentColumn = pc.UID_DialogColumn
JOIN DialogTable  ct ON cc.UID_DialogTable   = ct.UID_DialogTable
JOIN DialogTable  pt ON pc.UID_DialogTable   = pt.UID_DialogTable
ORDER BY ct.TableName, cc.ColumnName
"@
        }
        "ColumnRelation" {
@"
SELECT
    ct.TableName  AS ChildTable,
    cc.ColumnName AS ChildColumn,
    pt.TableName  AS ParentTable,
    pc.ColumnName AS ParentColumn
FROM ColumnRelation cr
JOIN DialogColumn cc ON cr.UID_ChildColumn  = cc.UID_DialogColumn
JOIN DialogColumn pc ON cr.UID_ParentColumn = pc.UID_DialogColumn
JOIN DialogTable  ct ON cc.UID_DialogTable   = ct.UID_DialogTable
JOIN DialogTable  pt ON pc.UID_DialogTable   = pt.UID_DialogTable
ORDER BY ct.TableName, cc.ColumnName
"@
        }
        default {
@"
SELECT
    ct.TableName  AS ChildTable,
    cc.ColumnName AS ChildColumn,
    pt.TableName  AS ParentTable,
    pc.ColumnName AS ParentColumn
FROM DialogColumn_FK fk
JOIN DialogColumn cc ON fk.UID_ChildColumn  = cc.UID_DialogColumn
JOIN DialogColumn pc ON fk.UID_ParentColumn = pc.UID_DialogColumn
JOIN DialogTable  ct ON cc.UID_DialogTable   = ct.UID_DialogTable
JOIN DialogTable  pt ON pc.UID_DialogTable   = pt.UID_DialogTable
ORDER BY ct.TableName, cc.ColumnName
"@
        }
    }

    try {
        $fkRows = @(Invoke-SchemaQuery -Sql $fkSql)
        Write-Host ("  {0} FK relations found." -f $fkRows.Count)

        foreach ($r in $fkRows) {
            $fkRelationsList.Add([pscustomobject]@{
                child_table   = [string]$r.ChildTable
                child_column  = [string]$r.ChildColumn
                parent_table  = [string]$r.ParentTable
                parent_column = [string]$r.ParentColumn
            })
        }
    }
    catch {
        Write-Warning ("FK query failed: {0}" -f $_.Exception.Message)
    }
}
else {
    Write-Warning "No FK metadata table detected. fk_relations will be empty."
}

# ---------------------------------------------------------------------------
# Build indexes
# ---------------------------------------------------------------------------
function Build-SchemaIndexes {
    <#
    .SYNOPSIS
    Builds lookup indexes from an array of FK relation objects.
    Returns a hashtable with keys ColumnToFkTarget and ParentToChildren.
    Extracted as a named function so it can be loaded and tested without a live DB.
    #>
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [object[]]$FkRelations
    )

    # column_to_fk_target: "<ChildTable>.<ChildColumn>" -> { parent_table, parent_column }
    $columnToFkTarget = [ordered]@{}
    foreach ($fk in $FkRelations) {
        $key = ("{0}.{1}" -f $fk.child_table, $fk.child_column)
        $columnToFkTarget[$key] = [pscustomobject]@{
            parent_table  = $fk.parent_table
            parent_column = $fk.parent_column
        }
    }

    # parent_to_children: "<ParentTable>.<ParentColumn>" -> [{ child_table, child_column }, ...]
    $parentToChildren = [ordered]@{}
    foreach ($fk in $FkRelations) {
        $key = ("{0}.{1}" -f $fk.parent_table, $fk.parent_column)
        if (-not $parentToChildren.Contains($key)) {
            $parentToChildren[$key] = New-Object System.Collections.Generic.List[object]
        }
        $parentToChildren[$key].Add([pscustomobject]@{
            child_table  = $fk.child_table
            child_column = $fk.child_column
        })
    }

    # Convert lists to arrays for JSON serialisation
    $parentToChildrenFinal = [ordered]@{}
    foreach ($k in $parentToChildren.Keys) {
        $parentToChildrenFinal[$k] = $parentToChildren[$k].ToArray()
    }

    return @{
        ColumnToFkTarget = $columnToFkTarget
        ParentToChildren = $parentToChildrenFinal
    }
}

Write-Host "Building lookup indexes..."

$fkRelations = $fkRelationsList.ToArray()
$indexes = Build-SchemaIndexes -FkRelations $fkRelations
$columnToFkTarget    = $indexes.ColumnToFkTarget
$parentToChildrenFinal = $indexes.ParentToChildren

# ---------------------------------------------------------------------------
# Assemble snapshot
# ---------------------------------------------------------------------------
$sourceMode = if ($AccessMode -eq "Direct") { "Direct" } elseif ($AccessMode -eq "Session") { "Session" } else { "Auto" }

$snapshot = [ordered]@{
    snapshot_metadata = [ordered]@{
        generated_at          = (Get-Date -Format "o")
        environment_fingerprint = $envFingerprint
        source_mode           = $sourceMode
        project_config_path   = $settings.ProjectConfigPath
        fk_metadata_table     = if ($fkTableName) { $fkTableName } else { $null }
    }
    tables     = @($tables)
    columns    = @($columns)
    fk_relations = @($fkRelations)
    indexes    = [ordered]@{
        column_to_fk_target = $columnToFkTarget
        parent_to_children  = $parentToChildrenFinal
    }
}

# ---------------------------------------------------------------------------
# Write output
# ---------------------------------------------------------------------------
$json = $snapshot | ConvertTo-Json -Depth 10
Set-Content -LiteralPath $snapshotPath -Value $json -Encoding UTF8

Write-Host ""
Write-Host ("Schema snapshot written to: {0}" -f $snapshotPath)
Write-Host ("  Tables    : {0}" -f $tables.Count)
Write-Host ("  Columns   : {0}" -f $columns.Count)
Write-Host ("  FK edges  : {0}" -f $fkRelations.Count)
exit 0
