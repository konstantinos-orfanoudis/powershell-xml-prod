[CmdletBinding()]
param(
    [Parameter()]
    [string]$ExtractedDocRoot = "C:\Users\aiuser\Documents\GitHub\powershell-xml-prod\New_Design_PS\dist\OneIM_QBM_ApiServer_extracted",

    [Parameter()]
    [string]$OutputPath,

    [Parameter()]
    [string]$AuthorityName = "One Identity API Server CHM (local)"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$scriptRoot = Split-Path -Parent $PSCommandPath
$skillRoot = Split-Path -Parent $scriptRoot
$resolvedDocRoot = [System.IO.Path]::GetFullPath($ExtractedDocRoot)
$resolvedOutputPath = if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    [System.IO.Path]::GetFullPath((Join-Path $skillRoot "assets\apiserver-doc-index.json"))
} else {
    [System.IO.Path]::GetFullPath($OutputPath)
}

$hhcPath = Join-Path $resolvedDocRoot "OneIM_QBM_ApiServer.hhc"
if (-not (Test-Path -LiteralPath $hhcPath)) {
    throw "CHM table of contents not found at '$hhcPath'."
}

$aliasByGuid = @{
    "27aaa313-bd2d-3e2c-1693-021a3b36daa1" = "oneim-apiserver-observable-event-stream-response"
    "cb218e87-815d-69dd-37b2-b9059d1a8211" = "oneim-apiserver-observable-event-stream-awaittasks"
    "d34ece1d-52e6-cf25-15eb-d89821eedb7e" = "oneim-apiserver-cache-response"
    "f7efd18c-a4ca-698c-f511-35c10fcf9d60" = "oneim-apiserver-get-request-ip-address"
    "e340859f-8891-7cee-7036-1e0b89c160d9" = "oneim-apiserver-request-validator"
    "dfe75fcb-0c96-48c4-c588-825b321d4165" = "oneim-apiserver-request-validator-validateasync"
    "0dfe9c43-8e85-96e5-8c45-80dc6a07cf67" = "oneim-apiserver-entity-write-filter"
    "05dfbc80-2522-b891-bdc5-b4643ded2fed" = "oneim-apiserver-entity-write-filter-checkchangesasync"
    "732d5a02-ce20-38b0-f222-e7ad2e32ce1a" = "oneim-apiserver-server-level-config"
    "fc03d568-e26a-e68b-13cb-7739f5bd15a0" = "oneim-apiserver-include-all-exception-info"
    "cd7dcf0e-ec84-73d2-88f0-165dcb8a8988" = "oneim-apiserver-enable-endpoint-security-permission-check"
    "6636b2c5-fd96-35c2-5b98-6371e6aa8638" = "oneim-apiserver-cors-origins"
    "5981da10-2588-a606-fbbf-db40860ac68b" = "oneim-apiserver-auth-tokens-enabled"
    "45b72d9d-d375-0d78-564b-a3f4c5893452" = "oneim-apiserver-auth-tokens-lifetime-minutes"
    "9b275f78-14fe-d176-6eef-e339464d81b0" = "oneim-apiserver-do-not-sort-on-api-server"
    "108fc7c6-8bbd-2821-8c36-c127c9c938fe" = "oneim-apiserver-with-validator"
}

function Get-DocMetaValue {
    param(
        [Parameter(Mandatory)]
        [string]$Html,

        [Parameter(Mandatory)]
        [string]$Name
    )

    $match = [regex]::Match($Html, ('(?is)<meta\s+name="{0}"\s+content="(?<value>[^"]*)"' -f [regex]::Escape($Name)))
    if ($match.Success) {
        return [System.Net.WebUtility]::HtmlDecode([string]$match.Groups["value"].Value).Trim()
    }

    return ""
}

function Get-FirstHtmlTitle {
    param(
        [Parameter(Mandatory)]
        [string]$Html
    )

    $match = [regex]::Match($Html, '(?is)<title>(?<value>.*?)</title>')
    if ($match.Success) {
        return [System.Net.WebUtility]::HtmlDecode([string]$match.Groups["value"].Value).Trim()
    }

    return ""
}

function New-SourceId {
    param(
        [Parameter(Mandatory)]
        [string]$GuidValue,

        [Parameter(Mandatory)]
        [string]$Title
    )

    if ($aliasByGuid.ContainsKey($GuidValue)) {
        return $aliasByGuid[$GuidValue]
    }

    $slug = ($Title.ToLowerInvariant() -replace '[^a-z0-9]+', '-' -replace '(^-+|-+$)', '')
    if ([string]::IsNullOrWhiteSpace($slug)) {
        return ("oneim-apiserver-{0}" -f $GuidValue.ToLowerInvariant())
    }

    return ("oneim-apiserver-{0}-{1}" -f $slug, $GuidValue.Substring(0, 8).ToLowerInvariant())
}

$hhcRaw = Get-Content -LiteralPath $hhcPath -Raw
$tocMatches = [regex]::Matches(
    $hhcRaw,
    '(?is)<OBJECT\s+type="text/sitemap">\s*<param\s+name="Name"\s+value="(?<name>[^"]*)">\s*<param\s+name="Local"\s+value="(?<local>[^"]*)">\s*</OBJECT>'
)

$sources = New-Object 'System.Collections.Generic.List[object]'
$seenSourceIds = @{}

foreach ($match in $tocMatches) {
    $name = [System.Net.WebUtility]::HtmlDecode([string]$match.Groups["name"].Value).Trim()
    $relativeLocal = [System.Net.WebUtility]::HtmlDecode([string]$match.Groups["local"].Value).Trim()
    if ([string]::IsNullOrWhiteSpace($relativeLocal) -or -not $relativeLocal.EndsWith(".htm", [System.StringComparison]::OrdinalIgnoreCase)) {
        continue
    }

    $resolvedLocalPath = [System.IO.Path]::GetFullPath((Join-Path $resolvedDocRoot $relativeLocal))
    if (-not (Test-Path -LiteralPath $resolvedLocalPath)) {
        continue
    }

    $html = Get-Content -LiteralPath $resolvedLocalPath -Raw
    $title = Get-FirstHtmlTitle -Html $html
    if ([string]::IsNullOrWhiteSpace($title)) {
        $title = $name
    }

    $description = Get-DocMetaValue -Html $html -Name "Description"
    $container = Get-DocMetaValue -Html $html -Name "container"
    $helpId = Get-DocMetaValue -Html $html -Name "Microsoft.Help.Id"
    $guidValue = Get-DocMetaValue -Html $html -Name "guid"
    if ([string]::IsNullOrWhiteSpace($guidValue)) {
        $guidValue = [System.IO.Path]::GetFileNameWithoutExtension($resolvedLocalPath)
    }

    $sourceId = New-SourceId -GuidValue $guidValue -Title $title
    if ($seenSourceIds.ContainsKey($sourceId)) {
        continue
    }

    $seenSourceIds[$sourceId] = $true
    $sources.Add([pscustomobject]@{
            id = $sourceId
            family = "oneim-apiserver-local"
            title = $title
            authority = $AuthorityName
            url = ([System.Uri]::new($resolvedLocalPath)).AbsoluteUri
            local_path = $resolvedLocalPath
            docset_root = $resolvedDocRoot
            toc_name = $name
            description = $description
            namespace = $container
            help_id = $helpId
            guid = $guidValue
            relative_local = ($relativeLocal -replace '/', '\')
        })
}

$outputObject = [ordered]@{
    generated_at = (Get-Date).ToString("o")
    authority = $AuthorityName
    docset = "One Identity Manager API Server"
    docset_root = $resolvedDocRoot
    toc_path = $hhcPath
    source_count = $sources.Count
    sources = @($sources | Sort-Object id)
}

$outputDirectory = Split-Path -Parent $resolvedOutputPath
if (-not [string]::IsNullOrWhiteSpace($outputDirectory) -and -not (Test-Path -LiteralPath $outputDirectory)) {
    New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
}

$outputObject | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $resolvedOutputPath -Encoding UTF8
Write-Host ("Wrote API Server doc index with {0} sources to '{1}'." -f $sources.Count, $resolvedOutputPath)
