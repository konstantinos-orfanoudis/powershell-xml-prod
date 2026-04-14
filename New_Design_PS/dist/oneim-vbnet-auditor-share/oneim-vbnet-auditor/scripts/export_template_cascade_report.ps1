<#
.SYNOPSIS
Builds a cascade dependency graph for a OneIM template and exports an HTML report.

.DESCRIPTION
Starting from a root "<Table>.<Column>" template, this script:
  1. Loads the schema snapshot (column -> FK target, parent -> children indexes).
  2. Loads the template catalog JSON (produced by export_live_db_templates.ps1 or equivalent).
  3. Parses each template's expression text for three edge types:
       GetTriggerValue("FieldName")  — reads a field value from the triggering object
       $FieldName$                   — references another column on the same table
       FK(Table.Column)              — traverses a foreign key to a related table
  4. Expands FK hops through the snapshot's column_to_fk_target index.
  5. Derives successor nodes using the parent_to_children reverse index.
  6. Detects cycles via iterative DFS; cycle paths are recorded.
  7. Optionally merges benchmark timings from a benchmark-report.json.
  8. Writes a single self-contained HTML report (no external assets).

The HTML report includes:
  - Root template info panel
  - Collapsible predecessor tree
  - Collapsible successor tree
  - Node table: type, name, avg_elapsed_ms, threshold status
  - Bottleneck node highlighted in red (highest avg_ms)
  - Cycle nodes/edges shown in amber with explicit path
  - Threshold overruns shown in red when thresholds were loaded

.PARAMETER TemplateName
Root template in "<Table>.<Column>" format.

.PARAMETER SchemaSnapshotPath
Path to schema-snapshot.json. If omitted, the script searches output\oneim-schema\ for
the most recent snapshot.

.PARAMETER TemplateCatalogPath
Path to a template catalog JSON. Expected shape: { "templates": [{ "table_name", "column_name",
"template_value", ... }] }. If omitted, cascade analysis is limited to FK-derived edges only.

.PARAMETER BenchmarkReportPath
Optional path to a benchmark-report.json from invoke_oneim_benchmark.ps1.
When supplied, timing data is merged into node rows.

.PARAMETER ThresholdsFile
Optional JSON thresholds file. When supplied, threshold overruns are highlighted in the report.

.PARAMETER OutputDir
Destination directory for the HTML report. Defaults to output\oneim-cascade\<timestamp>\.

.PARAMETER MaxDepth
Maximum traversal depth for the HTML tree renderer (predecessors and successors). Defaults to 20.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$TemplateName,

    [Parameter()]
    [string]$SchemaSnapshotPath,

    [Parameter()]
    [string]$TemplateCatalogPath,

    [Parameter()]
    [string]$BenchmarkReportPath,

    [Parameter()]
    [string]$ThresholdsFile,

    [Parameter()]
    [string]$OutputDir,

    [Parameter()]
    [ValidateRange(1, 100)]
    [int]$MaxDepth = 20
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$scriptRoot = Split-Path -Parent $PSCommandPath
$moduleRoot = Join-Path $scriptRoot "modules"

Import-Module (Join-Path $moduleRoot "OneimAudit.Graph.psm1") -Force

# ---------------------------------------------------------------------------
# Helper: HTML-escape
# ---------------------------------------------------------------------------
function Escape-Html {
    param([string]$Text)
    return $Text `
        -replace '&', '&amp;' `
        -replace '<', '&lt;' `
        -replace '>', '&gt;' `
        -replace '"', '&quot;'
}

# ---------------------------------------------------------------------------
# Resolve schema snapshot
# ---------------------------------------------------------------------------
$resolvedSchemaPath = $null

if (-not [string]::IsNullOrWhiteSpace($SchemaSnapshotPath)) {
    $resolvedSchemaPath = [System.IO.Path]::GetFullPath($SchemaSnapshotPath)
} else {
    $searchRoot = Join-Path (Get-Location).Path "output\oneim-schema"
    if (Test-Path -LiteralPath $searchRoot) {
        $candidate = Get-ChildItem -Path $searchRoot -Filter "schema-snapshot.json" -Recurse |
            Sort-Object LastWriteTime -Descending |
            Select-Object -First 1
        if ($candidate) { $resolvedSchemaPath = $candidate.FullName }
    }
}

if (-not $resolvedSchemaPath -or -not (Test-Path -LiteralPath $resolvedSchemaPath)) {
    throw "Schema snapshot not found. Supply -SchemaSnapshotPath or run export_oneim_schema_snapshot.ps1 first."
}

Write-Host ("Loading schema snapshot: {0}" -f $resolvedSchemaPath)
$schema = Get-Content -LiteralPath $resolvedSchemaPath -Raw | ConvertFrom-Json

# Rebuild hashtable indexes from the JSON (PSCustomObject properties)
$colToFk          = @{}
$parentToChildren = @{}

foreach ($prop in $schema.indexes.column_to_fk_target.PSObject.Properties) {
    $colToFk[$prop.Name] = $prop.Value
}
foreach ($prop in $schema.indexes.parent_to_children.PSObject.Properties) {
    $parentToChildren[$prop.Name] = @($prop.Value)
}

# ---------------------------------------------------------------------------
# Load template catalog
# ---------------------------------------------------------------------------
$templateCatalog = @{}   # key: "Table.Column" -> template_value string

if (-not [string]::IsNullOrWhiteSpace($TemplateCatalogPath)) {
    $catPath = [System.IO.Path]::GetFullPath($TemplateCatalogPath)
    if (-not (Test-Path -LiteralPath $catPath)) {
        throw "Template catalog not found: '$catPath'."
    }
    Write-Host ("Loading template catalog: {0}" -f $catPath)
    $catRaw = Get-Content -LiteralPath $catPath -Raw | ConvertFrom-Json
    foreach ($t in @($catRaw.templates)) {
        $key = ("{0}.{1}" -f [string]$t.table_name, [string]$t.column_name)
        $templateCatalog[$key] = [string]$t.template_value
    }
    Write-Host ("  {0} templates loaded." -f $templateCatalog.Count)
}

# ---------------------------------------------------------------------------
# Load benchmark data
# ---------------------------------------------------------------------------
$benchData = @{}   # key: "template::Table.Column" -> result object

if (-not [string]::IsNullOrWhiteSpace($BenchmarkReportPath)) {
    $bPath = [System.IO.Path]::GetFullPath($BenchmarkReportPath)
    if (Test-Path -LiteralPath $bPath) {
        $bench = Get-Content -LiteralPath $bPath -Raw | ConvertFrom-Json
        foreach ($r in @($bench.results)) {
            $bKey = ("{0}::{1}" -f [string]$r.surface, [string]$r.name)
            $benchData[$bKey] = $r
        }
        Write-Host ("Loaded {0} benchmark results." -f $benchData.Count)
    } else {
        Write-Warning ("Benchmark report not found: '{0}'." -f $bPath)
    }
}

# ---------------------------------------------------------------------------
# Load thresholds
# ---------------------------------------------------------------------------
$thresholds = @{}
if (-not [string]::IsNullOrWhiteSpace($ThresholdsFile)) {
    $tPath = [System.IO.Path]::GetFullPath($ThresholdsFile)
    if (Test-Path -LiteralPath $tPath) {
        $tRaw = Get-Content -LiteralPath $tPath -Raw | ConvertFrom-Json
        foreach ($entry in @($tRaw)) {
            $tKey = ("{0}::{1}" -f [string]$entry.surface, [string]$entry.name)
            $thresholds[$tKey] = $entry
        }
    }
}

# ---------------------------------------------------------------------------
# Build graph
# ---------------------------------------------------------------------------
Write-Host "Building cascade graph..."

$graph = New-OneImAuditGraph -BenchData $benchData -TemplateCatalog $templateCatalog

Invoke-OneImAuditGraphBFS `
    -Graph            $graph `
    -RootKey          $TemplateName `
    -ParentToChildren $parentToChildren

Build-OneImAuditGraphReverseAdj -Graph $graph

Find-OneImAuditGraphCycles -Graph $graph

$sccs       = Find-OneImAuditSCCs -Graph $graph
$stats      = Get-OneImAuditGraphStats -Graph $graph
$topoResult = Invoke-OneImAuditTopologicalSort -Graph $graph
$depthHist  = Get-OneImAuditDepthHistogram -Graph $graph

# Advanced graph analyses — each adds a distinct layer of insight
$criticalPath   = Get-OneImAuditCriticalPath           -Graph $graph
$artPoints      = @(Find-OneImAuditArticulationPoints  -Graph $graph)
$fasResult      = Get-OneImAuditFeedbackArcSet         -Graph $graph
$dominatorTree  = Build-OneImAuditDominatorTree        -Graph $graph -RootKey $TemplateName
$betweenness    = Get-OneImAuditBetweennessCentrality  -Graph $graph

# Local aliases so the HTML rendering helpers below can read graph data
# without taking the graph object as a parameter.
$nodes          = $graph.Nodes
$adjList        = $graph.AdjList
$reverseAdj     = $graph.ReverseAdj
$cycleEdges     = $graph.CycleEdges
$nodeCount      = $stats.node_count
$edgeCount      = $stats.edge_count
$cycleCount     = $stats.cycle_count
$topoOrder      = $topoResult.order
$cyclicKeys     = $topoResult.cycle_node_keys
$multiSccs      = @($sccs | Where-Object { $_.size -gt 1 })

Write-Host ("  {0} nodes, {1} edges, {2} cycle(s), {3} multi-node SCC(s)" -f $nodeCount, $edgeCount, $cycleCount, $multiSccs.Count)

# ---------------------------------------------------------------------------
# Identify bottleneck node
# ---------------------------------------------------------------------------
$bottleneckKey = $null
$bottleneckMs  = -1.0

foreach ($n in @($nodes.Values)) {
    if ($null -ne $n.avg_ms -and [double]$n.avg_ms -gt $bottleneckMs) {
        $bottleneckMs  = [double]$n.avg_ms
        $bottleneckKey = $n.key
    }
}

# ---------------------------------------------------------------------------
# Tree rendering helper (HTML) — uses $nodes and $bottleneckKey from above
# ---------------------------------------------------------------------------
function Render-TreeNode {
    param(
        [string]$NodeKey,
        [hashtable]$AdjMap,
        [int]$Depth,
        [int]$MaxD,
        [hashtable]$Visited
    )

    if ($Depth -gt $MaxD) { return "<li><em>(depth limit reached)</em></li>" }
    if ($Visited.ContainsKey($NodeKey)) {
        return "<li><span class='cycle-node'>" + (Escape-Html $NodeKey) + " <em>(already expanded)</em></span></li>"
    }

    $Visited[$NodeKey] = $true

    $n        = if ($nodes.Contains($NodeKey)) { $nodes[$NodeKey] } else { $null }
    $cssClass = "node"
    if ($n -and $n.in_cycle)           { $cssClass += " cycle-node" }
    if ($n -and $n.threshold_exceeded) { $cssClass += " threshold-fail" }
    if ($NodeKey -eq $bottleneckKey)   { $cssClass += " bottleneck" }

    $timingText = ""
    if ($n -and $null -ne $n.avg_ms) {
        $timingText = " <span class='timing'>[avg: {0}ms]</span>" -f $n.avg_ms
    }

    $childrenList = New-Object System.Collections.Generic.List[string]
    if ($AdjMap.ContainsKey($NodeKey)) {
        foreach ($c in $AdjMap[$NodeKey]) { $childrenList.Add([string]$c) }
    }

    $html = "<li><span class='$cssClass'>" + (Escape-Html $NodeKey) + $timingText + "</span>"

    if ($childrenList.Count -gt 0) {
        $html += "<details><summary>({0} child(ren))</summary><ul>" -f $childrenList.Count
        foreach ($child in $childrenList) {
            $childVisited = @{} + $Visited
            $html += Render-TreeNode -NodeKey $child -AdjMap $AdjMap -Depth ($Depth + 1) -MaxD $MaxD -Visited $childVisited
        }
        $html += "</ul></details>"
    }

    $html += "</li>"
    return $html
}

# ---------------------------------------------------------------------------
# Build node table rows
# ---------------------------------------------------------------------------
$nodeRows = foreach ($n in ($nodes.Values | Sort-Object -Property key)) {
    $rowClass = ""
    if ($n.in_cycle)               { $rowClass = "cycle-row" }
    if ($n.threshold_exceeded)     { $rowClass = "threshold-row" }
    if ($n.key -eq $bottleneckKey) { $rowClass = "bottleneck-row" }

    $avgText   = if ($null -ne $n.avg_ms) { "{0} ms" -f $n.avg_ms } else { "-" }
    $p95Text   = if ($null -ne $n.p95_ms) { "{0} ms" -f $n.p95_ms } else { "-" }
    $cycleText = if ($n.in_cycle) { "&#9888; Yes" } else { "No" }
    $threshText = if ($n.threshold_exceeded) { "&#9888; Exceeded" } else { "OK" }

    "<tr class='$rowClass'><td>" + (Escape-Html $n.key) + "</td><td>" + (Escape-Html $n.node_type) +
    "</td><td>$avgText</td><td>$p95Text</td><td>$cycleText</td><td>$threshText</td></tr>"
}

# ---------------------------------------------------------------------------
# Successor and predecessor tree HTML
# ---------------------------------------------------------------------------
$adjListHT    = @{}
$reverseAdjHT = @{}
foreach ($k in $adjList.Keys)    { $adjListHT[$k]    = $adjList[$k] }
foreach ($k in $reverseAdj.Keys) { $reverseAdjHT[$k] = $reverseAdj[$k] }

$successorHtml   = Render-TreeNode -NodeKey $TemplateName -AdjMap $adjListHT    -Depth 0 -MaxD $MaxDepth -Visited @{}
$predecessorHtml = Render-TreeNode -NodeKey $TemplateName -AdjMap $reverseAdjHT -Depth 0 -MaxD $MaxDepth -Visited @{}

# ---------------------------------------------------------------------------
# Cycle detail rows
# ---------------------------------------------------------------------------
$cycleRows = foreach ($ce in $cycleEdges) {
    $pathStr = ($ce.path | ForEach-Object { Escape-Html $_ }) -join " &#8594; "
    "<tr class='cycle-row'><td>" + (Escape-Html $ce.from) + "</td><td>" + (Escape-Html $ce.to) + "</td><td>$pathStr</td></tr>"
}

# ---------------------------------------------------------------------------
# Assemble HTML
# ---------------------------------------------------------------------------
$reportTitle = "OneIM Template Cascade Report - {0}" -f (Escape-Html $TemplateName)
$generatedAt = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

$html = @"
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>$reportTitle</title>
<style>
  body { font-family: Segoe UI, Arial, sans-serif; margin: 0; padding: 1rem 2rem; background: #f4f6f9; color: #222; }
  h1 { color: #1a3a5c; font-size: 1.4rem; border-bottom: 2px solid #1a3a5c; padding-bottom: .4rem; }
  h2 { font-size: 1.1rem; margin-top: 1.4rem; color: #1a3a5c; }
  .meta { background: #fff; border: 1px solid #dde3ec; border-radius: 6px; padding: .8rem 1.2rem; margin-bottom: 1rem; font-size: .9rem; }
  .meta span { display: inline-block; margin-right: 2rem; }
  table { border-collapse: collapse; width: 100%; font-size: .875rem; background: #fff; border-radius: 6px; overflow: hidden; }
  th { background: #1a3a5c; color: #fff; text-align: left; padding: .45rem .7rem; }
  td { padding: .4rem .7rem; border-bottom: 1px solid #e8ecf1; }
  tr:last-child td { border-bottom: none; }
  .bottleneck-row td { background: #fde8e8; font-weight: bold; }
  .cycle-row td { background: #fff3cd; }
  .threshold-row td { background: #fde8e8; }
  .bottleneck { color: #c0392b; font-weight: bold; }
  .cycle-node { color: #b7620a; }
  .threshold-fail { color: #c0392b; }
  .timing { color: #555; font-size: .8rem; }
  details > summary { cursor: pointer; font-size: .85rem; color: #1a3a5c; }
  ul { list-style: none; padding-left: 1.2rem; margin: .2rem 0; }
  li { margin: .1rem 0; }
  .section { background: #fff; border: 1px solid #dde3ec; border-radius: 6px; padding: .8rem 1.2rem; margin-bottom: 1rem; }
  .badge { display: inline-block; padding: .1rem .5rem; border-radius: 3px; font-size: .78rem; font-weight: bold; margin-left: .4rem; }
  .badge-red { background: #fde8e8; color: #c0392b; }
  .badge-amber { background: #fff3cd; color: #b7620a; }
  .badge-gray { background: #e8ecf1; color: #444; }
</style>
</head>
<body>
<h1>OneIM Template Cascade Report</h1>

<div class="meta">
  <span><strong>Root template:</strong> $(Escape-Html $TemplateName)</span>
  <span><strong>Generated:</strong> $generatedAt</span>
  <span><strong>Nodes:</strong> $nodeCount</span>
  <span><strong>Edges:</strong> $edgeCount</span>
  <span><strong>Cycles detected:</strong> $cycleCount$(if ($cycleCount -gt 0) { ' <span class="badge badge-amber">&#9888; Cycles</span>' } else { '' })</span>
  $(if ($bottleneckKey) { "<span><strong>Bottleneck:</strong> <span class='bottleneck'>$(Escape-Html $bottleneckKey)</span> ($bottleneckMs ms avg) <span class='badge badge-red'>Hot</span></span>" })
</div>

<div class="section">
  <h2>Predecessor Tree <span class="badge badge-gray">(what feeds into $( Escape-Html $TemplateName ))</span></h2>
  <ul>$predecessorHtml</ul>
</div>

<div class="section">
  <h2>Successor Tree <span class="badge badge-gray">(what $( Escape-Html $TemplateName ) feeds into)</span></h2>
  <ul>$successorHtml</ul>
</div>

<div class="section">
  <h2>All Nodes</h2>
  <table>
    <thead><tr><th>Node</th><th>Type</th><th>Avg ms</th><th>P95 ms</th><th>In Cycle</th><th>Threshold</th></tr></thead>
    <tbody>
      $($nodeRows -join "`n      ")
    </tbody>
  </table>
</div>

$(if ($cycleCount -gt 0) {
@"
<div class="section">
  <h2>Detected Cycles <span class="badge badge-amber">&#9888; $cycleCount cycle(s)</span></h2>
  <table>
    <thead><tr><th>From</th><th>To (back edge)</th><th>Cycle path</th></tr></thead>
    <tbody>
      $($cycleRows -join "`n      ")
    </tbody>
  </table>
</div>
"@
})

$(if ($multiSccs.Count -gt 0) {
    $sccRows = foreach ($scc in ($multiSccs | Sort-Object size -Descending)) {
        $memberStr = ($scc.members | Sort-Object | ForEach-Object { Escape-Html $_ }) -join ", "
        $riskBadge = if ($scc.concurrency_risk -eq "read-cycle") { "<span class='badge badge-amber'>read-cycle</span>" } else { "" }
        "<tr class='cycle-row'><td>$($scc.scc_id)</td><td>$($scc.size)</td><td>$memberStr</td><td>$riskBadge</td></tr>"
    }
@"
<div class="section">
  <h2>SCC Clusters <span class="badge badge-amber">&#9888; $($multiSccs.Count) mutual-dependency group(s)</span></h2>
  <p style="font-size:.88rem;color:#555;">Nodes within a cluster can all reach each other — any writer in the cluster creates a write-read-write risk under concurrent evaluation.</p>
  <table>
    <thead><tr><th>SCC</th><th>Size</th><th>Members</th><th>Risk</th></tr></thead>
    <tbody>
      $($sccRows -join "`n      ")
    </tbody>
  </table>
</div>
"@
})

<div class="section">
  <h2>Depth Histogram <span class="badge badge-gray">BFS levels from root</span></h2>
  <table>
    <thead><tr><th>Depth</th><th>Node count</th></tr></thead>
    <tbody>
      $(($depthHist | ForEach-Object { "<tr><td>$($_.depth)</td><td>$($_.count)</td></tr>" }) -join "`n      ")
    </tbody>
  </table>
</div>

<div class="section">
  <h2>Safe Evaluation Order <span class="badge badge-gray">$(if ($cyclicKeys.Count -gt 0) { "$($cyclicKeys.Count) cyclic node(s) excluded" } else { "no cycles - complete ordering" })</span></h2>
  $(if ($cyclicKeys.Count -gt 0) { "<p style='color:#b7620a;font-size:.88rem;'>&#9888; Nodes in cycles cannot be linearised and are omitted from this list. See Detected Cycles above.</p>" })
  <ol style="font-size:.875rem;column-count:2;column-gap:2rem;padding-left:1.4rem;">
    $(($topoOrder | ForEach-Object { "<li>$(Escape-Html $_)</li>" }) -join "`n    ")
  </ol>
</div>

$(
# ---------------------------------------------------------------------------
# Critical Path section
# ---------------------------------------------------------------------------
$cpNodes = $criticalPath.critical_path
$cpTotalMs = $criticalPath.total_ms
$cpHasBench = $criticalPath.has_benchmark_data
$cpBadge = if (-not $cpHasBench) { "<span class='badge badge-gray'>no timing data</span>" } `
           elseif ($cpNodes.Count -eq 0) { "<span class='badge badge-gray'>empty graph</span>" } `
           else { "<span class='badge badge-red'>$([Math]::Round($cpTotalMs,1)) ms total</span>" }
$cpRows = ($cpNodes | ForEach-Object {
    $n = if ($nodes.Contains($_)) { $nodes[$_] } else { $null }
    $ms = if ($n -and $null -ne $n.avg_ms) { "$($n.avg_ms) ms" } else { "-" }
    "<tr><td>$(Escape-Html $_)</td><td>$ms</td></tr>"
}) -join "`n      "
@"
<div class="section">
  <h2>Critical Path $cpBadge</h2>
  <p style="font-size:.88rem;color:#555;">
    <strong>What it is:</strong> The critical path is the chain of templates with the <em>highest combined evaluation time</em> from source to sink.
    It is the bottleneck that sets the lower bound on how fast the entire cascade can run &mdash; no amount of parallelism can make the cascade
    finish faster than the sum of times along this chain.<br>
    <strong>Why it matters:</strong> If you need to speed up the cascade, start here. Optimising any template <em>not</em> on the critical path
    will not reduce the total elapsed time.
  </p>
  $(if ($cpNodes.Count -gt 0) {
    "<table><thead><tr><th>Node (in order)</th><th>Avg ms</th></tr></thead><tbody>$cpRows</tbody></table>"
  } else {
    "<p style='color:#888;font-size:.88rem;'>No timing data available. Supply a benchmark report (-BenchmarkReportPath) to compute the critical path.</p>"
  })
</div>
"@
)

$(
# ---------------------------------------------------------------------------
# Articulation Points section
# ---------------------------------------------------------------------------
$apBadge = if ($artPoints.Count -eq 0) { "<span class='badge badge-gray'>none found</span>" } `
           else { "<span class='badge badge-amber'>&#9888; $($artPoints.Count) found</span>" }
$apRows = ($artPoints | Sort-Object | ForEach-Object {
    $n = if ($nodes.Contains($_)) { $nodes[$_] } else { $null }
    $ms = if ($n -and $null -ne $n.avg_ms) { "$($n.avg_ms) ms" } else { "-" }
    "<tr class='cycle-row'><td>$(Escape-Html $_)</td><td>$ms</td></tr>"
}) -join "`n      "
@"
<div class="section">
  <h2>Articulation Points (Single Points of Failure) $apBadge</h2>
  <p style="font-size:.88rem;color:#555;">
    <strong>What it is:</strong> An articulation point is a template node that, if removed or unavailable, would split the
    cascade into two or more disconnected parts. It is a <em>structural single point of failure</em>.<br>
    <strong>Why it matters:</strong> If an articulation point template throws an unhandled exception, evaluates to null when
    dependants expect a value, or is accidentally deleted, all templates that rely on it through that path stop receiving
    updates. These nodes deserve extra test coverage, explicit null-guards, and monitoring.
  </p>
  $(if ($artPoints.Count -gt 0) {
    "<table><thead><tr><th>Articulation Point</th><th>Avg ms</th></tr></thead><tbody>$apRows</tbody></table>"
  } else {
    "<p style='color:#888;font-size:.88rem;'>No articulation points found. The graph has no structural single points of failure.</p>"
  })
</div>
"@
)

$(
# ---------------------------------------------------------------------------
# Feedback Arc Set section
# ---------------------------------------------------------------------------
$fasBadge = if ($fasResult.count -eq 0) { "<span class='badge badge-gray'>no cycles to break</span>" } `
            else { "<span class='badge badge-amber'>&#9888; $($fasResult.count) edge(s)</span>" }
$fasRows = ($fasResult.edges | ForEach-Object {
    "<tr class='cycle-row'><td>$(Escape-Html $_.from)</td><td>$(Escape-Html $_.to)</td><td>SCC $($_.scc_id)</td></tr>"
}) -join "`n      "
@"
<div class="section">
  <h2>Feedback Arc Set (Minimum Cycle-Breaking Edges) $fasBadge</h2>
  <p style="font-size:.88rem;color:#555;">
    <strong>What it is:</strong> The feedback arc set is the smallest group of dependency edges whose removal would make
    every cycle in the graph disappear. Edges are selected with a greedy algorithm that keeps the most &ldquo;forward-flowing&rdquo;
    edges and marks the backward ones as candidates for removal.<br>
    <strong>Why it matters:</strong> OneIM evaluates templates in a topological order. A cycle means there is no safe order &mdash;
    template A needs B&rsquo;s value, and B needs A&rsquo;s value. The only practical fix is to break one of these dependencies.
    The table below shows <em>exactly which relationships to revisit</em> in Designer to resolve the cycle with the fewest changes.
  </p>
  $(if ($fasResult.count -gt 0) {
    "<table><thead><tr><th>Remove dependency: From</th><th>To</th><th>In SCC</th></tr></thead><tbody>$fasRows</tbody></table>"
  } else {
    "<p style='color:#888;font-size:.88rem;'>No feedback edges found. The cascade is acyclic and has a safe evaluation order.</p>"
  })
</div>
"@
)

$(
# ---------------------------------------------------------------------------
# Dominator Tree section
# ---------------------------------------------------------------------------
$domCount = $dominatorTree.idom.Count
$domBadge = if ($domCount -le 1) { "<span class='badge badge-gray'>single-node graph</span>" } `
            else { "<span class='badge badge-gray'>$domCount node(s) reachable</span>" }

# Build rows: for each node (except root) show its immediate dominator
$domRows = New-Object System.Collections.Generic.List[string]
foreach ($nodeKey in ($dominatorTree.idom.Keys | Sort-Object)) {
    if ($nodeKey -eq $TemplateName) { continue }
    $idomKey = $dominatorTree.idom[$nodeKey]
    $domRows.Add("<tr><td>$(Escape-Html $nodeKey)</td><td>$(Escape-Html $idomKey)</td></tr>")
}
$domRowsHtml = $domRows -join "`n      "
@"
<div class="section">
  <h2>Dominator Tree $domBadge</h2>
  <p style="font-size:.88rem;color:#555;">
    <strong>What it is:</strong> Node D <em>dominates</em> node N when <em>every</em> path from the root template to N must
    pass through D. The table shows each reachable node&rsquo;s <em>immediate dominator</em> &mdash; the closest ancestor that
    all paths share.<br>
    <strong>Why it matters:</strong> A node&rsquo;s immediate dominator is a mandatory gateway to reach it. If the dominator
    produces an incorrect value, every node it dominates will inherit that incorrect value regardless of their own logic.
    This is particularly useful for security and data-quality audits: a single sanitisation or validation template that
    dominates many descendants is a high-leverage place to enforce rules.
  </p>
  $(if ($domRows.Count -gt 0) {
    "<table><thead><tr><th>Node</th><th>Immediate Dominator</th></tr></thead><tbody>$domRowsHtml</tbody></table>"
  } else {
    "<p style='color:#888;font-size:.88rem;'>Root template has no reachable descendants, or root is not in the graph.</p>"
  })
</div>
"@
)

$(
# ---------------------------------------------------------------------------
# Betweenness Centrality section
# ---------------------------------------------------------------------------
# Sort nodes by score descending; show top 15
$bcSorted = @($betweenness.Keys | Sort-Object { [double]$betweenness[$_] } -Descending)
$topBc    = $bcSorted | Select-Object -First 15
$bcBadge  = if ($bcSorted.Count -eq 0) { "<span class='badge badge-gray'>empty graph</span>" } `
            else {
                $topKey   = $bcSorted[0]
                $topScore = [Math]::Round([double]$betweenness[$topKey], 4)
                "<span class='badge badge-gray'>top: $(Escape-Html $topKey) ($topScore)</span>"
            }
$bcRows = ($topBc | ForEach-Object {
    $score = [Math]::Round([double]$betweenness[$_], 4)
    $isTop = ($_ -eq $bcSorted[0])
    $cls   = if ($isTop) { " class='bottleneck-row'" } else { "" }
    "<tr$cls><td>$(Escape-Html $_)</td><td>$score</td></tr>"
}) -join "`n      "
@"
<div class="section">
  <h2>Betweenness Centrality (Traffic Bottlenecks) $bcBadge</h2>
  <p style="font-size:.88rem;color:#555;">
    <strong>What it is:</strong> Betweenness centrality measures how often a node lies on the <em>shortest path</em> between
    every pair of other nodes. A score of 1.0 means all shortest paths in the graph flow through that node; a score of 0
    means none do.<br>
    <strong>Why it matters:</strong> High-centrality templates are &ldquo;traffic hubs&rdquo;. Under concurrent evaluation
    (many save operations triggering cascades simultaneously) these nodes are the most likely to become latency hot-spots
    because the most recalculation work converges on them. They are also the highest-impact targets for caching or
    pre-computation optimisations.
  </p>
  $(if ($bcRows.Count -gt 0 -or $bcSorted.Count -gt 0) {
    "<table><thead><tr><th>Node (top 15 by score)</th><th>Normalized Score</th></tr></thead><tbody>$bcRows</tbody></table>"
  } else {
    "<p style='color:#888;font-size:.88rem;'>Graph has no nodes.</p>"
  })
</div>
"@
)

</body>
</html>
"@

# ---------------------------------------------------------------------------
# Write output
# ---------------------------------------------------------------------------
$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$resolvedOutputDir = if (-not [string]::IsNullOrWhiteSpace($OutputDir)) {
    [System.IO.Path]::GetFullPath($OutputDir)
} else {
    Join-Path (Get-Location).Path "output\oneim-cascade\$timestamp"
}

if (-not (Test-Path -LiteralPath $resolvedOutputDir)) {
    $null = New-Item -ItemType Directory -Path $resolvedOutputDir -Force
}

$safeName    = $TemplateName -replace '[\\/:*?"<>|]', '_'
$htmlOutPath = Join-Path $resolvedOutputDir ("cascade-{0}.html" -f $safeName)

Set-Content -LiteralPath $htmlOutPath -Value $html -Encoding UTF8

# Companion JSON for tooling consumption
# Betweenness: convert hashtable to ordered array for clean JSON
$bcArray = @($betweenness.Keys | Sort-Object { [double]$betweenness[$_] } -Descending | ForEach-Object {
    [ordered]@{ node = $_; score = [Math]::Round([double]$betweenness[$_], 4) }
})

# Dominator idom: convert hashtable to ordered array for clean JSON
$idomArray = @($dominatorTree.idom.Keys | Sort-Object | ForEach-Object {
    [ordered]@{ node = $_; immediate_dominator = $dominatorTree.idom[$_] }
})

$jsonReport = [ordered]@{
    root_template      = $TemplateName
    generated_at       = $generatedAt
    node_count         = $nodeCount
    edge_count         = $edgeCount
    cycle_count        = $cycleCount
    bottleneck         = if ($bottleneckKey) { [ordered]@{ key = $bottleneckKey; avg_ms = $bottleneckMs } } else { $null }
    nodes              = @($nodes.Values | Sort-Object key)
    cycles             = $cycleEdges.ToArray()
    depth_histogram              = $depthHist
    topological_order            = $topoOrder
    cycle_node_keys              = $cyclicKeys
    strongly_connected_components = $sccs
    critical_path = [ordered]@{
        path               = $criticalPath.critical_path
        total_ms           = $criticalPath.total_ms
        has_benchmark_data = $criticalPath.has_benchmark_data
    }
    articulation_points = $artPoints
    feedback_arc_set    = [ordered]@{
        edges = $fasResult.edges
        count = $fasResult.count
    }
    dominator_tree = [ordered]@{
        root = $dominatorTree.root
        idom = $idomArray
    }
    betweenness_centrality = $bcArray
}

$jsonOutPath = Join-Path $resolvedOutputDir ("cascade-{0}.json" -f $safeName)
$jsonReport | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $jsonOutPath -Encoding UTF8

Write-Host ""
Write-Host ("Cascade report written to: {0}" -f $resolvedOutputDir)
Write-Host ("  HTML : {0}" -f $htmlOutPath)
Write-Host ("  JSON : {0}" -f $jsonOutPath)
Write-Host ("  Nodes   : {0}" -f $nodeCount)
Write-Host ("  Edges   : {0}" -f $edgeCount)
Write-Host ("  Cycles  : {0}" -f $cycleCount)
if ($bottleneckKey) {
    Write-Host ("  Bottleneck: {0} ({1} ms avg)" -f $bottleneckKey, $bottleneckMs) -ForegroundColor Red
}
exit 0
