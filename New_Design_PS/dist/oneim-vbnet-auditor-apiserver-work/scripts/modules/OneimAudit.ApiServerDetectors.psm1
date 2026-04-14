Set-StrictMode -Version Latest

function Get-OneImApiServerFindings {
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
        [hashtable]$SourceLookup
    )

    $findings = New-Object 'System.Collections.Generic.List[object]'
    $seen = @{}

    for ($index = 0; $index -lt $Lines.Count; $index++) {
        $lineNumber = $index + 1
        $trimmed = $Lines[$index].Trim()

        if ([string]::IsNullOrWhiteSpace($trimmed) -or $trimmed.StartsWith("'")) {
            continue
        }

        if ($RuleCatalog.ContainsKey("API600") -and $trimmed -match '(?i)\bAwaitTasks\s*=\s*True\b') {
            Add-OneImAuditFinding -Findings $findings -Seen $seen -Finding (
                New-OneImAuditFinding -RuleId "API600" -RuleCatalog $RuleCatalog -SourceLookup $SourceLookup -FilePath $FilePath -RelativePath $RelativePath -Line $lineNumber `
                    -Evidence $trimmed `
                    -TriggeringScenario "The API Server reference docs state that enabling ObservableEventStreamResponse.AwaitTasks can cause deadlocks while outstanding writes are awaited." `
                    -Remediation "Keep AwaitTasks disabled unless you have a reviewed, proven need for synchronous write draining and have tested the shutdown path for deadlock risk." `
                    -TestIdeas @(
                        "Exercise the event-stream shutdown path under concurrent writes and confirm the stream closes without hanging.",
                        "Set AwaitTasks to False and verify the endpoint still drains work acceptably for the target workload."
                    )
            )
        }

        if ($RuleCatalog.ContainsKey("API610") -and $trimmed -match '(?i)\bIncludeAllExceptionInfo\s*=\s*True\b') {
            Add-OneImAuditFinding -Findings $findings -Seen $seen -Finding (
                New-OneImAuditFinding -RuleId "API610" -RuleCatalog $RuleCatalog -SourceLookup $SourceLookup -FilePath $FilePath -RelativePath $RelativePath -Line $lineNumber `
                    -Evidence $trimmed `
                    -TriggeringScenario "Server-level API configuration explicitly enables full exception information, which may expose more server internals than intended to API consumers." `
                    -Remediation "Default to False for externally reachable environments and enable full exception detail only in tightly controlled troubleshooting scenarios." `
                    -TestIdeas @(
                        "Trigger a handled API failure and confirm the client no longer receives unnecessary internal exception detail.",
                        "Verify operational diagnostics still capture the needed server-side details after disabling the setting."
                    ) `
                    -Extra @{ confidence_score = 55 }
            )
        }

        if ($RuleCatalog.ContainsKey("API620") -and $trimmed -match '(?i)\bEnableEndpointSecurityPermissionCheck\s*=\s*False\b') {
            Add-OneImAuditFinding -Findings $findings -Seen $seen -Finding (
                New-OneImAuditFinding -RuleId "API620" -RuleCatalog $RuleCatalog -SourceLookup $SourceLookup -FilePath $FilePath -RelativePath $RelativePath -Line $lineNumber `
                    -Evidence $trimmed `
                    -TriggeringScenario "Endpoint security permission checks are explicitly disabled in API Server configuration, which deserves a manual review of the intended access boundary." `
                    -Remediation "Enable endpoint security permission checks by default, and keep any exception documented, environment-scoped, and deliberately approved." `
                    -TestIdeas @(
                        "Run the affected endpoint with a principal lacking the expected permission and confirm access is rejected when the check is enabled.",
                        "Document why the permission check is disabled if the behavior is intentional for a private administrative surface."
                    ) `
                    -Extra @{ confidence_score = 58 }
            )
        }

        if ($RuleCatalog.ContainsKey("API630") -and $trimmed -match '(?i)\bCorsOrigins\b' -and $trimmed -match '(?i)"\*"') {
            Add-OneImAuditFinding -Findings $findings -Seen $seen -Finding (
                New-OneImAuditFinding -RuleId "API630" -RuleCatalog $RuleCatalog -SourceLookup $SourceLookup -FilePath $FilePath -RelativePath $RelativePath -Line $lineNumber `
                    -Evidence $trimmed `
                    -TriggeringScenario "The API Server CORS origin list includes a wildcard, which broadens browser-based cross-origin access and should be reviewed against the intended trust boundary." `
                    -Remediation "Replace wildcard origins with the explicit trusted origin list that actually needs browser access to the API surface." `
                    -TestIdeas @(
                        "Issue a browser-origin request from an untrusted origin and confirm it is rejected after narrowing the allowed origins.",
                        "Verify the intended first-party web clients still pass preflight and normal requests with the explicit allowlist."
                    ) `
                    -Extra @{ confidence_score = 55 }
            )
        }

        if ($RuleCatalog.ContainsKey("API640") -and $trimmed -match '(?i)\b(X-Forwarded-For|Forwarded)\b') {
            $looksLikeHeaderRead = (
                $trimmed -match '(?i)\b(Header|Headers|TryGetValue|ContainsKey|Item)\b' -or
                $trimmed -match '(?i)\("?(X-Forwarded-For|Forwarded)"?\)'
            )

            if ($looksLikeHeaderRead -and $trimmed -notmatch '(?i)\bGetRequestIpAddress\s*\(') {
                Add-OneImAuditFinding -Findings $findings -Seen $seen -Finding (
                    New-OneImAuditFinding -RuleId "API640" -RuleCatalog $RuleCatalog -SourceLookup $SourceLookup -FilePath $FilePath -RelativePath $RelativePath -Line $lineNumber `
                        -Evidence $trimmed `
                        -TriggeringScenario "The API Server docs expose a GetRequestIpAddress helper for IRequest. Manual forwarded-header parsing can drift from the framework helper and proxy configuration expectations." `
                        -Remediation "Prefer the IRequest.GetRequestIpAddress helper so IP resolution stays aligned with the API Server request pipeline and proxy handling behavior." `
                        -TestIdeas @(
                            "Exercise direct and reverse-proxy requests and confirm the resolved client IP still matches expectations after switching to GetRequestIpAddress.",
                            "Verify spoofed forwarded headers are handled consistently with the intended proxy configuration."
                        ) `
                        -Extra @{ confidence_score = 65 }
                )
            }
        }
    }

    return $findings.ToArray()
}

Export-ModuleMember -Function Get-OneImApiServerFindings
