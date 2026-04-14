Set-StrictMode -Version Latest

function ConvertTo-OneImAuditHtmlReport {
    param(
        [Parameter(Mandatory)]
        [object]$Report
    )

    $html = New-Object System.Text.StringBuilder
    $null = $html.AppendLine("<!doctype html>")
    $null = $html.AppendLine("<html><head><meta charset='utf-8'><title>OneIM VB.NET Audit Report</title>")
    $null = $html.AppendLine("<style>body{font-family:Segoe UI,Arial,sans-serif;margin:24px;color:#1a1a1a;}table{border-collapse:collapse;width:100%;margin-top:16px;}th,td{border:1px solid #d0d7de;padding:8px;vertical-align:top;}th{background:#f6f8fa;text-align:left;}code{font-family:Consolas,monospace;} .sev-high{color:#b42318;font-weight:600;} .sev-medium{color:#b54708;font-weight:600;} .sev-low{color:#175cd3;font-weight:600;} .muted{color:#667085;} ul{margin-top:4px;} .hist-table{width:auto;margin-top:12px;} .hist-table th,.hist-table td{padding:6px 12px;} .bar{display:inline-block;height:10px;border-radius:3px;vertical-align:middle;margin-right:6px;} .bar-high{background:#b42318;} .bar-medium{background:#b54708;} .bar-low{background:#175cd3;} .file-group-hdr td{background:#eef2f6;font-weight:600;padding:6px 8px;cursor:pointer;user-select:none;} .file-group-hdr td:before{content:'▼ ';font-size:10px;} .file-group-hdr.collapsed td:before{content:'▶ ';} #sev-filters{margin:12px 0;} #sev-filters label{margin-right:14px;cursor:pointer;} #file-index{margin:12px 0 0;padding:0;list-style:none;display:flex;flex-wrap:wrap;gap:6px;} #file-index li a{display:inline-block;padding:3px 8px;background:#f6f8fa;border:1px solid #d0d7de;border-radius:4px;text-decoration:none;color:#1a1a1a;font-size:13px;} #file-index li a:hover{background:#eef2f6;} @media print{#sev-filters,#file-index{display:none;} tr{page-break-inside:avoid;} .file-group-hdr td{background:#f6f8fa !important;} a{color:inherit;text-decoration:none;}} .score-cards{display:flex;flex-wrap:wrap;gap:12px;margin:12px 0;} .score-card{border:1px solid #d0d7de;border-radius:8px;padding:12px 20px;min-width:120px;text-align:center;} .score-label{font-size:12px;color:#667085;margin-bottom:4px;text-transform:uppercase;letter-spacing:0.5px;} .score-value{font-size:28px;font-weight:700;} .score-green{background:#f0fdf4;border-color:#86efac;} .score-green .score-value{color:#166534;} .score-yellow{background:#fefce8;border-color:#fde047;} .score-yellow .score-value{color:#854d0e;} .score-orange{background:#fff7ed;border-color:#fdba74;} .score-orange .score-value{color:#9a3412;} .score-red{background:#fef2f2;border-color:#fca5a5;} .score-red .score-value{color:#991b1b;}</style>
<script>function applyFilters(){var c={};['high','medium','low'].forEach(function(s){c[s]=document.getElementById('filter-'+s).checked;});var g={};document.querySelectorAll('tr[data-sev]').forEach(function(r){var hdr=document.querySelector('tr.file-group-hdr[data-grp='+r.dataset.grp+']');var collapsed=hdr&&hdr.classList.contains('collapsed');var sevOk=c[r.dataset.sev];r.style.display=(sevOk&&!collapsed)?'':'none';if(g[r.dataset.grp]===undefined)g[r.dataset.grp]=false;if(sevOk)g[r.dataset.grp]=true;});document.querySelectorAll('tr.file-group-hdr').forEach(function(r){r.style.display=(g[r.dataset.grp]!==false)?'':'none';});}function toggleGroup(hdr){hdr.classList.toggle('collapsed');var grp=hdr.dataset.grp;var c={};['high','medium','low'].forEach(function(s){c[s]=document.getElementById('filter-'+s).checked;});var collapsed=hdr.classList.contains('collapsed');document.querySelectorAll('tr[data-grp='+grp+'][data-sev]').forEach(function(r){r.style.display=(collapsed||!c[r.dataset.sev])?'':'none';});}</script>
</head><body>")
    $null = $html.AppendLine("<h1>OneIM VB.NET Audit Report</h1>")
    $null = $html.AppendLine(("<p><strong>Generated:</strong> {0}<br><strong>OneIM version:</strong> {1}<br><strong>Target path:</strong> <code>{2}</code><br><strong>Reference repo path:</strong> <code>{3}</code></p>" -f `
            [System.Net.WebUtility]::HtmlEncode($Report.generated_at), `
            [System.Net.WebUtility]::HtmlEncode($Report.oneim_version), `
            [System.Net.WebUtility]::HtmlEncode($Report.target_path), `
            [System.Net.WebUtility]::HtmlEncode($Report.reference_repo_path)))
    if ($Report.target_root) {
        $null = $html.AppendLine(("<p><strong>Audit root:</strong> <code>{0}</code></p>" -f [System.Net.WebUtility]::HtmlEncode($Report.target_root)))
    }
    if (@($Report.selected_target_paths).Count -gt 1) {
        $null = $html.AppendLine("<h2>Selected Target Paths</h2><ul>")
        foreach ($target in @($Report.selected_target_paths)) {
            $null = $html.AppendLine(("<li><code>{0}</code></li>" -f [System.Net.WebUtility]::HtmlEncode([string]$target)))
        }
        $null = $html.AppendLine("</ul>")
    }

    $summary = $Report.summary
    $null = $html.AppendLine("<h2>Executive Summary</h2>")
    $null = $html.AppendLine("<ul>")
    $null = $html.AppendLine(("<li>Files audited: {0}</li>" -f $summary.files_audited))
    $null = $html.AppendLine(("<li>Detected findings: {0}</li>" -f $summary.detected_findings))
    $null = $html.AppendLine(("<li>Reported findings: {0}</li>" -f $summary.reported_findings))
    $null = $html.AppendLine(("<li>Omitted duplicate examples: {0}</li>" -f $summary.omitted_examples))
    $null = $html.AppendLine(("<li>Gating findings: {0}</li>" -f $summary.gating_findings))
    $null = $html.AppendLine(("<li>Correctness: {0}, Security: {1}, Performance: {2}</li>" -f $summary.correctness_findings, $summary.security_findings, $summary.performance_findings))
    $null = $html.AppendLine("</ul>")

    # Severity x category histogram
    $categories = @("correctness","security","reliability","performance","concurrency")
    $severities  = @("high","medium","low")
    # Build a hashtable: [severity][category] = count
    $hist = @{}
    foreach ($sev in $severities) { $hist[$sev] = @{}; foreach ($cat in $categories) { $hist[$sev][$cat] = 0 } }
    $maxCount = 0
    foreach ($f in @($Report.findings)) {
        $s = [string]$f.severity; $c = [string]$f.category
        if ($hist.ContainsKey($s) -and $hist[$s].ContainsKey($c)) {
            $hist[$s][$c]++
            if ($hist[$s][$c] -gt $maxCount) { $maxCount = $hist[$s][$c] }
        }
    }
    $null = $html.AppendLine("<h2>Finding Breakdown</h2>")
    $null = $html.AppendLine("<table class='hist-table'><thead><tr><th>Severity</th>")
    foreach ($cat in $categories) { $null = $html.AppendLine(("<th>{0}</th>" -f [System.Net.WebUtility]::HtmlEncode($cat))) }
    $null = $html.AppendLine("<th>Total</th></tr></thead><tbody>")
    foreach ($sev in $severities) {
        $rowTotal = 0
        foreach ($cat in $categories) { $rowTotal += $hist[$sev][$cat] }
        $null = $html.AppendLine(("<tr><td class='sev-{0}'>{0}</td>" -f [System.Net.WebUtility]::HtmlEncode($sev)))
        foreach ($cat in $categories) {
            $cnt = $hist[$sev][$cat]
            if ($cnt -gt 0) {
                $barWidth = if ($maxCount -gt 0) { [int][Math]::Max(4, [Math]::Round(40 * $cnt / $maxCount)) } else { 0 }
                $null = $html.AppendLine(("<td><span class='bar bar-{0}' style='width:{1}px'></span>{2}</td>" -f [System.Net.WebUtility]::HtmlEncode($sev), $barWidth, $cnt))
            } else {
                $null = $html.AppendLine("<td class='muted'>&mdash;</td>")
            }
        }
        $null = $html.AppendLine(("<td><strong>{0}</strong></td></tr>" -f $rowTotal))
    }
    $null = $html.AppendLine("</tbody></table>")

    # Category risk score cards
    $categoryScoresProp = $Report.PSObject.Properties.Match('category_scores')
    $categoryScoresData = if ($categoryScoresProp.Count -gt 0) { $Report.category_scores } else { $null }
    if ($null -ne $categoryScoresData) {
        $null = $html.AppendLine("<h2>Category Risk Scores</h2>")
        $null = $html.AppendLine("<p class='muted' style='margin-top:-8px;font-size:13px;'>Weighted score per audited file (high&times;3 + medium&times;2 + low&times;1). Lower is better.</p>")
        $null = $html.AppendLine("<div class='score-cards'>")
        $catLabels = [ordered]@{
            correctness = "Correctness"
            security    = "Security"
            reliability = "Reliability"
            performance = "Performance"
            concurrency = "Concurrency"
            overall     = "Overall"
        }
        foreach ($catKey in $catLabels.Keys) {
            $entry = $categoryScoresData.$catKey
            if ($null -eq $entry) { continue }
            $scoreVal   = [string]$entry.score
            $colorClass = [string]$entry.color
            $label      = $catLabels[$catKey]
            $isOverall  = ($catKey -eq "overall")
            $cardStyle  = if ($isOverall) { "margin-top:12px;border-top:2px solid #d0d7de;padding-top:12px;" } else { "" }
            $null = $html.AppendLine(("<div class='score-card {0}' style='{1}'><div class='score-label'>{2}</div><div class='score-value'>{3}</div></div>" -f `
                [System.Net.WebUtility]::HtmlEncode($colorClass), $cardStyle, `
                [System.Net.WebUtility]::HtmlEncode($label), `
                [System.Net.WebUtility]::HtmlEncode($scoreVal)))
        }
        $null = $html.AppendLine("</div>")
    }

    $refInfo = $Report.reference_validation
    $null = $html.AppendLine("<h2>Reference Validation</h2>")
    $null = $html.AppendLine("<ul>")
    $null = $html.AppendLine(("<li>Layout mode: {0}</li>" -f [System.Net.WebUtility]::HtmlEncode($refInfo.mode)))
    $null = $html.AppendLine(("<li>Version root: <code>{0}</code></li>" -f [System.Net.WebUtility]::HtmlEncode($refInfo.version_root)))
    $null = $html.AppendLine(("<li>OOTB root used for comparison: <code>{0}</code></li>" -f [System.Net.WebUtility]::HtmlEncode($refInfo.primary_ootb_root)))
    $null = $html.AppendLine(("<li>OOTB files available: {0}</li>" -f $refInfo.ootb_file_count))
    $null = $html.AppendLine(("<li>Promoted custom roots: {0}</li>" -f $refInfo.promoted_custom_root_count))
    $null = $html.AppendLine(("<li>Candidate custom roots: {0}</li>" -f $refInfo.candidate_custom_root_count))
    $null = $html.AppendLine("</ul>")

    if (@($Report.omitted_example_summaries).Count -gt 0) {
        $null = $html.AppendLine("<h2>Noise Controls</h2><table><thead><tr><th>Rule</th><th>File</th><th>Reported</th><th>Omitted</th></tr></thead><tbody>")
        foreach ($item in @($Report.omitted_example_summaries)) {
            $null = $html.AppendLine("<tr>")
            $null = $html.AppendLine(("<td><strong>{0}</strong></td>" -f [System.Net.WebUtility]::HtmlEncode($item.rule_id)))
            $null = $html.AppendLine(("<td><code>{0}</code></td>" -f [System.Net.WebUtility]::HtmlEncode($item.relative_path)))
            $null = $html.AppendLine(("<td>{0}</td>" -f [System.Net.WebUtility]::HtmlEncode([string]$item.reported_examples)))
            $null = $html.AppendLine(("<td>{0}</td>" -f [System.Net.WebUtility]::HtmlEncode([string]$item.omitted_examples)))
            $null = $html.AppendLine("</tr>")
        }
        $null = $html.AppendLine("</tbody></table>")
    }

    if (@($Report.unresolved_questions).Count -gt 0) {
        $null = $html.AppendLine("<h2>Unresolved Questions</h2><ul>")
        foreach ($question in @($Report.unresolved_questions)) {
            $null = $html.AppendLine(("<li>{0}</li>" -f [System.Net.WebUtility]::HtmlEncode($question)))
        }
        $null = $html.AppendLine("</ul>")
    }

    $null = $html.AppendLine("<h2>Findings</h2>")
    $null = $html.AppendLine("<div id='sev-filters'>Filter by severity:")
    $null = $html.AppendLine("  <label><input type='checkbox' id='filter-high'   checked onchange='applyFilters()'> <span class='sev-high'>High</span></label>")
    $null = $html.AppendLine("  <label><input type='checkbox' id='filter-medium' checked onchange='applyFilters()'> <span class='sev-medium'>Medium</span></label>")
    $null = $html.AppendLine("  <label><input type='checkbox' id='filter-low'    checked onchange='applyFilters()'> <span class='sev-low'>Low</span></label>")
    $null = $html.AppendLine("</div>")

    # Group findings by relative_path; non-file findings (relative_path="") go last
    $allFindings = @($Report.findings)
    $fileGroups = [ordered]@{}
    foreach ($f in $allFindings) {
        $key = if ([string]$f.relative_path -ne "") { [string]$f.relative_path } else { "`0cross-file" }
        if (-not $fileGroups.Contains($key)) { $fileGroups[$key] = [System.Collections.Generic.List[object]]::new() }
        $fileGroups[$key].Add($f)
    }

    # File index — jump-to links, one per group; hidden when printing
    if ($fileGroups.Count -gt 1) {
        $null = $html.AppendLine("<ul id='file-index'>")
        $idxCounter = 0
        foreach ($fileKey in $fileGroups.Keys) {
            $displayPath = if ($fileKey -eq "`0cross-file") { "(cross-file findings)" } else { $fileKey }
            $cnt = $fileGroups[$fileKey].Count
            $null = $html.AppendLine(("<li><a href='#grp-{0}'>{1} ({2})</a></li>" -f $idxCounter, [System.Net.WebUtility]::HtmlEncode($displayPath), $cnt))
            $idxCounter++
        }
        $null = $html.AppendLine("</ul>")
    }

    $null = $html.AppendLine("<table><thead><tr><th>Severity</th><th>Rule</th><th>Location</th><th>Evidence</th><th>Remediation</th><th>Sources</th></tr></thead><tbody>")
    $grpIdx = 0
    foreach ($fileKey in $fileGroups.Keys) {
        $groupFindings = $fileGroups[$fileKey]
        $displayPath = if ($fileKey -eq "`0cross-file") { "(cross-file findings)" } else { $fileKey }
        $null = $html.AppendLine(("<tr id='grp-{0}' class='file-group-hdr' data-grp='{0}' onclick='toggleGroup(this)'><td colspan='6'>{1} &mdash; {2} finding(s)</td></tr>" -f $grpIdx, [System.Net.WebUtility]::HtmlEncode($displayPath), $groupFindings.Count))
        foreach ($finding in $groupFindings) {
            $sev   = [string]$finding.severity
            $sevClass = "sev-{0}" -f $sev
            $sourceLinks = @()
            foreach ($source in @($finding.sources)) {
                $safeTitle = [System.Net.WebUtility]::HtmlEncode($source.title)
                $safeUrl   = [System.Net.WebUtility]::HtmlEncode($source.url)
                $sourceLinks += "<a href='$safeUrl'>$safeTitle</a>"
            }
            $location = "{0}:{1}" -f $finding.relative_path, $finding.line
            $null = $html.AppendLine(("<tr data-sev='{0}' data-grp='{1}'>" -f $sev, $grpIdx))
            $null = $html.AppendLine(("<td class='{0}'>{1}<br><span class='muted'>{2}</span></td>" -f $sevClass, [System.Net.WebUtility]::HtmlEncode($sev), [System.Net.WebUtility]::HtmlEncode($finding.confidence_label)))
            $null = $html.AppendLine(("<td><strong>{0}</strong><br><span class='muted'>{1}</span></td>" -f [System.Net.WebUtility]::HtmlEncode($finding.rule_id), [System.Net.WebUtility]::HtmlEncode($finding.title)))
            $null = $html.AppendLine(("<td><code>{0}</code></td>" -f [System.Net.WebUtility]::HtmlEncode($location)))
            $null = $html.AppendLine(("<td>{0}<br><span class='muted'>{1}</span></td>" -f [System.Net.WebUtility]::HtmlEncode($finding.evidence), [System.Net.WebUtility]::HtmlEncode($finding.triggering_scenario)))
            $null = $html.AppendLine(("<td>{0}</td>" -f [System.Net.WebUtility]::HtmlEncode($finding.remediation)))
            $null = $html.AppendLine(("<td>{0}</td>" -f ($sourceLinks -join "<br>")))
            $null = $html.AppendLine("</tr>")
        }
        $grpIdx++
    }
    $null = $html.AppendLine("</tbody></table>")
    $null = $html.AppendLine("</body></html>")
    return $html.ToString()
}

Export-ModuleMember -Function ConvertTo-OneImAuditHtmlReport
