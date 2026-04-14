Set-StrictMode -Version Latest

function ConvertTo-OneImAuditDetectorInlineText {
    param(
        [Parameter()]
        [string[]]$Segments
    )

    return ((@($Segments) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) -join "`n")
}

function Get-OneImAuditSec100Finding {
    param(
        [Parameter(Mandatory)]
        [string]$StatementText,

        [Parameter()]
        [string[]]$PriorContextLines = @(),

        [Parameter(Mandatory)]
        [string]$FilePath,

        [Parameter(Mandatory)]
        [string]$RelativePath,

        [Parameter(Mandatory)]
        [int]$LineNumber,

        [Parameter(Mandatory)]
        [hashtable]$RuleCatalog,

        [Parameter(Mandatory)]
        [hashtable]$SourceLookup
    )

    if (-not $RuleCatalog.ContainsKey("SEC100")) { return $null }

    $normalized = ConvertTo-OneImAuditDetectorInlineText -Segments @($PriorContextLines + @($StatementText))
    if ($normalized -notmatch '(?i)\b(select\s+.+\s+from|insert\s+into|update\s+\w+|delete\s+from)\b') { return $null }
    if ($normalized -notmatch '(&|\$")') { return $null }
    if ($normalized -match '(?i)\b(UidComparison|Comparison|SqlFormatter|DialogQuery|Query\.From|CreateParameter|Parameters\.Add)\b') { return $null }

    return New-OneImAuditFinding -RuleId "SEC100" -RuleCatalog $RuleCatalog -SourceLookup $SourceLookup -FilePath $FilePath -RelativePath $RelativePath -Line $LineNumber `
        -Evidence ($StatementText.Trim()) `
        -TriggeringScenario "Dynamic query construction that mixes SQL text with variables is hard to validate and can become injectable." `
        -Remediation "Move variable data into parameters or OneIM-safe query builders instead of concatenating SQL or filter text directly." `
        -TestIdeas @(
            "Run the query path with delimiter-heavy input and verify parameters, not raw text, carry the variable data.",
            "Check the generated SQL in System Debugger and confirm user data is no longer embedded inside the statement text."
        )
}

function Get-OneImAuditSec131Finding {
    param(
        [Parameter(Mandatory)]
        [string]$StatementText,

        [Parameter()]
        [string[]]$PriorContextLines = @(),

        [Parameter(Mandatory)]
        [string]$FilePath,

        [Parameter(Mandatory)]
        [string]$RelativePath,

        [Parameter(Mandatory)]
        [int]$LineNumber,

        [Parameter(Mandatory)]
        [hashtable]$RuleCatalog,

        [Parameter(Mandatory)]
        [hashtable]$SourceLookup
    )

    if (-not $RuleCatalog.ContainsKey("SEC131")) { return $null }

    $normalized = ConvertTo-OneImAuditDetectorInlineText -Segments @($PriorContextLines + @($StatementText))
    if ($normalized -notmatch '(?i)\b(GetAsync|PostAsync|SendAsync|DownloadString|DownloadData|OpenRead|Create)\s*\(') { return $null }
    if ($normalized -notmatch '(?i)\b(url|uri|endpoint)\b') { return $null }

    $hasAllowlistHint = ($normalized -match '(?i)\b(allowlist|approved(host|uri|url)|trusted(host|uri|url)|baseUri|knownEndpoint)\b')
    $confidenceScore = if ($hasAllowlistHint) { 60 } else { 70 }
    $scenario = if ($hasAllowlistHint) {
        "Variable-driven outbound endpoints deserve SSRF review even when an allowlist or base-URI concept is present, because the constraint is not fully visible on this statement."
    } else {
        "Variable-driven outbound endpoints deserve SSRF review when the URL source is not obviously constrained."
    }

    return New-OneImAuditFinding -RuleId "SEC131" -RuleCatalog $RuleCatalog -SourceLookup $SourceLookup -FilePath $FilePath -RelativePath $RelativePath -Line $LineNumber `
        -Evidence ($StatementText.Trim()) `
        -TriggeringScenario $scenario `
        -Remediation "Validate the destination against an allowlist, normalize the URI before issuing the request, and keep redirect handling explicit." `
        -TestIdeas @(
            "Exercise the request path with internal-host and redirect-style input and confirm it is blocked.",
            "Verify the code accepts only approved hosts or base URIs in the final request target."
        ) `
        -Extra @{ confidence_score = $confidenceScore }
}

function Get-OneImAuditSec140Finding {
    param(
        [Parameter(Mandatory)]
        [string]$StatementText,

        [Parameter()]
        [string[]]$PriorContextLines = @(),

        [Parameter(Mandatory)]
        [string]$FilePath,

        [Parameter(Mandatory)]
        [string]$RelativePath,

        [Parameter(Mandatory)]
        [int]$LineNumber,

        [Parameter(Mandatory)]
        [hashtable]$RuleCatalog,

        [Parameter(Mandatory)]
        [hashtable]$SourceLookup
    )

    if (-not $RuleCatalog.ContainsKey("SEC140")) { return $null }

    $normalized = ConvertTo-OneImAuditDetectorInlineText -Segments @($PriorContextLines + @($StatementText))
    if ($normalized -notmatch '(?i)\b(File\.(ReadAllText|ReadAllBytes|WriteAllText|WriteAllBytes|AppendAllText)|Directory\.(CreateDirectory|Delete)|FileStream|StreamReader|StreamWriter)\b') { return $null }

    $looksVariableDriven = ($normalized -notmatch '"[^"]+"' -or $normalized -match '(?i)\b(path|file|folder|directory|target|output|input|name)\b')
    if (-not $looksVariableDriven) { return $null }

    $hasNormalizationHint = ($normalized -match '(?i)\b(Path\.(Combine|GetFullPath|Join)|Resolve-Path|Normalize)\b')
    $confidenceScore = if ($hasNormalizationHint) { 60 } else { 70 }
    $scenario = if ($hasNormalizationHint) {
        "File-system work still deserves traversal review because the path is variable-driven, even though the statement shows a normalization helper."
    } else {
        "File or directory operations with variable-driven paths deserve path traversal and overwrite review."
    }

    return New-OneImAuditFinding -RuleId "SEC140" -RuleCatalog $RuleCatalog -SourceLookup $SourceLookup -FilePath $FilePath -RelativePath $RelativePath -Line $LineNumber `
        -Evidence ($StatementText.Trim()) `
        -TriggeringScenario $scenario `
        -Remediation "Normalize the path against an approved root, validate file names, and keep unsafe input away from file-system APIs." `
        -TestIdeas @(
            "Pass traversal-like path input and verify the code refuses to read or write outside the intended root.",
            "Verify the final path is rooted under the expected working directory before the file-system call runs."
        ) `
        -Extra @{ confidence_score = $confidenceScore }
}

function Get-OneImAuditSec150Finding {
    param(
        [Parameter(Mandatory)]
        [string]$StatementText,

        [Parameter()]
        [string[]]$PriorContextLines = @(),

        [Parameter(Mandatory)]
        [string]$FilePath,

        [Parameter(Mandatory)]
        [string]$RelativePath,

        [Parameter(Mandatory)]
        [int]$LineNumber,

        [Parameter(Mandatory)]
        [hashtable]$RuleCatalog,

        [Parameter(Mandatory)]
        [hashtable]$SourceLookup
    )

    if (-not $RuleCatalog.ContainsKey("SEC150")) { return $null }

    $normalized = ConvertTo-OneImAuditDetectorInlineText -Segments @($PriorContextLines + @($StatementText))
    if ($normalized -notmatch '(?i)\b(XmlDocument|XmlReader|XmlReaderSettings|LoadXml|InnerXml)\b') { return $null }

    $hasSafeMarkers = ($normalized -match '(?i)\b(DtdProcessing\.(Prohibit|Ignore)|XmlResolver\s*=\s*Nothing)\b')
    if ($hasSafeMarkers) { return $null }

    return New-OneImAuditFinding -RuleId "SEC150" -RuleCatalog $RuleCatalog -SourceLookup $SourceLookup -FilePath $FilePath -RelativePath $RelativePath -Line $LineNumber `
        -Evidence ($StatementText.Trim()) `
        -TriggeringScenario "XML parsing and XML text injection need explicit XXE-safe and DTD-safe settings when safe markers are not visible nearby." `
        -Remediation "Use secure XML reader settings, keep external entity resolution disabled, and review any XML text loaded from variable input." `
        -TestIdeas @(
            "Load XML with external-entity style payloads in a safe test harness and confirm the parser refuses them.",
            "Set DtdProcessing and XmlResolver explicitly, then verify the rule no longer fires."
        )
}

Export-ModuleMember -Function `
    Get-OneImAuditSec100Finding, `
    Get-OneImAuditSec131Finding, `
    Get-OneImAuditSec140Finding, `
    Get-OneImAuditSec150Finding
