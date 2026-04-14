Set-StrictMode -Version Latest

$script:_concurrencyDetectorsPath = Join-Path $PSScriptRoot "OneimAudit.ConcurrencyDetectors.psm1"
$script:_apiServerDetectorsPath = Join-Path $PSScriptRoot "OneimAudit.ApiServerDetectors.psm1"
$script:_securityDetectorsPath = Join-Path $PSScriptRoot "OneimAudit.SecurityDetectors.psm1"
$script:_performanceDetectorsPath = Join-Path $PSScriptRoot "OneimAudit.PerformanceDetectors.psm1"
foreach ($moduleSpec in @(
        @{ Path = $script:_concurrencyDetectorsPath; Name = "OneimAudit.ConcurrencyDetectors" },
        @{ Path = $script:_apiServerDetectorsPath; Name = "OneimAudit.ApiServerDetectors" },
        @{ Path = $script:_securityDetectorsPath; Name = "OneimAudit.SecurityDetectors" },
        @{ Path = $script:_performanceDetectorsPath; Name = "OneimAudit.PerformanceDetectors" }
    )) {
    if (-not [string]::IsNullOrWhiteSpace($moduleSpec.Path) -and
        (Test-Path -LiteralPath $moduleSpec.Path -ErrorAction SilentlyContinue)) {
        try {
            Import-Module $moduleSpec.Path -Force -Global -ErrorAction Stop
        } catch {
            Write-Warning ("{0} could not be loaded: {1}" -f $moduleSpec.Name, $_.Exception.Message)
        }
    }
}

function Get-OneImAuditHeaderLineNumber {
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [AllowEmptyString()]
        [string[]]$Lines,

        [Parameter(Mandatory)]
        [string]$Pattern,

        [Parameter()]
        [int]$HeaderScanLines = 40
    )

    $limit = [Math]::Min($Lines.Count, $HeaderScanLines)
    for ($index = 0; $index -lt $limit; $index++) {
        if ($Lines[$index] -match $Pattern) {
            return ($index + 1)
        }
    }

    return $null
}

function Test-OneImAuditNearbyThrow {
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [AllowEmptyString()]
        [string[]]$Lines,

        [Parameter(Mandatory)]
        [int]$LineNumber,

        [Parameter()]
        [int]$LookaheadLines = 6
    )

    $startIndex = [Math]::Min($Lines.Count - 1, $LineNumber)
    $endIndex = [Math]::Min($Lines.Count - 1, $LineNumber + $LookaheadLines)
    for ($index = $startIndex; $index -le $endIndex; $index++) {
        if ($Lines[$index] -match "\bThrow\b") {
            return $true
        }
    }

    return $false
}

function Test-OneImAuditNearbyDispose {
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [AllowEmptyString()]
        [string[]]$Lines,

        [Parameter(Mandatory)]
        [int]$LineNumber,

        [Parameter()]
        [string]$VariableName,

        [Parameter()]
        [int]$LookaheadLines = 8
    )

    $startIndex = [Math]::Max(0, $LineNumber - 1)
    $endIndex = [Math]::Min($Lines.Count - 1, $LineNumber + $LookaheadLines)
    for ($index = $startIndex; $index -le $endIndex; $index++) {
        if ($Lines[$index] -match "^\s*Using\b") {
            return $true
        }

        if ($VariableName -and $Lines[$index] -match ("(?i)\b{0}\.Dispose\s*\(" -f [regex]::Escape($VariableName))) {
            return $true
        }
    }

    return $false
}

function Get-OneImAuditLoopDepthMap {
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [AllowEmptyString()]
        [string[]]$Lines
    )

    $map = @{}
    $depth = 0
    for ($index = 0; $index -lt $Lines.Count; $index++) {
        $line = $Lines[$index]
        if ($line -match "^\s*(For Each|For|While|Do While|Do Until|Do)\b") {
            $depth++
        }

        $map[$index + 1] = $depth

        if ($line -match "^\s*(Next|End While|Loop)\b") {
            $depth = [Math]::Max(0, $depth - 1)
        }
    }

    return $map
}

function Get-OneImAuditStatementRange {
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [AllowEmptyString()]
        [string[]]$Lines,

        [Parameter(Mandatory)]
        [int]$StartIndex
    )

    $endIndex = $StartIndex
    while ($endIndex -lt ($Lines.Count - 1) -and $Lines[$endIndex].TrimEnd().EndsWith("_")) {
        $endIndex++
    }

    return [pscustomobject]@{
        StartIndex = $StartIndex
        EndIndex = $endIndex
        Text = ($Lines[$StartIndex..$endIndex] -join "`n")
    }
}

function Get-OneImAuditPreviousMeaningfulLines {
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [AllowEmptyString()]
        [string[]]$Lines,

        [Parameter(Mandatory)]
        [int]$StartIndex,

        [Parameter()]
        [int]$Count = 6
    )

    $items = New-Object System.Collections.Generic.List[string]
    for ($index = $StartIndex - 1; $index -ge 0; $index--) {
        $trimmed = $Lines[$index].Trim()
        if ([string]::IsNullOrWhiteSpace($trimmed) -or $trimmed.StartsWith("'")) {
            continue
        }

        $items.Add($Lines[$index])
        if ($items.Count -ge $Count) {
            break
        }
    }

    $result = @($items.ToArray())
    [array]::Reverse($result)
    return $result
}

function Get-OneImAuditNextMeaningfulLines {
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [AllowEmptyString()]
        [string[]]$Lines,

        [Parameter(Mandatory)]
        [int]$StartIndex,

        [Parameter()]
        [int]$Count = 6
    )

    $items = New-Object System.Collections.Generic.List[string]
    for ($index = $StartIndex + 1; $index -lt $Lines.Count; $index++) {
        $trimmed = $Lines[$index].Trim()
        if ([string]::IsNullOrWhiteSpace($trimmed) -or $trimmed.StartsWith("'")) {
            continue
        }

        $items.Add($Lines[$index])
        if ($items.Count -ge $Count) {
            break
        }
    }

    return @($items.ToArray())
}

function Test-OneImAuditConditionalGuardNearby {
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [AllowEmptyString()]
        [string[]]$ContextLines
    )

    foreach ($line in @($ContextLines)) {
        $trimmed = $line.Trim()
        if ($trimmed -match "^(If|ElseIf)\b") {
            return $true
        }

        if ($trimmed -match "(?i)\b(FULLSYNC|ChangeLevels|IsChanged|String\.IsNullOrEmpty|String\.IsNullOrWhiteSpace|Entity\.State\.HasFlag|Provider\.GetValue)\b") {
            return $true
        }
    }

    return $false
}

function Get-OneImAuditTriggerWriteFields {
    param(
        [Parameter(Mandatory)]
        [string]$StatementText
    )

    $results = New-Object System.Collections.Generic.List[object]
    $seen = @{}
    $matches = [regex]::Matches($StatementText, '(?i)GetTriggerValue\("(?<field>[^"]+)"\)\.(?<kind>String|Text)')
    foreach ($match in $matches) {
        $field = [string]$match.Groups["field"].Value
        $kind = [string]$match.Groups["kind"].Value
        $key = "{0}|{1}" -f $field, $kind
        if ($seen.ContainsKey($key)) {
            continue
        }

        $seen[$key] = $true
        $results.Add([pscustomobject]@{
                Field = $field
                Kind = $kind
            })
    }

    return $results.ToArray()
}

function Test-OneImAuditTriggerFieldGuarded {
    param(
        [Parameter(Mandatory)]
        [string]$ContextText,

        [Parameter(Mandatory)]
        [string]$Field,

        [Parameter(Mandatory)]
        [string]$Kind
    )

    $escapedField = [regex]::Escape($Field)
    $patterns = @(
        "(?is)String\.IsNullOrEmpty\s*\(\s*GetTriggerValue\(""$escapedField""\)\.$Kind\s*\)",
        "(?is)String\.IsNullOrWhiteSpace\s*\(\s*GetTriggerValue\(""$escapedField""\)\.$Kind\s*\)",
        "(?is)Not\s+String\.IsNullOrEmpty\s*\(\s*GetTriggerValue\(""$escapedField""\)\.$Kind\s*\)",
        "(?is)Not\s+String\.IsNullOrWhiteSpace\s*\(\s*GetTriggerValue\(""$escapedField""\)\.$Kind\s*\)",
        "(?is)GetTriggerValue\(""$escapedField""\)\.$Kind\s*(<>|=)\s*""""",
        "(?is)""""\s*(<>|=)\s*GetTriggerValue\(""$escapedField""\)\.$Kind",
        "(?is)GetTriggerValue\(""$escapedField""\)\.$Kind\s*\.Length\s*(>|<>|=)\s*0"
    )

    foreach ($pattern in $patterns) {
        if ($ContextText -match $pattern) {
            return $true
        }
    }

    return $false
}

function Test-OneImAuditIdentifierLikeTriggerField {
    param(
        [Parameter(Mandatory)]
        [string]$Field
    )

    return ($Field -match '(?i)(^UID_|^FK\(|\bUID_[A-Za-z0-9_]+\b|XObjectKey|ObjectKey)')
}

function Normalize-OneImAuditCustomName {
    param(
        [Parameter(Mandatory)]
        [string]$Name
    )

    $normalized = $Name.Trim()
    if ($normalized.StartsWith("[") -and $normalized.EndsWith("]")) {
        $normalized = $normalized.TrimStart("[").TrimEnd("]")
    }

    return $normalized
}

function Get-OneImAuditViKeyEntry {
    param(
        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$Line
    )

    if ([string]::IsNullOrWhiteSpace($Line)) {
        return $null
    }

    $match = [regex]::Match($Line, '(?i)VI-KEY\(<Key><T>(?<type>[^<]+)</T><P>(?<key>[^<]+)</P></Key>,\s*(?<name>[^)]+)\)')
    if (-not $match.Success) {
        return $null
    }

    return [pscustomobject]@{
        Type = [string]$match.Groups["type"].Value
        Key = [string]$match.Groups["key"].Value
        Name = Normalize-OneImAuditCustomName -Name ([string]$match.Groups["name"].Value)
    }
}

function Test-OneImAuditCustomViKeyNameMismatch {
    param(
        [Parameter(Mandatory)]
        [string]$Key,

        [Parameter(Mandatory)]
        [string]$Name
    )

    return (
        $Key -match '^(?i)CCC-' -and
        (Normalize-OneImAuditCustomName -Name $Name) -notmatch '^(?i)CCC[_-]'
    )
}

function Get-OneImAuditNextRoutineDeclaration {
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [AllowEmptyString()]
        [string[]]$Lines,

        [Parameter(Mandatory)]
        [int]$StartIndex,

        [Parameter()]
        [int]$LookAhead = 20
    )

    $endIndex = [Math]::Min($Lines.Count - 1, $StartIndex + $LookAhead)
    for ($index = $StartIndex + 1; $index -le $endIndex; $index++) {
        $trimmed = $Lines[$index].Trim()
        if ([string]::IsNullOrWhiteSpace($trimmed) -or $trimmed.StartsWith("'")) {
            continue
        }

        if ($trimmed -match '(?i)VI-KEY\(') {
            break
        }

        $match = [regex]::Match($trimmed, '(?i)\b(Function|Sub)\s+(?<name>\[[^\]]+\]|[A-Za-z_][A-Za-z0-9_]*)\b')
        if ($match.Success) {
            return [pscustomobject]@{
                LineNumber = $index + 1
                Kind = [string]$match.Groups[1].Value
                Name = Normalize-OneImAuditCustomName -Name ([string]$match.Groups["name"].Value)
                LineText = $trimmed
            }
        }
    }

    return $null
}

# ---------------------------------------------------------------------------
# Per-line dispatch table (script scope — built once at module load, not per call).
# Each scriptblock is invoked with & inside the per-line loop and inherits the
# caller's scope, so $lines, $index, $lineNumber, $trimmed, $loopDepthMap,
# $findings, $seen, $potentialEnumerations, $RuleCatalog, $SourceLookup,
# $FilePath, and $RelativePath are all directly accessible.
# ---------------------------------------------------------------------------
$script:_detectionUnits = [ordered]@{

    # OIM510 + OIM511 share the $viKeyEntry computation.
    "OIM51x" = {
        $viKeyEntry = $null
        if ($RuleCatalog.ContainsKey("OIM510") -or $RuleCatalog.ContainsKey("OIM511")) {
            $viKeyEntry = Get-OneImAuditViKeyEntry -Line $trimmed
        }

        if ($RuleCatalog.ContainsKey("OIM510") -and $null -ne $viKeyEntry -and (Test-OneImAuditCustomViKeyNameMismatch -Key $viKeyEntry.Key -Name $viKeyEntry.Name)) {
            Add-OneImAuditFinding -Findings $findings -Seen $seen -Finding (
                New-OneImAuditFinding -RuleId "OIM510" -RuleCatalog $RuleCatalog -SourceLookup $SourceLookup -FilePath $FilePath -RelativePath $RelativePath -Line $lineNumber `
                    -Evidence $trimmed `
                    -TriggeringScenario "A custom VI-KEY id is paired with a script name that does not look custom-prefixed, which can mislead custom-vs-OOTB review and export handling." `
                    -Remediation "Review the script definition name in the Script Editor and keep CCC-keyed entries aligned with a 'CCC_' or 'CCC-' script name when the mismatch is not intentional." `
                    -TestIdeas @(
                        "Inspect the script entry in the OneIM Script Editor and confirm the custom key and script name are intentionally paired.",
                        "Re-export the script block and verify the VI-KEY comment still shows the intended custom-prefixed script name."
                    )
            )
        }

        if ($RuleCatalog.ContainsKey("OIM511") -and $null -ne $viKeyEntry -and $viKeyEntry.Key -match '^(?i)CCC-') {
            $routineDeclaration = Get-OneImAuditNextRoutineDeclaration -Lines $lines -StartIndex $index
            if ($null -ne $routineDeclaration -and $routineDeclaration.Name -notmatch '^(?i)CCC[_-]') {
                Add-OneImAuditFinding -Findings $findings -Seen $seen -Finding (
                    New-OneImAuditFinding -RuleId "OIM511" -RuleCatalog $RuleCatalog -SourceLookup $SourceLookup -FilePath $FilePath -RelativePath $RelativePath -Line $routineDeclaration.LineNumber `
                        -Evidence $routineDeclaration.LineText `
                        -TriggeringScenario "A custom VI-KEY id is followed by a Function or Sub declaration whose name does not look custom-prefixed, which weakens custom-script traceability during review and export handling." `
                        -Remediation "Review the declared Function or Sub name and keep CCC-keyed entries aligned with a 'CCC_' or 'CCC-' routine name when the mismatch is not intentional." `
                        -TestIdeas @(
                            "Inspect the script entry in the OneIM Script Editor and confirm the exported custom key maps to the intended Function or Sub name.",
                            "Re-export the script block and verify the routine declaration still uses the intended custom-prefixed name."
                        )
                )
            }
        }
    }

    "VB003" = {
        if ($RuleCatalog.ContainsKey("VB003") -and ($trimmed -match "(?i)\bAs\s+Object\b" -or $trimmed -match "(?i)\bCreateObject\s*\(" -or $trimmed -match "(?i)\bCallByName\s*\(")) {
            Add-OneImAuditFinding -Findings $findings -Seen $seen -Finding (
                New-OneImAuditFinding -RuleId "VB003" -RuleCatalog $RuleCatalog -SourceLookup $SourceLookup -FilePath $FilePath -RelativePath $RelativePath -Line $lineNumber `
                    -Evidence $trimmed `
                    -TriggeringScenario "Object-heavy or late-bound code is harder to reason about and tends to hide runtime-only failures." `
                    -Remediation "Use explicit types and direct member access so the compiler can validate the code path." `
                    -TestIdeas @("Replace Object-heavy declarations with concrete types and run the affected code path in System Debugger.")
            )
        }
    }

    "SEC100" = {
        if (Get-Command Get-OneImAuditSec100Finding -ErrorAction SilentlyContinue) {
            $statement = Get-OneImAuditStatementRange -Lines $lines -StartIndex $index
            if ([string]::IsNullOrWhiteSpace($statement.Text)) { return }
            $priorContextLines = @(Get-OneImAuditPreviousMeaningfulLines -Lines $lines -StartIndex $index -Count 4)
            Add-OneImAuditFinding -Findings $findings -Seen $seen -Finding (
                Get-OneImAuditSec100Finding -StatementText $statement.Text -PriorContextLines $priorContextLines `
                    -FilePath $FilePath -RelativePath $RelativePath -LineNumber $lineNumber `
                    -RuleCatalog $RuleCatalog -SourceLookup $SourceLookup
            )
        }
    }

    "SEC110" = {
        if ($RuleCatalog.ContainsKey("SEC110") -and $trimmed -match "(?i)\b(Process\.Start|cmd\.exe|powershell\.exe|wscript\.shell|Shell\s*\()") {
            Add-OneImAuditFinding -Findings $findings -Seen $seen -Finding (
                New-OneImAuditFinding -RuleId "SEC110" -RuleCatalog $RuleCatalog -SourceLookup $SourceLookup -FilePath $FilePath -RelativePath $RelativePath -Line $lineNumber `
                    -Evidence $trimmed `
                    -TriggeringScenario "Process execution from script logic broadens the trust boundary and can become command-injection prone." `
                    -Remediation "Remove shell execution from OneIM script paths or isolate it behind a reviewed service boundary with strict argument handling." `
                    -TestIdeas @("Confirm the scenario still works when external execution is removed or replaced with an internal API call.")
            )
        }
    }

    "SEC120" = {
        if ($RuleCatalog.ContainsKey("SEC120") -and $trimmed -match "^\s*Catch(\s+\w+)?\s+As\s+(System\.)?Exception\b" -and -not (Test-OneImAuditNearbyThrow -Lines $lines -LineNumber $lineNumber -LookaheadLines $cfgThrowLookahead)) {
            Add-OneImAuditFinding -Findings $findings -Seen $seen -Finding (
                New-OneImAuditFinding -RuleId "SEC120" -RuleCatalog $RuleCatalog -SourceLookup $SourceLookup -FilePath $FilePath -RelativePath $RelativePath -Line $lineNumber `
                    -Evidence $trimmed `
                    -TriggeringScenario "Broad exception handling without a nearby rethrow can hide broken security or correctness behavior." `
                    -Remediation "Catch the specific expected exception types, log useful context, and rethrow or surface failures when the script cannot safely continue." `
                    -TestIdeas @("Trigger the exception path and verify the failure is surfaced instead of silently swallowed.")
            )
        }
    }

    "SEC130" = {
        if ($RuleCatalog.ContainsKey("SEC130") -and $trimmed -match "(?i)\b(WebRequest|HttpWebRequest|WebClient)\b") {
            Add-OneImAuditFinding -Findings $findings -Seen $seen -Finding (
                New-OneImAuditFinding -RuleId "SEC130" -RuleCatalog $RuleCatalog -SourceLookup $SourceLookup -FilePath $FilePath -RelativePath $RelativePath -Line $lineNumber `
                    -Evidence $trimmed `
                    -TriggeringScenario "Older web request APIs are obsolete and more error-prone to secure than HttpClient-based code." `
                    -Remediation "Prefer HttpClient with explicit timeout, lifecycle, and certificate-handling decisions." `
                    -TestIdeas @("Replace the obsolete API with HttpClient and confirm the request path still works under timeout and error conditions.")
            )
        }
    }

    "SEC131" = {
        if (Get-Command Get-OneImAuditSec131Finding -ErrorAction SilentlyContinue) {
            $statement = Get-OneImAuditStatementRange -Lines $lines -StartIndex $index
            if ([string]::IsNullOrWhiteSpace($statement.Text)) { return }
            $priorContextLines = @(Get-OneImAuditPreviousMeaningfulLines -Lines $lines -StartIndex $index -Count 4)
            Add-OneImAuditFinding -Findings $findings -Seen $seen -Finding (
                Get-OneImAuditSec131Finding -StatementText $statement.Text -PriorContextLines $priorContextLines `
                    -FilePath $FilePath -RelativePath $RelativePath -LineNumber $lineNumber `
                    -RuleCatalog $RuleCatalog -SourceLookup $SourceLookup
            )
        }
    }

    "SEC140" = {
        if (Get-Command Get-OneImAuditSec140Finding -ErrorAction SilentlyContinue) {
            $statement = Get-OneImAuditStatementRange -Lines $lines -StartIndex $index
            if ([string]::IsNullOrWhiteSpace($statement.Text)) { return }
            $priorContextLines = @(Get-OneImAuditPreviousMeaningfulLines -Lines $lines -StartIndex $index -Count 4)
            Add-OneImAuditFinding -Findings $findings -Seen $seen -Finding (
                Get-OneImAuditSec140Finding -StatementText $statement.Text -PriorContextLines $priorContextLines `
                    -FilePath $FilePath -RelativePath $RelativePath -LineNumber $lineNumber `
                    -RuleCatalog $RuleCatalog -SourceLookup $SourceLookup
            )
        }
    }

    "SEC150" = {
        if (Get-Command Get-OneImAuditSec150Finding -ErrorAction SilentlyContinue) {
            $statement = Get-OneImAuditStatementRange -Lines $lines -StartIndex $index
            if ([string]::IsNullOrWhiteSpace($statement.Text)) { return }
            $priorContextLines = @(Get-OneImAuditPreviousMeaningfulLines -Lines $lines -StartIndex $index -Count 4)
            $nextContextLines = @(Get-OneImAuditNextMeaningfulLines -Lines $lines -StartIndex $statement.EndIndex -Count 4)
            $nearbyContextLines = @($priorContextLines + $nextContextLines)
            Add-OneImAuditFinding -Findings $findings -Seen $seen -Finding (
                Get-OneImAuditSec150Finding -StatementText $statement.Text -PriorContextLines $nearbyContextLines `
                    -FilePath $FilePath -RelativePath $RelativePath -LineNumber $lineNumber `
                    -RuleCatalog $RuleCatalog -SourceLookup $SourceLookup
            )
        }
    }

    "SEC160" = {
        if ($RuleCatalog.ContainsKey("SEC160") -and $trimmed -match "(?i)\b(BinaryFormatter|NetDataContractSerializer)\b") {
            Add-OneImAuditFinding -Findings $findings -Seen $seen -Finding (
                New-OneImAuditFinding -RuleId "SEC160" -RuleCatalog $RuleCatalog -SourceLookup $SourceLookup -FilePath $FilePath -RelativePath $RelativePath -Line $lineNumber `
                    -Evidence $trimmed `
                    -TriggeringScenario "These deserializers are unsafe for untrusted data and are difficult to justify in modern .NET code." `
                    -Remediation "Replace the deserializer with a safer format and validate the payload schema explicitly." `
                    -TestIdeas @("Attempt to deserialize crafted input in a test harness and verify the unsafe deserializer has been removed.")
            )
        }
    }

    "SEC170" = {
        if ($RuleCatalog.ContainsKey("SEC170") -and $trimmed -match "(?i)\b(ServerCertificateValidationCallback|SecurityProtocolType\.(Ssl3|Tls|Tls11)|SslProtocols\.(Ssl2|Ssl3|Tls|Tls11)|MD5|SHA1)\b") {
            Add-OneImAuditFinding -Findings $findings -Seen $seen -Finding (
                New-OneImAuditFinding -RuleId "SEC170" -RuleCatalog $RuleCatalog -SourceLookup $SourceLookup -FilePath $FilePath -RelativePath $RelativePath -Line $lineNumber `
                    -Evidence $trimmed `
                    -TriggeringScenario "Weak TLS, weak hashes, or disabled certificate validation materially weakens transport or integrity checks." `
                    -Remediation "Use current TLS defaults, keep certificate validation enabled, and replace weak hashes with modern approved algorithms." `
                    -TestIdeas @("Run a connection test against a bad certificate and verify the client rejects it.")
            )
        }
    }

    "REL200" = {
        if ($RuleCatalog.ContainsKey("REL200") -and $trimmed -match "(?i)\b(?:Dim\s+)?(?<name>[A-Za-z_][A-Za-z0-9_]*)\s*(?:As\s+New|=\s+New)\s+(?<type>FileStream|StreamReader|StreamWriter|SqlCommand|XmlReader|WebClient|HttpClient|StringReader|MemoryStream)\b" -and -not (Test-OneImAuditNearbyDispose -Lines $lines -LineNumber $lineNumber -VariableName $Matches["name"] -LookaheadLines $cfgDisposeLookahead)) {
            Add-OneImAuditFinding -Findings $findings -Seen $seen -Finding (
                New-OneImAuditFinding -RuleId "REL200" -RuleCatalog $RuleCatalog -SourceLookup $SourceLookup -FilePath $FilePath -RelativePath $RelativePath -Line $lineNumber `
                    -Evidence $trimmed `
                    -TriggeringScenario "Disposable resources created without Using or disposal logic can leak across repeated script execution." `
                    -Remediation "Wrap disposable resources in a Using block or dispose them deterministically before the reference is lost." `
                    -TestIdeas @("Run the code path repeatedly and confirm handles, sockets, or streams do not accumulate.")
            )
        }
    }

    "REL210" = {
        if ($RuleCatalog.ContainsKey("REL210") -and $trimmed -match "(?i)\.(Equals|StartsWith|EndsWith|IndexOf|Contains)\s*\(" -and $trimmed -notmatch "(?i)StringComparison" -and $trimmed -match "(?i)\b(uid|ident|identifier|key|id|column|table|dialog|name)\b") {
            Add-OneImAuditFinding -Findings $findings -Seen $seen -Finding (
                New-OneImAuditFinding -RuleId "REL210" -RuleCatalog $RuleCatalog -SourceLookup $SourceLookup -FilePath $FilePath -RelativePath $RelativePath -Line $lineNumber `
                    -Evidence $trimmed `
                    -TriggeringScenario "Identifier-sensitive string logic can behave differently under culture-aware defaults." `
                    -Remediation "Use an explicit StringComparison choice, usually Ordinal or OrdinalIgnoreCase for identifiers and keys." `
                    -TestIdeas @("Run the comparison in a non-default culture and verify identifiers still match exactly as intended.")
            )
        }
    }

    # REL220 + OIM500 share the $statement / $contextText computation.
    "REL220_OIM500" = {
        if (($RuleCatalog.ContainsKey("REL220") -or $RuleCatalog.ContainsKey("OIM500")) -and $trimmed -match "(?i)\b(PutValue|ExecuteTemplate)\s*\(") {
            $statement = Get-OneImAuditStatementRange -Lines $lines -StartIndex $index
            $priorContextLines = @(Get-OneImAuditPreviousMeaningfulLines -Lines $lines -StartIndex $index -Count 6)
            $contextText = (($priorContextLines + @($lines[$statement.StartIndex..$statement.EndIndex])) -join "`n")

            if ($RuleCatalog.ContainsKey("REL220")) {
                $triggerWriteFields = @(Get-OneImAuditTriggerWriteFields -StatementText $statement.Text)
                $unguardedTriggerWrites = @($triggerWriteFields | Where-Object {
                        -not (Test-OneImAuditIdentifierLikeTriggerField -Field $_.Field) -and
                        -not (Test-OneImAuditTriggerFieldGuarded -ContextText $contextText -Field $_.Field -Kind $_.Kind)
                    })
                if ($unguardedTriggerWrites.Count -gt 0) {
                    $fieldList = ($unguardedTriggerWrites | ForEach-Object { $_.Field } | Sort-Object -Unique) -join ", "
                    Add-OneImAuditFinding -Findings $findings -Seen $seen -Finding (
                        New-OneImAuditFinding -RuleId "REL220" -RuleCatalog $RuleCatalog -SourceLookup $SourceLookup -FilePath $FilePath -RelativePath $RelativePath -Line $lineNumber `
                            -Evidence $trimmed `
                            -TriggeringScenario ("Write logic uses GetTriggerValue string/text input without an obvious Nothing or empty guard for: {0}." -f $fieldList) `
                            -Remediation "Guard the specific trigger values before writing them into PutValue or ExecuteTemplate paths, and make empty-string handling explicit." `
                            -TestIdeas @("Test the write path with Nothing and empty trigger values and confirm the script behaves safely.")
                    )
                }
            }

            if ($RuleCatalog.ContainsKey("OIM500") -and -not (Test-OneImAuditConditionalGuardNearby -ContextLines $priorContextLines)) {
                Add-OneImAuditFinding -Findings $findings -Seen $seen -Finding (
                    New-OneImAuditFinding -RuleId "OIM500" -RuleCatalog $RuleCatalog -SourceLookup $SourceLookup -FilePath $FilePath -RelativePath $RelativePath -Line $lineNumber `
                        -Evidence $trimmed `
                        -TriggeringScenario "Write-oriented OneIM helpers can create hidden side effects when they execute without a nearby conditional guard or sync-state check." `
                        -Remediation "Document why the write is safe, or move it under an explicit conditional guard such as sync-state, change-level, or state-based intent." `
                        -TestIdeas @("Run the script in normal save and sync-time scenarios and confirm the side effect only happens when intended.")
                )
            }
        }
    }

    "PER400" = {
        if ($RuleCatalog.ContainsKey("PER400") -and $trimmed -match "(?i)\.(Count|LongCount)\s*\(\s*\)\s*(>|<>|=)\s*0\b") {
            Add-OneImAuditFinding -Findings $findings -Seen $seen -Finding (
                New-OneImAuditFinding -RuleId "PER400" -RuleCatalog $RuleCatalog -SourceLookup $SourceLookup -FilePath $FilePath -RelativePath $RelativePath -Line $lineNumber `
                    -Evidence $trimmed `
                    -TriggeringScenario "Count or LongCount is doing more work than needed when the only question is whether items exist." `
                    -Remediation "Use Any for emptiness checks and reserve Count or LongCount for cases where the total is actually needed." `
                    -TestIdeas @("Benchmark the hot path before and after switching the emptiness check to Any.")
            )
        }
    }

    "PER410" = {
        if ($RuleCatalog.ContainsKey("PER410") -and $loopDepthMap[$lineNumber] -gt 0 -and ($trimmed -match "&=" -or $trimmed -match "(?i)^\s*[A-Za-z_][A-Za-z0-9_]*\s*=\s*[A-Za-z_][A-Za-z0-9_]*\s*&")) {
            Add-OneImAuditFinding -Findings $findings -Seen $seen -Finding (
                New-OneImAuditFinding -RuleId "PER410" -RuleCatalog $RuleCatalog -SourceLookup $SourceLookup -FilePath $FilePath -RelativePath $RelativePath -Line $lineNumber `
                    -Evidence $trimmed `
                    -TriggeringScenario "Loop-driven string concatenation creates repeated allocations and can degrade performance noticeably." `
                    -Remediation "Use StringBuilder or accumulate into a collection before joining once at the end." `
                    -TestIdeas @("Benchmark the loop before and after replacing concatenation with StringBuilder.")
            )
        }
    }

    # PER420 accumulates per-line; flush happens post-loop.
    "PER420" = {
        if ($RuleCatalog.ContainsKey("PER420") -and $trimmed -match "(?i)\b(?<enumerable>[A-Za-z_][A-Za-z0-9_]*)\.(Count|LongCount)\s*\(") {
            $enumerable = $Matches["enumerable"]
            if (-not $potentialEnumerations.ContainsKey($enumerable)) {
                $potentialEnumerations[$enumerable] = New-Object System.Collections.Generic.List[int]
            }
            $potentialEnumerations[$enumerable].Add($lineNumber)
        }
    }

    "PER430" = {
        if ($RuleCatalog.ContainsKey("PER430") -and $loopDepthMap[$lineNumber] -gt 0 -and $trimmed -match "(?i)\b(Session|Connection|UnitOfWork|Source)\.") {
            Add-OneImAuditFinding -Findings $findings -Seen $seen -Finding (
                New-OneImAuditFinding -RuleId "PER430" -RuleCatalog $RuleCatalog -SourceLookup $SourceLookup -FilePath $FilePath -RelativePath $RelativePath -Line $lineNumber `
                    -Evidence $trimmed `
                    -TriggeringScenario "Per-iteration object or database access can multiply cost in large OneIM loops." `
                    -Remediation "Move invariant lookups outside the loop, cache repeated reads, or batch the work where the API allows it." `
                    -TestIdeas @("Measure the loop with realistic row counts and compare it to a cached or batched version.")
            )
        }
    }

    "VB004" = {
        # = Nothing / <> Nothing in conditional context (not Dim initialisation).
        if ($RuleCatalog.ContainsKey("VB004") -and
            $trimmed -match "(?i)(=|<>)\s*Nothing\b" -and
            ($trimmed -match "^\s*(If|ElseIf)\b" -or $trimmed -match "(?i)\b(AndAlso|OrElse)\b") -and
            $trimmed -notmatch "^\s*Dim\b") {
            Add-OneImAuditFinding -Findings $findings -Seen $seen -Finding (
                New-OneImAuditFinding -RuleId "VB004" -RuleCatalog $RuleCatalog -SourceLookup $SourceLookup -FilePath $FilePath -RelativePath $RelativePath -Line $lineNumber `
                    -Evidence $trimmed `
                    -TriggeringScenario "Using = Nothing or <> Nothing in a conditional applies value-equality semantics to a reference comparison, which can behave unexpectedly for reference types." `
                    -Remediation "Replace '= Nothing' with 'Is Nothing' and '<> Nothing' with 'IsNot Nothing' in all conditional expressions." `
                    -TestIdeas @(
                        "Verify the surrounding type is a reference type and confirm the comparison works as expected after switching to Is Nothing.",
                        "Test with both a populated and a Nothing reference to confirm the guard fires in exactly the expected case."
                    )
            )
        }
    }

    "REL230" = {
        # Empty Catch block: Catch immediately followed by End Try or another Catch with no code between.
        if ($RuleCatalog.ContainsKey("REL230") -and $trimmed -match "^\s*Catch\b") {
            $lookAheadIdx = $index + 1
            while ($lookAheadIdx -lt $lines.Count) {
                $la = $lines[$lookAheadIdx].Trim()
                if (-not [string]::IsNullOrWhiteSpace($la) -and -not $la.StartsWith("'")) {
                    break
                }
                $lookAheadIdx++
            }
            if ($lookAheadIdx -lt $lines.Count -and $lines[$lookAheadIdx].Trim() -match "^\s*(End Try|Catch)\b") {
                Add-OneImAuditFinding -Findings $findings -Seen $seen -Finding (
                    New-OneImAuditFinding -RuleId "REL230" -RuleCatalog $RuleCatalog -SourceLookup $SourceLookup -FilePath $FilePath -RelativePath $RelativePath -Line $lineNumber `
                        -Evidence $trimmed `
                        -TriggeringScenario "An empty Catch block silently swallows the exception. In a OneIM sync script this causes the operation to fail invisibly, producing wrong provisioning results without any error or log entry." `
                        -Remediation "At minimum log the exception with its message and stack trace. If the failure is truly non-fatal, document why and re-evaluate whether the script can continue safely." `
                        -TestIdeas @(
                            "Trigger the exception path and confirm that the failure is surfaced in the system-debugger log or escalated to the caller.",
                            "Remove the empty catch and handle the exception explicitly; verify the sync job reports a meaningful error."
                        )
                )
            }
        }
    }

    "PER440" = {
        # New <Type>(...) constructor calls inside a loop; suppresses common cheap inlinable types.
        if ($RuleCatalog.ContainsKey("PER440") -and $loopDepthMap[$lineNumber] -gt 0 -and
            $trimmed -match "(?i)=\s*New\s+[A-Za-z_]\w*\s*[(\[]" -and
            $trimmed -notmatch "(?i)=\s*New\s+(List|Dictionary|HashSet|Queue|Stack|StringBuilder)\s*[(\[]") {
            Add-OneImAuditFinding -Findings $findings -Seen $seen -Finding (
                New-OneImAuditFinding -RuleId "PER440" -RuleCatalog $RuleCatalog -SourceLookup $SourceLookup -FilePath $FilePath -RelativePath $RelativePath -Line $lineNumber `
                    -Evidence $trimmed `
                    -TriggeringScenario "An object is being constructed on every loop iteration, increasing GC pressure. Under large provisioning sets this can produce noticeable pause times and degrade throughput." `
                    -Remediation "Hoist the allocation outside the loop when the object can be reused, reset, or replaced by a value parameter. Where reuse is unsafe, consider pooling." `
                    -TestIdeas @("Benchmark the loop before and after hoisting the allocation; compare GC gen-0 counts in the system-debugger benchmark report.")
            )
        }
    }

    "OIM520" = {
        # GetListFor / GetSingleProperty / GetSingleFiltered inside a loop — N+1 query pattern.
        if ($loopDepthMap[$lineNumber] -gt 0 -and (Get-Command Get-OneImAuditOIM520Finding -ErrorAction SilentlyContinue)) {
            Add-OneImAuditFinding -Findings $findings -Seen $seen -Finding (
                Get-OneImAuditOIM520Finding -LineText $trimmed -LineNumber $lineNumber `
                    -FilePath $FilePath -RelativePath $RelativePath -RuleCatalog $RuleCatalog -SourceLookup $SourceLookup
            )
        }
    }

    "SEC190" = {
        # DirectorySearcher filter built by string concatenation — LDAP injection risk.
        # Fires when the line references DirectorySearcher construction or .Filter assignment
        # AND also contains a & concatenation operator, indicating a dynamically built filter.
        if ($RuleCatalog.ContainsKey("SEC190") -and
            $trimmed -match "(?i)(DirectorySearcher\s*\(|\.Filter\s*=)" -and
            $trimmed -match "&\s*[A-Za-z_""]") {
            Add-OneImAuditFinding -Findings $findings -Seen $seen -Finding (
                New-OneImAuditFinding -RuleId "SEC190" -RuleCatalog $RuleCatalog -SourceLookup $SourceLookup -FilePath $FilePath -RelativePath $RelativePath -Line $lineNumber `
                    -Evidence $trimmed `
                    -TriggeringScenario "An LDAP search filter is constructed by concatenating script parameters directly into the filter string. A caller who controls the parameter value can append extra filter clauses to widen or bypass the intended query scope." `
                    -Remediation "Sanitise all values inserted into LDAP filters by escaping special characters (parentheses, asterisk, backslash, NUL) before concatenation, or use a parameterised LDAP API if available. Validate that each parameter value conforms to expected format before use." `
                    -TestIdeas @(
                        "Pass a value containing ')(' characters as the parameter and verify the constructed filter is rejected or sanitised.",
                        "Test with a value such as '*)(uid=*))(|(uid=*' to confirm injection attempts are blocked."
                    )
            )
        }
    }

    "REL240" = {
        # .GetFk(...).GetParent() or .GetFk(...).GetValue() without an IsEmpty guard.
        # Chaining directly on the GetFk result dereferences a potentially empty FK object.
        if ($RuleCatalog.ContainsKey("REL240") -and
            $trimmed -match "(?i)\.GetFk\s*\([^)]*\)\s*\.(GetParent|GetValue|GetSingleValue)\s*\(") {
            Add-OneImAuditFinding -Findings $findings -Seen $seen -Finding (
                New-OneImAuditFinding -RuleId "REL240" -RuleCatalog $RuleCatalog -SourceLookup $SourceLookup -FilePath $FilePath -RelativePath $RelativePath -Line $lineNumber `
                    -Evidence $trimmed `
                    -TriggeringScenario "The script calls GetFk and immediately chains .GetParent() or .GetValue() without first checking IsEmpty. If the referenced row does not exist the FK object is empty and the chained call throws a NullReferenceException, aborting provisioning for that object." `
                    -Remediation "Assign the GetFk result to a variable, test .IsEmpty before calling further methods, and handle the empty case explicitly (skip, log, or raise a meaningful error)." `
                    -TestIdeas @(
                        "Supply an object whose FK column is NULL and confirm the script does not throw.",
                        "Supply a valid FK and confirm the chained call succeeds."
                    )
            )
        }
    }

    "STR600" = {
        # .ToLower()/.ToUpper() used in a comparison — culture-sensitive, allocates temp string.
        # Fires when the result is directly compared (= or <>) on the same line, or when
        # it appears inside a conditional expression (If/ElseIf/While/Do While).
        if ($RuleCatalog.ContainsKey("STR600") -and
            $trimmed -match "(?i)\.To(?:Lower|Upper)\s*\(\s*\)" -and
            ($trimmed -match "(?i)\.To(?:Lower|Upper)\s*\(\s*\)\s*(?:=|<>|Like\b)" -or
             $trimmed -match "^\s*(If|ElseIf|While|Do While|Loop While)\b")) {
            Add-OneImAuditFinding -Findings $findings -Seen $seen -Finding (
                New-OneImAuditFinding -RuleId "STR600" -RuleCatalog $RuleCatalog -SourceLookup $SourceLookup -FilePath $FilePath -RelativePath $RelativePath -Line $lineNumber `
                    -Evidence $trimmed `
                    -TriggeringScenario "A string comparison is performed by normalising case with .ToLower() or .ToUpper() before comparing. This is culture-sensitive: in the Turkish locale the uppercase I lowercases to a dotless i, not i, silently breaking the comparison for any string containing that letter. OneIM sync scripts can run on servers in any locale." `
                    -Remediation "Replace .ToLower() or .ToUpper() comparisons with String.Equals(a, b, StringComparison.OrdinalIgnoreCase) for case-insensitive checks, or StringComparison.Ordinal for case-sensitive ones. Both are locale-independent." `
                    -TestIdeas @(
                        "Test the comparison with strings containing 'I' / 'i' on a Turkish-locale machine and confirm the result is unchanged.",
                        "Measure memory allocations before and after removing the ToLower/ToUpper call."
                    )
            )
        }
    }

    "OIM530" = {
        # f.Comparison() called with a column name starting with UID_ — use f.UidComparison() instead.
        # Pattern: any ISqlFormatter .Comparison call whose first string argument is "UID_xxx".
        if ($RuleCatalog.ContainsKey("OIM530") -and
            $trimmed -match "(?i)\b\w+\.Comparison\s*\(\s*""UID_[A-Za-z_]") {
            Add-OneImAuditFinding -Findings $findings -Seen $seen -Finding (
                New-OneImAuditFinding -RuleId "OIM530" -RuleCatalog $RuleCatalog -SourceLookup $SourceLookup -FilePath $FilePath -RelativePath $RelativePath -Line $lineNumber `
                    -Evidence $trimmed `
                    -TriggeringScenario "A UID column is compared using the generic f.Comparison() method with ValType.String. The OneIM SQL formatter provides f.UidComparison() specifically for UID/GUID columns; it handles the empty-UID sentinel value ('') and any UID-specific SQL optimisations. Using the generic method may generate subtly different SQL that mismatches the UID storage semantics." `
                    -Remediation "Replace f.Comparison(""UID_xxx"", value, ValType.String, ...) with f.UidComparison(""UID_xxx"", value, ...). The UidComparison overload signature matches the Comparison overload with the ValType.String argument removed." `
                    -TestIdeas @(
                        "Run the query with an empty string '' value and compare the generated SQL from f.Comparison vs f.UidComparison.",
                        "Verify the result set is identical before and after switching to f.UidComparison."
                    )
            )
        }
    }

    "PER451" = {
        # IEntity.Create(Session) inside a loop — triggers one SELECT per collection item.
        # Both .Create(Session) and .Create(Session, EntityLoadType.xxx) forms are matched.
        if ($loopDepthMap[$lineNumber] -gt 0 -and (Get-Command Get-OneImAuditPER451Finding -ErrorAction SilentlyContinue)) {
            Add-OneImAuditFinding -Findings $findings -Seen $seen -Finding (
                Get-OneImAuditPER451Finding -LineText $trimmed -LineNumber $lineNumber `
                    -FilePath $FilePath -RelativePath $RelativePath -RuleCatalog $RuleCatalog -SourceLookup $SourceLookup
            )
        }
    }

    "OIM597" = {
        # TryGet / TryGetSingleValue / TryGetSingleFiltered inside a loop — N+1 read pattern.
        # Each call issues a separate SELECT. Use Session.Source.GetCollection / GetCollectionFiltered
        # to fetch all needed entities in one query before the loop, then look up from an in-memory dict.
        if ($loopDepthMap[$lineNumber] -gt 0 -and (Get-Command Get-OneImAuditOIM597Finding -ErrorAction SilentlyContinue)) {
            Add-OneImAuditFinding -Findings $findings -Seen $seen -Finding (
                Get-OneImAuditOIM597Finding -LineText $trimmed -LineNumber $lineNumber `
                    -FilePath $FilePath -RelativePath $RelativePath -RuleCatalog $RuleCatalog -SourceLookup $SourceLookup
            )
        }
    }

    "OIM555" = {
        # .Save(Session) inside a loop — each call is a separate database round-trip.
        # UnitOfWork.Put() + Commit() batches all writes into a single transaction.
        if ($loopDepthMap[$lineNumber] -gt 0 -and (Get-Command Get-OneImAuditOIM555Finding -ErrorAction SilentlyContinue)) {
            Add-OneImAuditFinding -Findings $findings -Seen $seen -Finding (
                Get-OneImAuditOIM555Finding -LineText $trimmed -LineNumber $lineNumber `
                    -FilePath $FilePath -RelativePath $RelativePath -RuleCatalog $RuleCatalog -SourceLookup $SourceLookup
            )
        }
    }

    "PER455" = {
        # BuildSessionFactory() per method invocation — rebuilds expensive connection infrastructure.
        # Fires on any line containing BuildSessionFactory(; the finding advises caching at module level.
        if ($RuleCatalog.ContainsKey("PER455") -and
            $trimmed -match "(?i)\bBuildSessionFactory\s*\(") {
            Add-OneImAuditFinding -Findings $findings -Seen $seen -Finding (
                New-OneImAuditFinding -RuleId "PER455" -RuleCatalog $RuleCatalog -SourceLookup $SourceLookup -FilePath $FilePath -RelativePath $RelativePath -Line $lineNumber `
                    -Evidence $trimmed `
                    -TriggeringScenario "BuildSessionFactory() is called inside a helper method that runs once per provisioned account. The factory compiles connection metadata and sets up the connection pool on every call, paying the full initialisation cost (potentially 50-200ms) for each record rather than once at startup." `
                    -Remediation "Move the session factory to a Shared ReadOnly module-level field (e.g., 'Private Shared ReadOnly _sf As ISessionFactory = DbApp.ConnectTo(...).BuildSessionFactory()') so it is built once and reused across all calls." `
                    -TestIdeas @(
                        "Measure elapsed time per record before and after moving BuildSessionFactory() to a cached field.",
                        "Confirm that the cached factory correctly handles connection errors by reconnecting on the next call."
                    )
            )
        }
    }

    # OIM560 accumulates per-line; flush happens post-loop.
    # Key = table name + "|" + where-clause text so only calls with the same table
    # AND the same where clause are grouped — different where clauses are independent queries.
    "OIM560" = {
        if ($RuleCatalog.ContainsKey("OIM560") -and
            $trimmed -match '(?i)\b(?:Try)?GetSingleValue\s*\(\s*"([^"]+)"\s*,[^,]+,\s*([^)]+)\)') {
            $tableName  = $Matches[1].Trim()
            $whereClause = $Matches[2].Trim().ToLower()
            $key = $tableName + '|' + $whereClause
            if (-not $tryGetSingleValueByTable.ContainsKey($key)) {
                $tryGetSingleValueByTable[$key] = New-Object System.Collections.Generic.List[int]
            }
            $tryGetSingleValueByTable[$key].Add($lineNumber)
        }
    }

    # OIM570/OIM571: MultiValueProperty — track variable declarations, modifications, writeback, and index access.
    "OIM570_OIM571" = {
        # Collect variable names declared as MultiValueProperty.
        if (($RuleCatalog.ContainsKey("OIM570") -or $RuleCatalog.ContainsKey("OIM571")) -and
            $trimmed -match '(?i)\bDim\s+(\w+)\s+As\s+(?:New\s+)?MultiValueProperty\b') {
            [void]$mvpVarNames.Add($Matches[1])
        }

        # OIM570: track .Add() or .Remove() on any MVP variable (modification without writeback = data loss).
        if ($RuleCatalog.ContainsKey("OIM570") -and $mvpModLineList.Count -eq 0 -and
            $trimmed -match '(?i)\.(Add|Remove)\s*\(') {
            # Only record if an MVP variable is in scope (any declared in this file).
            if ($mvpVarNames.Count -gt 0) {
                [void]$mvpModLineList.Add($lineNumber)
            }
        }

        # OIM570: track .Value written back via PutValue — clears the violation.
        if ($RuleCatalog.ContainsKey("OIM570") -and
            $trimmed -match '(?i)\bPutValue\b' -and $trimmed -match '(?i)\.Value\b') {
            [void]$mvpWritebackList.Add($true)
        }

        # OIM571: index access on a known MVP variable without a .Count guard in the preceding 10 lines.
        if ($RuleCatalog.ContainsKey("OIM571") -and $mvpVarNames.Count -gt 0) {
            foreach ($varName in $mvpVarNames) {
                if ($trimmed -match ('(?i)\b' + [regex]::Escape($varName) + '\s*\(')) {
                    # Check preceding 10 lines for a .Count check.
                    $guardFound = $false
                    $startCheck = [Math]::Max(0, $index - $cfgMvpGuardLookback)
                    for ($c = $startCheck; $c -lt $index; $c++) {
                        if ($lines[$c] -match '(?i)\.Count\b') {
                            $guardFound = $true
                            break
                        }
                    }
                    if (-not $guardFound) {
                        Add-OneImAuditFinding -Findings $findings -Seen $seen -Finding (
                            New-OneImAuditFinding -RuleId "OIM571" -RuleCatalog $RuleCatalog -SourceLookup $SourceLookup -FilePath $FilePath -RelativePath $RelativePath -Line $lineNumber `
                                -Evidence $trimmed `
                                -TriggeringScenario ("'{0}' is accessed by array index without a visible .Count bounds check in the preceding lines. If the stored value has fewer entries than expected, this throws an IndexOutOfRangeException." -f $varName) `
                                -Remediation ("Wrap the index access in a guard: 'If i < {0}.Count Then ... End If', as shown in the OneIM MultiValueProperty reference sample." -f $varName) `
                                -TestIdeas @(
                                    "Call the function with an entity whose OtherMailbox column is empty and verify no IndexOutOfRangeException is thrown.",
                                    "Add a .Count guard and confirm the function returns String.Empty when the position is out of range."
                                )
                        )
                    }
                }
            }
        }
    }

    # OIM580: VI_AE_ITDataFromOrg/Pers called — track call lines and comment-based dependencies.
    "OIM580" = {
        if ($RuleCatalog.ContainsKey("OIM580")) {
            if ($itDataCallLines.Count -eq 0 -and
                $trimmed -match '(?i)\bVI_AE_ITDataFrom(?:Org|Pers)\s*\(') {
                [void]$itDataCallLines.Add($lineNumber)
            }
            # Comment line containing a dollar-notation reference: '$Column$ or '$FK(...)...
            if ($trimmed -match "^'\s*\`$[A-Za-z_(]") {
                [void]$itDataDollarComments.Add($true)
            }
        }
    }

    "REL260" = {
        if ($RuleCatalog.ContainsKey("REL260") -and
            $trimmed -match '(?i)\b(CType|DirectCast)\s*\(') {
            $castKeyword = $Matches[1]
            # Check preceding context_lines lines for a TypeOf ... Is guard
            $hasGuard = $false
            $lookbackStart = [Math]::Max(0, $index - $cfgContextLines)
            for ($j = $lookbackStart; $j -lt $index; $j++) {
                if ($lines[$j] -match '(?i)\bTypeOf\b.*\bIs\b') {
                    $hasGuard = $true
                    break
                }
            }
            if (-not $hasGuard) {
                Add-OneImAuditFinding -Findings $findings -Seen $seen -Finding (
                    New-OneImAuditFinding -RuleId "REL260" -RuleCatalog $RuleCatalog -SourceLookup $SourceLookup `
                        -FilePath $FilePath -RelativePath $RelativePath -Line $lineNumber `
                        -Evidence $trimmed `
                        -TriggeringScenario ("$castKeyword throws InvalidCastException when the object is not of the target type. In OneIM scripts the source object may be Nothing or a different runtime subtype depending on provisioning state and data configuration.") `
                        -Remediation ("Add a TypeOf guard before the cast: If TypeOf obj Is TargetType Then Dim typed = CType(obj, TargetType). Alternatively use TryCast which returns Nothing instead of throwing.") `
                        -TestIdeas @(
                            "Pass an object of the wrong type and confirm InvalidCastException is thrown without the guard.",
                            "Add the TypeOf guard and verify the finding no longer fires.",
                            "Verify TryCast(obj, TargetType) with an IsNot Nothing check does not trigger the rule."
                        )
                )
            }
        }
    }

    "OIM590" = {
        if ($RuleCatalog.ContainsKey("OIM590") -and
            $trimmed -match '(?i)\.GetList\b' -and
            $trimmed -match ',\s*(""|String\.Empty)\s*[,)]') {
            [void]$getListEmptyLines.Add($lineNumber)
        }
    }

    "OIM596" = {
        if ($RuleCatalog.ContainsKey("OIM596")) {
            # Track any Connection.GetConfigParmValue usage in the file
            if ($trimmed -match '(?i)\bConnection\.GetConfigParmValue\s*\(') {
                [void]$configParmValueCalled.Add($true)
            }
            # Flag GetValue/GetColumnValue result compared to a non-trivial hardcoded string literal
            # Ignore: empty string, GUIDs, purely numeric strings, known boolean-ish values
            if ($getValueCompareLines.Count -lt 10 -and
                $trimmed -match '(?i)\.Get(?:Column)?Value\s*\([^)]+\)\s*(=|<>)\s*"([^"]{2,})"') {
                $literalVal = $Matches[2]
                $isGuid    = $literalVal -match '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'
                $isNumeric = $literalVal -match '^\d+(\.\d+)?$'
                $isBool    = $literalVal -match '^(?:true|false|yes|no)$'
                if (-not $isGuid -and -not $isNumeric -and -not $isBool) {
                    [void]$getValueCompareLines.Add($lineNumber)
                }
            }
        }
    }
}

function Get-OneImFileFindings {
    param(
        [Parameter(Mandatory)]
        [string]$FilePath,

        [Parameter(Mandatory)]
        [string]$RelativePath,

        [Parameter(Mandatory)]
        [hashtable]$RuleCatalog,

        [Parameter(Mandatory)]
        [hashtable]$SourceLookup,

        [Parameter()]
        [hashtable]$Config
    )

    # Resolve config values (fall back to built-in defaults when $Config not supplied).
    $cfgHeaderScanLines     = if ($null -ne $Config) { $Config.detection.header_scan_lines }              else { 40 }
    $cfgMvpGuardLookback    = if ($null -ne $Config) { $Config.detection.mvp_guard_lookback_lines }       else { 10 }
    $cfgThrowLookahead      = if ($null -ne $Config) { $Config.detection.nearby_throw_lookahead_lines }   else { 6  }
    $cfgDisposeLookahead    = if ($null -ne $Config) { $Config.detection.nearby_dispose_lookahead_lines } else { 8  }

    $lines = @(Get-Content -LiteralPath $FilePath)
    $findings = New-Object 'System.Collections.Generic.List[object]'
    $seen = @{}
    $loopDepthMap = Get-OneImAuditLoopDepthMap -Lines $lines

    # --- Header checks (file-level, not per-line) ---
    $optionExplicitLine = Get-OneImAuditHeaderLineNumber -Lines $lines -Pattern "^\s*Option\s+Explicit\s+On\b" -HeaderScanLines $cfgHeaderScanLines
    if (-not $optionExplicitLine -and $RuleCatalog.ContainsKey("VB001")) {
        Add-OneImAuditFinding -Findings $findings -Seen $seen -Finding (
            New-OneImAuditFinding -RuleId "VB001" -RuleCatalog $RuleCatalog -SourceLookup $SourceLookup -FilePath $FilePath -RelativePath $RelativePath -Line 1 `
                -Evidence "Header did not contain 'Option Explicit On' in the first 40 lines." `
                -TriggeringScenario "Late-bound members or misspelled variables can survive compile-time checks more easily when Option Explicit is off or missing." `
                -Remediation "Add 'Option Explicit On' at the top of the file and resolve any resulting undeclared-variable errors explicitly." `
                -TestIdeas @("Compile the script after enabling Option Explicit and confirm all identifiers resolve cleanly.")
        )
    }

    $optionStrictLine = Get-OneImAuditHeaderLineNumber -Lines $lines -Pattern "^\s*Option\s+Strict\s+On\b" -HeaderScanLines $cfgHeaderScanLines
    if (-not $optionStrictLine -and $RuleCatalog.ContainsKey("VB002")) {
        Add-OneImAuditFinding -Findings $findings -Seen $seen -Finding (
            New-OneImAuditFinding -RuleId "VB002" -RuleCatalog $RuleCatalog -SourceLookup $SourceLookup -FilePath $FilePath -RelativePath $RelativePath -Line 1 `
                -Evidence "Header did not contain 'Option Strict On' in the first 40 lines." `
                -TriggeringScenario "Implicit narrowing conversions and late-bound calls can hide correctness bugs until runtime." `
                -Remediation "Add 'Option Strict On' at the top of the file and fix any narrowing conversions or late-bound access explicitly." `
                -TestIdeas @("Recompile the script after enabling Option Strict and exercise the affected template or method paths.")
        )
    }

    # PER420 accumulates across lines; initialize before the per-line loop.
    $potentialEnumerations = @{}

    # OIM560 accumulates TryGetSingleValue/GetSingleValue calls per table name.
    $tryGetSingleValueByTable = @{}

    # OIM570/OIM571 track MultiValueProperty usage across the file.
    $mvpVarNames      = New-Object System.Collections.Generic.HashSet[string]
    $mvpModLineList   = New-Object System.Collections.Generic.List[int]   # holds line of first .Add/.Remove
    $mvpWritebackList = New-Object System.Collections.Generic.List[bool]  # non-empty = PutValue writeback seen

    # OIM580 tracks VI_AE_ITDataFrom* calls and comment-based dependency declarations.
    $itDataCallLines    = New-Object System.Collections.Generic.List[int]
    $itDataDollarComments = New-Object System.Collections.Generic.List[bool]

    # REL260 tracks CType/DirectCast calls without a TypeOf guard.
    $cfgContextLines = if ($null -ne $Config) { $Config.detection.context_lines } else { 6 }

    # OIM590 tracks GetList("") / GetList(String.Empty) calls.
    $getListEmptyLines = New-Object System.Collections.Generic.List[int]

    # OIM596 tracks GetValue/GetColumnValue compared to hardcoded string and GetConfigParmValue usage.
    $getValueCompareLines  = New-Object System.Collections.Generic.List[int]
    $configParmValueCalled = New-Object System.Collections.Generic.List[bool]

    # --- Per-line dispatch loop ---
    for ($index = 0; $index -lt $lines.Count; $index++) {
        $lineNumber = $index + 1
        $trimmed = $lines[$index].Trim()

        foreach ($unit in $script:_detectionUnits.GetEnumerator()) {
            & $unit.Value
        }
    }

    # --- Post-loop: flush PER420 accumulator ---
    if ($RuleCatalog.ContainsKey("PER420")) {
        foreach ($entry in $potentialEnumerations.GetEnumerator()) {
            if ($entry.Value.Count -ge 2) {
                $firstLine = $entry.Value[0]
                Add-OneImAuditFinding -Findings $findings -Seen $seen -Finding (
                    New-OneImAuditFinding -RuleId "PER420" -RuleCatalog $RuleCatalog -SourceLookup $SourceLookup -FilePath $FilePath -RelativePath $RelativePath -Line $firstLine `
                        -Evidence ("'{0}' appears in multiple Count-style calls in the same file." -f $entry.Key) `
                        -TriggeringScenario "Repeated Count-style calls on the same enumerable can indicate multiple enumeration in hot paths." `
                        -Remediation "Materialize or cache the sequence once when repeated traversal is intentional, or prefer Any when only existence matters." `
                        -TestIdeas @("Profile the code path and confirm the enumerable is not being re-evaluated unnecessarily.")
                )
            }
        }
    }

    # --- Post-loop: flush OIM560 accumulator ---
    if ($RuleCatalog.ContainsKey("OIM560")) {
        foreach ($entry in $tryGetSingleValueByTable.GetEnumerator()) {
            if ($entry.Value.Count -ge 2) {
                # Key format is "TableName|whereclause" — extract the display table name.
                $tableName = $entry.Key.Split('|')[0]
                # Report each call after the first — they are the redundant round-trips.
                for ($i = 1; $i -lt $entry.Value.Count; $i++) {
                    $dupLine = $entry.Value[$i]
                    Add-OneImAuditFinding -Findings $findings -Seen $seen -Finding (
                        New-OneImAuditFinding -RuleId "OIM560" -RuleCatalog $RuleCatalog -SourceLookup $SourceLookup -FilePath $FilePath -RelativePath $RelativePath -Line $dupLine `
                            -Evidence ("TryGetSingleValue called {0} times on table '{1}' with the same where clause; this is call #{2}." -f $entry.Value.Count, $tableName, ($i + 1)) `
                            -TriggeringScenario ("The script queries '{0}' with TryGetSingleValue {1} separate times using the same where clause, issuing {1} individual SELECTs when one entity load would be sufficient." -f $tableName, $entry.Value.Count) `
                            -Remediation ("Replace the repeated TryGetSingleValue calls with a single Session.Source.TryGet(Of IEntity)('{0}', whereClause). TryGet returns Nothing when no row matches (safe, like TryGetSingleValue) and gives you all columns in one round-trip." -f $tableName) `
                            -TestIdeas @(
                                "Enable SQL query logging in the system debugger and verify the SELECT count drops from N to 1.",
                                "Add an IsNot Nothing guard on the entity returned by TryGet before reading its column values."
                            )
                    )
                }
            }
        }
    }

    # --- Post-loop: flush OIM570 (MVP modified without writeback) ---
    if ($RuleCatalog.ContainsKey("OIM570") -and $mvpModLineList.Count -gt 0 -and $mvpWritebackList.Count -eq 0) {
        Add-OneImAuditFinding -Findings $findings -Seen $seen -Finding (
            New-OneImAuditFinding -RuleId "OIM570" -RuleCatalog $RuleCatalog -SourceLookup $SourceLookup -FilePath $FilePath -RelativePath $RelativePath -Line $mvpModLineList[0] `
                -Evidence "MultiValueProperty modified via .Add() or .Remove() but no PutValue(..., mvp.Value) call found in this file." `
                -TriggeringScenario "A MultiValueProperty is built from a database column, modified in memory with .Add() or .Remove(), but the updated value is never written back. When the entity is saved the column retains its original value -- the modifications are silently discarded." `
                -Remediation "After modifying the MVP, call entity.PutValue with the column name and mvpVariable.Value to persist the change. Example: entity.PutValue(colName, mvpVariable.Value) where colName is the same column used in entity.GetValue." `
                -TestIdeas @(
                    "Add a value with .Add(), reload the entity from the database, and confirm the new value is present.",
                    "Check that PutValue is called with the .Value property of the MVP, not the MVP object itself."
                )
        )
    }

    # --- Post-loop: flush OIM580 (VI_AE_ITDataFrom* without comment dependencies) ---
    if ($RuleCatalog.ContainsKey("OIM580") -and $itDataCallLines.Count -gt 0 -and $itDataDollarComments.Count -eq 0) {
        Add-OneImAuditFinding -Findings $findings -Seen $seen -Finding (
            New-OneImAuditFinding -RuleId "OIM580" -RuleCatalog $RuleCatalog -SourceLookup $SourceLookup -FilePath $FilePath -RelativePath $RelativePath -Line $itDataCallLines[0] `
                -Evidence "VI_AE_ITDataFromOrg or VI_AE_ITDataFromPers called but no comment-based dollar-notation dependency declarations ('`$Column`$) found in this file." `
                -TriggeringScenario "The ITData function reads columns from the IT data hierarchy internally. Because those column references are hidden inside the function call the OneIM template engine does not register them as dependencies and will not re-evaluate the template when the underlying values change." `
                -Remediation "Declare the hidden input columns as comment-based dependencies directly above the call: '`$Department`$ / '`$Location`$ / '`$FK(UID_Person).UID_ProfitCenter`$. The template engine registers dependency columns found in comments as well as in active code." `
                -TestIdeas @(
                    "Change a Department value for a Person and confirm the derived template field is recalculated after adding the comment dependencies.",
                    "Remove the comment dependencies and verify the template is NOT recalculated on data change, confirming the finding."
                )
        )
    }

    # --- Post-loop: flush OIM590 (GetList with empty filter) ---
    foreach ($gll in $getListEmptyLines) {
        if ($RuleCatalog.ContainsKey("OIM590")) {
            Add-OneImAuditFinding -Findings $findings -Seen $seen -Finding (
                New-OneImAuditFinding -RuleId "OIM590" -RuleCatalog $RuleCatalog -SourceLookup $SourceLookup -FilePath $FilePath -RelativePath $RelativePath -Line $gll `
                    -Evidence "Session.Source.GetList called with an empty WHERE filter." `
                    -TriggeringScenario "Calling GetList with an empty or String.Empty WHERE clause returns the entire table. In production OneIM databases these tables can contain millions of rows, causing out-of-memory conditions and extremely slow provisioning jobs." `
                    -Remediation "Always supply a specific WHERE clause to GetList, e.g. Session.Source.GetList(Of IEntity)(tableName, whereClause). If you genuinely need all rows, document why and consider a paged approach." `
                    -TestIdeas @(
                        "Verify GetList(String.Empty) triggers the rule.",
                        "Verify GetList(whereClause) with a non-empty filter does NOT trigger the rule.",
                        "Verify GetList(`"`") triggers the rule."
                    )
            )
        }
    }

    # --- Post-loop: flush OIM596 (hardcoded business value without GetConfigParmValue) ---
    if ($RuleCatalog.ContainsKey("OIM596") -and $getValueCompareLines.Count -gt 0 -and $configParmValueCalled.Count -eq 0) {
        foreach ($gvl in $getValueCompareLines) {
            Add-OneImAuditFinding -Findings $findings -Seen $seen -Finding (
                New-OneImAuditFinding -RuleId "OIM596" -RuleCatalog $RuleCatalog -SourceLookup $SourceLookup -FilePath $FilePath -RelativePath $RelativePath -Line $gvl `
                    -Evidence "GetValue result compared against a hardcoded string literal and Connection.GetConfigParmValue is not used anywhere in this file." `
                    -TriggeringScenario "Business values (department names, status codes, company identifiers) that are compared directly as string literals must be changed in code when the business value changes. In OneIM Designer these values can be stored as named Configuration Parameters and read at runtime via Connection.GetConfigParmValue('KeyName')." `
                    -Remediation "Define the value as a Configuration Parameter in OneIM Designer (Base Data > General > Configuration Parameters). Replace the hardcoded literal with Connection.GetConfigParmValue('YourConfigKey'). This allows administrators to update the value without redeploying scripts." `
                    -TestIdeas @(
                        "Verify that .GetValue(col) = ""hardcodedValue"" triggers the rule.",
                        "Verify that adding Connection.GetConfigParmValue anywhere in the file suppresses the finding.",
                        "Verify that .GetValue(col) = """" (empty string) does NOT trigger the rule.",
                        "Verify that comparing against a GUID string does NOT trigger the rule."
                    )
            )
        }
    }

    # Declarative rule pass — runs all active declarative rules after coded checks
    foreach ($finding in @(Invoke-OneImDeclarativeRulePass -Lines $lines -FilePath $FilePath -RelativePath $RelativePath -RuleCatalog $RuleCatalog -SourceLookup $SourceLookup -Config $Config)) {
        Add-OneImAuditFinding -Findings $findings -Seen $seen -Finding $finding
    }

    return $findings.ToArray()
}

function Test-OneImAuditPathScopeMatch {
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [AllowEmptyString()]
        [string[]]$Globs,

        [Parameter(Mandatory)]
        [string]$RelativePath
    )

    foreach ($glob in @($Globs)) {
        if ([string]::IsNullOrWhiteSpace($glob)) {
            continue
        }

        $pattern = [System.Management.Automation.WildcardPattern]::new($glob, [System.Management.Automation.WildcardOptions]::IgnoreCase)
        if ($pattern.IsMatch($RelativePath)) {
            return $true
        }
    }

    return $false
}

function Invoke-OneImDeclarativeRulePass {
    param(
        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [AllowEmptyString()]
        [string[]]$Lines,

        [Parameter(Mandatory)]
        [string]$FilePath,

        [Parameter(Mandatory)]
        [string]$RelativePath,

        [Parameter(Mandatory)]
        [hashtable]$RuleCatalog,

        [Parameter(Mandatory)]
        [hashtable]$SourceLookup,

        [Parameter()]
        [hashtable]$Config
    )

    $cfgHeaderScanLines = if ($null -ne $Config) { $Config.detection.header_scan_lines } else { 40 }

    $findings = New-Object 'System.Collections.Generic.List[object]'
    $seen = @{}

    $declarativeRules = @($RuleCatalog.GetEnumerator() | Where-Object { [string]$_.Value.Engine -eq "declarative" } | ForEach-Object { $_.Value })

    foreach ($rule in $declarativeRules) {
        # Path scoping — exclude wins over include.
        # PS5.1 ConvertFrom-Json and pscustomobject can store @() as $null, and
        # if-else returning @() also yields $null in an assignment context.
        # Use Generic.List to guarantee a non-null collection with a real Count.
        $excludeGlobsList = New-Object 'System.Collections.Generic.List[string]'
        $includeGlobsList = New-Object 'System.Collections.Generic.List[string]'

        if ($null -ne $rule.ExcludePaths) {
            foreach ($g in @($rule.ExcludePaths)) {
                if ($null -ne $g -and -not [string]::IsNullOrWhiteSpace([string]$g)) { $excludeGlobsList.Add([string]$g) }
            }
        }
        if ($null -ne $rule.IncludePaths) {
            foreach ($g in @($rule.IncludePaths)) {
                if ($null -ne $g -and -not [string]::IsNullOrWhiteSpace([string]$g)) { $includeGlobsList.Add([string]$g) }
            }
        }

        if ($excludeGlobsList.Count -gt 0 -and (Test-OneImAuditPathScopeMatch -Globs $excludeGlobsList.ToArray() -RelativePath $RelativePath)) {
            continue
        }

        if ($includeGlobsList.Count -gt 0 -and -not (Test-OneImAuditPathScopeMatch -Globs $includeGlobsList.ToArray() -RelativePath $RelativePath)) {
            continue
        }

        $matchKind = [string]$rule.MatchKind
        $pattern = [string]$rule.Pattern

        if ([string]::IsNullOrWhiteSpace($matchKind) -or [string]::IsNullOrWhiteSpace($pattern)) {
            continue
        }

        $triggeringScenario = [string]$rule.TriggeringScenario
        $remediation = [string]$rule.Remediation
        $testIdeas = @($rule.TestIdeas | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object { [string]$_ })
        if ($testIdeas.Count -eq 0) {
            $testIdeas = @("Verify the condition no longer triggers after applying the recommended remediation.")
        }

        switch ($matchKind) {
            "header-required" {
                $found = $false
                $limit = [Math]::Min($Lines.Count, $cfgHeaderScanLines)
                for ($i = 0; $i -lt $limit; $i++) {
                    if ($Lines[$i] -match $pattern) {
                        $found = $true
                        break
                    }
                }

                if (-not $found) {
                    Add-OneImAuditFinding -Findings $findings -Seen $seen -Finding (
                        New-OneImAuditFinding -RuleId $rule.Id -RuleCatalog $RuleCatalog -SourceLookup $SourceLookup `
                            -FilePath $FilePath -RelativePath $RelativePath -Line 1 `
                            -Evidence ("Header did not contain the expected pattern in the first {0} lines: {1}" -f $cfgHeaderScanLines, $pattern) `
                            -TriggeringScenario $triggeringScenario `
                            -Remediation $remediation `
                            -TestIdeas $testIdeas
                    )
                }
            }
            "line-absence" {
                $found = $false
                foreach ($line in $Lines) {
                    if ($line -match $pattern) {
                        $found = $true
                        break
                    }
                }

                if (-not $found) {
                    Add-OneImAuditFinding -Findings $findings -Seen $seen -Finding (
                        New-OneImAuditFinding -RuleId $rule.Id -RuleCatalog $RuleCatalog -SourceLookup $SourceLookup `
                            -FilePath $FilePath -RelativePath $RelativePath -Line 1 `
                            -Evidence ("No line matched the expected pattern: {0}" -f $pattern) `
                            -TriggeringScenario $triggeringScenario `
                            -Remediation $remediation `
                            -TestIdeas $testIdeas
                    )
                }
            }
            "line-pattern" {
                for ($i = 0; $i -lt $Lines.Count; $i++) {
                    if ($Lines[$i] -match $pattern) {
                        $trimmed = $Lines[$i].Trim()
                        Add-OneImAuditFinding -Findings $findings -Seen $seen -Finding (
                            New-OneImAuditFinding -RuleId $rule.Id -RuleCatalog $RuleCatalog -SourceLookup $SourceLookup `
                                -FilePath $FilePath -RelativePath $RelativePath -Line ($i + 1) `
                                -Evidence $trimmed `
                                -TriggeringScenario $triggeringScenario `
                                -Remediation $remediation `
                                -TestIdeas $testIdeas
                        )
                    }
                }
            }
        }
    }

    # --- CNC-family coded detectors (CNC601, CNC602) ---
    $hasConcurrencyRules = @($RuleCatalog.Keys | Where-Object { [string]$_ -like "CNC*" }).Count -gt 0
    if ($hasConcurrencyRules -and (Get-Command Get-OneImConcurrencyFindings -ErrorAction SilentlyContinue)) {
        try {
            $cncFindings = @(Get-OneImConcurrencyFindings `
                -Lines $lines -FilePath $FilePath -RelativePath $RelativePath `
                -RuleCatalog $RuleCatalog -SourceLookup $SourceLookup)
            foreach ($f in $cncFindings) {
                $dedupKey = "{0}:{1}:{2}" -f $f.rule_id, $f.relative_path, $f.line
                if (-not $seen.ContainsKey($dedupKey)) {
                    $seen[$dedupKey] = $true
                    $findings.Add($f)
                }
            }
        } catch {
            Write-Warning ("Concurrency detectors failed for '{0}': {1}" -f $RelativePath, $_.Exception.Message)
        }
    }

    $hasApiServerRules = @($RuleCatalog.Keys | Where-Object { [string]$_ -like "API*" }).Count -gt 0
    if ($hasApiServerRules -and (Get-Command Get-OneImApiServerFindings -ErrorAction SilentlyContinue)) {
        try {
            $apiFindings = @(Get-OneImApiServerFindings `
                -Lines $lines -FilePath $FilePath -RelativePath $RelativePath `
                -RuleCatalog $RuleCatalog -SourceLookup $SourceLookup)
            foreach ($f in $apiFindings) {
                $dedupKey = "{0}:{1}:{2}" -f $f.rule_id, $f.relative_path, $f.line
                if (-not $seen.ContainsKey($dedupKey)) {
                    $seen[$dedupKey] = $true
                    $findings.Add($f)
                }
            }
        } catch {
            Write-Warning ("API Server detectors failed for '{0}': {1}" -f $RelativePath, $_.Exception.Message)
        }
    }

    return $findings.ToArray()
}

Export-ModuleMember -Function `
    Get-OneImAuditHeaderLineNumber, `
    Test-OneImAuditNearbyThrow, `
    Test-OneImAuditNearbyDispose, `
    Get-OneImAuditLoopDepthMap, `
    Get-OneImAuditStatementRange, `
    Get-OneImAuditPreviousMeaningfulLines, `
    Test-OneImAuditConditionalGuardNearby, `
    Get-OneImAuditTriggerWriteFields, `
    Test-OneImAuditTriggerFieldGuarded, `
    Test-OneImAuditIdentifierLikeTriggerField, `
    Test-OneImAuditPathScopeMatch, `
    Invoke-OneImDeclarativeRulePass, `
    Get-OneImFileFindings
