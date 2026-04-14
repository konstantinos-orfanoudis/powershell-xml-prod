Set-StrictMode -Version Latest

function Get-OneImAuditFirstExistingPath {
    param(
        [Parameter()]
        [string[]]$Candidates
    )

    foreach ($candidate in @($Candidates)) {
        if ([string]::IsNullOrWhiteSpace($candidate)) {
            continue
        }

        try {
            $fullPath = [System.IO.Path]::GetFullPath($candidate)
        }
        catch {
            continue
        }

        if (Test-Path -LiteralPath $fullPath) {
            return $fullPath
        }
    }

    return $null
}

# Resolve portable defaults from environment variables first, then from common
# locations under the current user's profile.
$script:DefaultTestAssistRoot = Get-OneImAuditFirstExistingPath -Candidates @(
    $env:ONEIM_TESTASSIST_ROOT,
    (Join-Path $env:USERPROFILE "Desktop\DeploymentManager-4.0.6-beta\TestAssist-distribute\TestAssist-1.2.2")
)

$script:DefaultProjectConfigPath = Get-OneImAuditFirstExistingPath -Candidates @(
    $env:ONEIM_PROJECT_CONFIG_PATH,
    (Join-Path $env:USERPROFILE "Documents\DMWorkshop2\Config\Example\projectConfig.xml")
)

function Get-OneImAuditSessionSettings {
    <#
    .SYNOPSIS
    Returns resolved TestAssist root and project config paths.
    Falls back to ONEIM_TESTASSIST_ROOT / ONEIM_PROJECT_CONFIG_PATH and then
    to common locations under the current user's profile.
    #>
    param(
        [Parameter()]
        [string]$TestAssistRoot,

        [Parameter()]
        [string]$ProjectConfigPath
    )

    $resolvedTestAssistRoot = if (-not [string]::IsNullOrWhiteSpace($TestAssistRoot)) {
        [System.IO.Path]::GetFullPath($TestAssistRoot)
    }
    else {
        $script:DefaultTestAssistRoot
    }

    $resolvedProjectConfigPath = if (-not [string]::IsNullOrWhiteSpace($ProjectConfigPath)) {
        [System.IO.Path]::GetFullPath($ProjectConfigPath)
    }
    else {
        $script:DefaultProjectConfigPath
    }

    return [pscustomobject]@{
        TestAssistRoot    = $resolvedTestAssistRoot
        ProjectConfigPath = $resolvedProjectConfigPath
        SetupPath         = if (-not [string]::IsNullOrWhiteSpace($resolvedTestAssistRoot)) { Join-Path $resolvedTestAssistRoot "Setup.ps1" } else { $null }
        ModulePath        = if (-not [string]::IsNullOrWhiteSpace($resolvedTestAssistRoot)) { Join-Path $resolvedTestAssistRoot "Intragen.TestAssist.psd1" } else { $null }
    }
}

function Get-OneImAuditProjectConfig {
    <#
    .SYNOPSIS
    Parses projectConfig.xml and returns connection metadata.
    Password is read from the DM_PASS environment variable when not present in the file.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$ProjectConfigPath
    )

    if ([string]::IsNullOrWhiteSpace($ProjectConfigPath)) {
        throw "Project config path was not provided and no default could be resolved. Pass -ProjectConfigPath or set ONEIM_PROJECT_CONFIG_PATH."
    }

    if (-not (Test-Path -LiteralPath $ProjectConfigPath)) {
        throw "Project config not found at '$ProjectConfigPath'."
    }

    [xml]$xml = Get-Content -LiteralPath $ProjectConfigPath -Raw

    $dataSource = $null
    $database   = $null
    $password   = $null

    # Use GetElementsByTagName (namespace-agnostic) rather than XPath //name which
    # fails silently when the document has a default namespace declaration.
    $dsNodes = $xml.GetElementsByTagName("dataSource")
    if ($dsNodes.Count -gt 0) {
        $dataSource = [string]$dsNodes.Item(0).InnerText
    }

    $dbNodes = $xml.GetElementsByTagName("database")
    if ($dbNodes.Count -gt 0) {
        $database = [string]$dbNodes.Item(0).InnerText
    }

    $pwNodes = $xml.GetElementsByTagName("Password")
    if ($pwNodes.Count -eq 0) { $pwNodes = $xml.GetElementsByTagName("password") }
    if ($pwNodes.Count -gt 0 -and -not [string]::IsNullOrWhiteSpace($pwNodes.Item(0).InnerText)) {
        $password = [string]$pwNodes.Item(0).InnerText
    }
    else {
        $password = $env:DM_PASS
    }

    return [pscustomobject]@{
        DataSource = $dataSource
        Database   = $database
        Password   = $password
    }
}

function Get-OneImAuditConnectionString {
    param(
        [Parameter(Mandatory)]
        [object]$ProjectConfig
    )

    $dsRaw = [string]$ProjectConfig.DataSource
    if ([string]::IsNullOrWhiteSpace($dsRaw)) {
        throw "DataSource is empty in the project config."
    }

    # If datasource already looks like a full connection string, return it
    if ($dsRaw -match "(?i)(Server|Data Source|Initial Catalog)\s*=") {
        return $dsRaw
    }

    # Build minimal connection string from parsed fields
    $cs = "Data Source={0};" -f $dsRaw
    if (-not [string]::IsNullOrWhiteSpace([string]$ProjectConfig.Database)) {
        $cs += "Initial Catalog={0};" -f $ProjectConfig.Database
    }

    if (-not [string]::IsNullOrWhiteSpace([string]$ProjectConfig.Password)) {
        $cs += "Integrated Security=False;User ID=sa;Password={0};" -f $ProjectConfig.Password
    }
    else {
        $cs += "Integrated Security=True;"
    }

    return $cs
}

function Ensure-OneImAuditSession {
    <#
    .SYNOPSIS
    Bootstraps a TestAssist session idempotently.
    Returns the session object or throws if setup fails.
    #>
    param(
        [Parameter(Mandatory)]
        [object]$Settings,

        [Parameter(Mandatory)]
        [string]$ProjectConfigPath
    )

    if ([string]::IsNullOrWhiteSpace([string]$Settings.TestAssistRoot)) {
        throw "TestAssist root was not provided and no default could be resolved. Pass -TestAssistRoot or set ONEIM_TESTASSIST_ROOT."
    }

    if ([string]::IsNullOrWhiteSpace($ProjectConfigPath)) {
        throw "Project config path was not provided. Pass -ProjectConfigPath or set ONEIM_PROJECT_CONFIG_PATH."
    }

    if (-not (Test-Path -LiteralPath $Settings.SetupPath)) {
        throw "TestAssist Setup.ps1 not found at '$($Settings.SetupPath)'. Verify -TestAssistRoot."
    }

    if (-not (Test-Path -LiteralPath $Settings.ModulePath)) {
        throw "Intragen.TestAssist.psd1 not found at '$($Settings.ModulePath)'. Verify -TestAssistRoot."
    }

    # Run setup and import the module (idempotent — Setup.ps1 is safe to re-run)
    . $Settings.SetupPath
    Import-Module $Settings.ModulePath -Force -Global

    $config = Get-OneImAuditProjectConfig -ProjectConfigPath $ProjectConfigPath
    $password = if ([string]::IsNullOrWhiteSpace([string]$config.Password)) { $null } else { $config.Password }

    # Start-QConsole uses no parameters — Setup.ps1 already configures the environment
    # (DM_HOME, DM_PASS etc.). We only need to ensure DM_PASS is set when a password
    # was found in the config and the env var is not already populated.
    if ($password -and [string]::IsNullOrWhiteSpace($env:DM_PASS)) {
        $env:DM_PASS = $password
    }

    $session = Start-QConsole
    return $session
}

function Invoke-OneImAuditSqlQuery {
    <#
    .SYNOPSIS
    Runs a SQL query against the OneIM database.
    Uses Find-QSql (TestAssist session) in Session mode, or ADO.NET in Direct mode.
    Auto mode tries Direct first and falls back to Session.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Query,

        [Parameter()]
        [ValidateSet("Auto", "Session", "Direct")]
        [string]$AccessMode = "Auto",

        [Parameter()]
        [object]$Settings,

        [Parameter()]
        [string]$ProjectConfigPath
    )

    if ($AccessMode -eq "Session" -or $AccessMode -eq "Auto") {
        try {
            $results = Find-QSql -Dictionary -Query $Query
            return @($results)
        }
        catch {
            if ($AccessMode -eq "Session") {
                throw
            }
            # Auto: fall through to Direct
        }
    }

    # Direct SQL via ADO.NET
    $config = Get-OneImAuditProjectConfig -ProjectConfigPath $ProjectConfigPath
    $connectionString = Get-OneImAuditConnectionString -ProjectConfig $config

    # System.Data.SqlClient does not support the multi-word keyword 'Trust Server Certificate'
    # used by Microsoft.Data.SqlClient. Normalise it to the equivalent single-word form.
    $connectionString = $connectionString -replace '(?i)Trust\s+Server\s+Certificate\s*=', 'TrustServerCertificate='

    $connection = New-Object System.Data.SqlClient.SqlConnection($connectionString)
    $connection.Open()

    try {
        $command = $connection.CreateCommand()
        $command.CommandText = $Query
        $command.CommandTimeout = 180

        $adapter = New-Object System.Data.SqlClient.SqlDataAdapter($command)
        $table = New-Object System.Data.DataTable
        $null = $adapter.Fill($table)

        $rows = New-Object System.Collections.Generic.List[object]
        foreach ($row in $table.Rows) {
            $obj = [ordered]@{}
            foreach ($col in $table.Columns) {
                $obj[$col.ColumnName] = $row[$col.ColumnName]
            }
            $rows.Add([pscustomobject]$obj)
        }

        return @($rows.ToArray())
    }
    finally {
        $connection.Close()
        $connection.Dispose()
    }
}

function Get-OneImAuditDmvSnapshot {
    <#
    .SYNOPSIS
    Captures a point-in-time snapshot of SQL DMV metrics for the current session.

    Returns an object with:
      logical_reads   — cumulative logical reads for the current session (sys.dm_exec_sessions)
      lck_wait_count  — cumulative server-wide LCK* wait count (sys.dm_os_wait_stats)
      lck_wait_ms     — cumulative server-wide LCK* wait time in milliseconds

    Use Get-OneImAuditDmvDelta to compute per-run deltas between two snapshots.
    #>
    param(
        [Parameter()]
        [ValidateSet("Auto", "Session", "Direct")]
        [string]$AccessMode = "Auto",

        [Parameter()]
        [object]$Settings,

        [Parameter()]
        [string]$ProjectConfigPath
    )

    $sessionQuery = "SELECT logical_reads FROM sys.dm_exec_sessions WHERE session_id = @@SPID"
    $lckQuery     = @"
SELECT ISNULL(SUM(waiting_tasks_count),0) AS lck_wait_count,
       ISNULL(SUM(wait_time_ms),0)        AS lck_wait_ms
FROM   sys.dm_os_wait_stats
WHERE  wait_type LIKE 'LCK%'
"@

    $sessionRows = Invoke-OneImAuditSqlQuery -Query $sessionQuery `
        -AccessMode $AccessMode -Settings $Settings -ProjectConfigPath $ProjectConfigPath
    $lckRows     = Invoke-OneImAuditSqlQuery -Query $lckQuery `
        -AccessMode $AccessMode -Settings $Settings -ProjectConfigPath $ProjectConfigPath

    $logicalReads  = if ($sessionRows.Count -gt 0) { [long]$sessionRows[0].logical_reads } else { 0L }
    $lckWaitCount  = if ($lckRows.Count    -gt 0) { [long]$lckRows[0].lck_wait_count }    else { 0L }
    $lckWaitMs     = if ($lckRows.Count    -gt 0) { [long]$lckRows[0].lck_wait_ms }       else { 0L }

    return [pscustomobject]@{
        logical_reads  = $logicalReads
        lck_wait_count = $lckWaitCount
        lck_wait_ms    = $lckWaitMs
    }
}

function Get-OneImAuditDmvDelta {
    <#
    .SYNOPSIS
    Computes per-run SQL DMV metric deltas between two snapshots.

    Returns:
      logical_reads_per_run   — logical reads added per measured run
      lck_wait_count_per_run  — LCK waits added per measured run
      lck_wait_ms_per_run     — LCK wait time (ms) added per measured run

    RunCount of 0 or negative returns zeros for all fields.
    #>
    param(
        [Parameter(Mandatory)]
        [object]$Before,

        [Parameter(Mandatory)]
        [object]$After,

        [Parameter(Mandatory)]
        [int]$RunCount
    )

    if ($RunCount -le 0) {
        return [pscustomobject]@{
            logical_reads_per_run  = 0L
            lck_wait_count_per_run = 0L
            lck_wait_ms_per_run    = 0L
        }
    }

    $deltaLogicalReads = [Math]::Max(0L, [long]$After.logical_reads  - [long]$Before.logical_reads)
    $deltaLckCount     = [Math]::Max(0L, [long]$After.lck_wait_count - [long]$Before.lck_wait_count)
    $deltaLckMs        = [Math]::Max(0L, [long]$After.lck_wait_ms    - [long]$Before.lck_wait_ms)

    return [pscustomobject]@{
        logical_reads_per_run  = [Math]::Round($deltaLogicalReads / $RunCount, 0)
        lck_wait_count_per_run = [Math]::Round($deltaLckCount     / $RunCount, 0)
        lck_wait_ms_per_run    = [Math]::Round($deltaLckMs        / $RunCount, 0)
    }
}

Export-ModuleMember -Function `
    Get-OneImAuditSessionSettings, `
    Get-OneImAuditProjectConfig, `
    Get-OneImAuditConnectionString, `
    Ensure-OneImAuditSession, `
    Invoke-OneImAuditSqlQuery, `
    Get-OneImAuditDmvSnapshot, `
    Get-OneImAuditDmvDelta
