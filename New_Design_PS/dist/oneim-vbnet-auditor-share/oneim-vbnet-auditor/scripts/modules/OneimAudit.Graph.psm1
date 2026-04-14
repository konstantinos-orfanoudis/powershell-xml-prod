Set-StrictMode -Version Latest

# ---------------------------------------------------------------------------
# New-OneImAuditGraph
# ---------------------------------------------------------------------------
function New-OneImAuditGraph {
    <#
    .SYNOPSIS
    Creates a new, empty graph object used by all graph operations in this module.

    .PARAMETER BenchData
    Optional hashtable of benchmark results keyed "template::Table.Column".
    Used by Add-OneImAuditGraphNode to populate avg_ms / p95_ms on each node.

    .PARAMETER TemplateCatalog
    Optional hashtable keyed "Table.Column" -> template expression string.
    Used by Add-OneImAuditGraphNode to set has_template and by BFS for edge parsing.
    #>
    param(
        [Parameter()]
        [hashtable]$BenchData = @{},

        [Parameter()]
        [hashtable]$TemplateCatalog = @{}
    )

    return @{
        Nodes           = [ordered]@{}
        AdjList         = [ordered]@{}
        ReverseAdj      = [ordered]@{}
        CycleEdges      = New-Object System.Collections.Generic.List[object]
        DepthMap        = @{}
        BenchData       = $BenchData
        TemplateCatalog = $TemplateCatalog
    }
}

# ---------------------------------------------------------------------------
# Add-OneImAuditGraphNode
# ---------------------------------------------------------------------------
function Add-OneImAuditGraphNode {
    <#
    .SYNOPSIS
    Adds a node to the graph if it does not already exist. Returns the node object.
    Idempotent: calling again for the same key returns the existing node unchanged.

    .PARAMETER Graph
    Graph object created by New-OneImAuditGraph.

    .PARAMETER Key
    Node key in "Table.Column" format.

    .PARAMETER NodeType
    Optional type label (default: "template").

    .PARAMETER IsWriter
    When set, marks this node as a writer (contains PutValue, ExecuteTemplate, or similar
    write operations). Writer nodes in multi-node SCCs get concurrency_risk = "write-cycle"
    instead of "read-cycle" in Find-OneImAuditSCCs.
    #>
    param(
        [Parameter(Mandatory)]
        [hashtable]$Graph,

        [Parameter(Mandatory)]
        [string]$Key,

        [Parameter()]
        [string]$NodeType = "template",

        [Parameter()]
        [switch]$IsWriter
    )

    if (-not $Graph.Nodes.Contains($Key)) {
        $parts  = $Key -split '\.'
        $tbl    = if ($parts.Count -ge 1) { $parts[0] } else { "" }
        $col    = if ($parts.Count -ge 2) { $parts[1..($parts.Count - 1)] -join "." } else { "" }

        $bKey   = "template::$Key"
        $bench  = if ($Graph.BenchData.ContainsKey($bKey)) { $Graph.BenchData[$bKey] } else { $null }
        $hasTemplate = $Graph.TemplateCatalog.ContainsKey($Key)

        $Graph.Nodes[$Key] = [pscustomobject]@{
            key               = $Key
            node_type         = $NodeType
            table_name        = $tbl
            column_name       = $col
            has_template      = $hasTemplate
            is_writer         = $IsWriter.IsPresent
            avg_ms            = if ($bench -and $null -ne $bench.PSObject.Properties["avg_ms"]) { [double]$bench.avg_ms } else { $null }
            p95_ms            = if ($bench -and $null -ne $bench.PSObject.Properties["p95_ms"]) { [double]$bench.p95_ms } else { $null }
            threshold_exceeded = if ($bench -and $null -ne $bench.PSObject.Properties["threshold_exceeded"]) { [bool]$bench.threshold_exceeded } else { $false }
            in_cycle          = $false
            cycle_paths       = @()
            scc_id            = 0
            scc_size          = 1
        }

        $Graph.AdjList[$Key] = New-Object System.Collections.Generic.List[string]
    }

    return $Graph.Nodes[$Key]
}

# ---------------------------------------------------------------------------
# Add-OneImAuditGraphEdge
# ---------------------------------------------------------------------------
function Add-OneImAuditGraphEdge {
    <#
    .SYNOPSIS
    Adds a directed edge From -> To in the graph. Idempotent (no duplicate edges).

    .PARAMETER Graph
    Graph object created by New-OneImAuditGraph.

    .PARAMETER From
    Source node key.

    .PARAMETER To
    Target node key.
    #>
    param(
        [Parameter(Mandatory)]
        [hashtable]$Graph,

        [Parameter(Mandatory)]
        [string]$From,

        [Parameter(Mandatory)]
        [string]$To
    )

    if (-not $Graph.AdjList.Contains($From)) {
        $Graph.AdjList[$From] = New-Object System.Collections.Generic.List[string]
    }

    if (-not $Graph.AdjList[$From].Contains($To)) {
        $Graph.AdjList[$From].Add($To)
    }
}

# ---------------------------------------------------------------------------
# Get-OneImAuditTemplateEdges
# ---------------------------------------------------------------------------
function Get-OneImAuditTemplateEdges {
    <#
    .SYNOPSIS
    Parses a OneIM template expression and returns a list of dependency edge objects.

    Three edge types are recognised:
      trigger-field  — GetTriggerValue("FieldName")
      substitution   — $FieldName$
      fk-explicit    — FK(Table.Column)

    .PARAMETER TableName
    The table that owns this template column (used for same-table edge targets).

    .PARAMETER TemplateText
    The raw template expression string.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$TableName,

        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$TemplateText
    )

    $edges = New-Object System.Collections.Generic.List[object]
    if ([string]::IsNullOrWhiteSpace($TemplateText)) {
        Write-Output -NoEnumerate $edges.ToArray()
        return
    }

    # GetTriggerValue("FieldName")
    $gtMatches = [regex]::Matches($TemplateText, 'GetTriggerValue\s*\(\s*"([^"]+)"\s*\)')
    foreach ($m in $gtMatches) {
        $fieldName = $m.Groups[1].Value
        $edges.Add([pscustomobject]@{
            kind         = "trigger-field"
            target       = ("{0}.{1}" -f $TableName, $fieldName)
            target_table = $TableName
            target_col   = $fieldName
        })
    }

    # $FieldName$
    $subMatches = [regex]::Matches($TemplateText, '\$([A-Za-z_][A-Za-z0-9_]*)\$')
    foreach ($m in $subMatches) {
        $fieldName = $m.Groups[1].Value
        $edges.Add([pscustomobject]@{
            kind         = "substitution"
            target       = ("{0}.{1}" -f $TableName, $fieldName)
            target_table = $TableName
            target_col   = $fieldName
        })
    }

    # FK(Table.Column)
    $fkMatches = [regex]::Matches($TemplateText, 'FK\s*\(\s*([A-Za-z_][A-Za-z0-9_]*)\.([A-Za-z_][A-Za-z0-9_]*)\s*\)')
    foreach ($m in $fkMatches) {
        $fkTable = $m.Groups[1].Value
        $fkCol   = $m.Groups[2].Value
        $edges.Add([pscustomobject]@{
            kind         = "fk-explicit"
            target       = ("{0}.{1}" -f $fkTable, $fkCol)
            target_table = $fkTable
            target_col   = $fkCol
        })
    }

    Write-Output -NoEnumerate $edges.ToArray()
}

# ---------------------------------------------------------------------------
# Invoke-OneImAuditGraphBFS
# ---------------------------------------------------------------------------
function Invoke-OneImAuditGraphBFS {
    <#
    .SYNOPSIS
    Expands the graph from a root node using BFS.

    Adds nodes and edges for:
      - Template expression references (GetTriggerValue, $Sub$, FK(...))
      - Schema FK successors from the parent_to_children index

    Populates Graph.DepthMap with the BFS depth of each reachable node.

    .PARAMETER Graph
    Graph object created by New-OneImAuditGraph (must carry TemplateCatalog).

    .PARAMETER RootKey
    Starting node in "Table.Column" format.

    .PARAMETER ParentToChildren
    Hashtable from Build-SchemaIndexes: "Table.Col" -> array of { child_table, child_column }.
    #>
    param(
        [Parameter(Mandatory)]
        [hashtable]$Graph,

        [Parameter(Mandatory)]
        [string]$RootKey,

        [Parameter(Mandatory)]
        [AllowEmptyCollection()]
        [hashtable]$ParentToChildren
    )

    $null = Add-OneImAuditGraphNode -Graph $Graph -Key $RootKey
    $Graph.DepthMap[$RootKey] = 0

    $queue   = New-Object System.Collections.Generic.Queue[object]
    $visited = @{}

    $queue.Enqueue([pscustomobject]@{ Key = $RootKey; Depth = 0 })
    $visited[$RootKey] = $true

    while ($queue.Count -gt 0) {
        $entry        = $queue.Dequeue()
        $currentKey   = [string]$entry.Key
        $currentDepth = [int]$entry.Depth

        $parts        = $currentKey -split '\.'
        $currentTable = if ($parts.Count -ge 1) { $parts[0] } else { "" }

        # Edges from template expression text
        if ($Graph.TemplateCatalog.ContainsKey($currentKey)) {
            $edges = Get-OneImAuditTemplateEdges `
                -TableName    $currentTable `
                -TemplateText $Graph.TemplateCatalog[$currentKey]

            foreach ($edge in $edges) {
                $targetKey = $edge.target
                $null = Add-OneImAuditGraphNode -Graph $Graph -Key $targetKey
                Add-OneImAuditGraphEdge -Graph $Graph -From $currentKey -To $targetKey

                if (-not $visited.ContainsKey($targetKey)) {
                    $visited[$targetKey] = $true
                    $Graph.DepthMap[$targetKey] = $currentDepth + 1
                    $queue.Enqueue([pscustomobject]@{ Key = $targetKey; Depth = $currentDepth + 1 })
                }
            }
        }

        # Edges from schema FK successors (parent_to_children)
        if ($ParentToChildren.ContainsKey($currentKey)) {
            foreach ($child in $ParentToChildren[$currentKey]) {
                $childKey = ("{0}.{1}" -f [string]$child.child_table, [string]$child.child_column)
                $null = Add-OneImAuditGraphNode -Graph $Graph -Key $childKey
                Add-OneImAuditGraphEdge -Graph $Graph -From $currentKey -To $childKey

                if (-not $visited.ContainsKey($childKey)) {
                    $visited[$childKey] = $true
                    $Graph.DepthMap[$childKey] = $currentDepth + 1
                    $queue.Enqueue([pscustomobject]@{ Key = $childKey; Depth = $currentDepth + 1 })
                }
            }
        }
    }
}

# ---------------------------------------------------------------------------
# Build-OneImAuditGraphReverseAdj
# ---------------------------------------------------------------------------
function Build-OneImAuditGraphReverseAdj {
    <#
    .SYNOPSIS
    Builds the reverse adjacency list from the forward AdjList.
    Populates Graph.ReverseAdj. Safe to call after BFS completes.

    .PARAMETER Graph
    Graph object created by New-OneImAuditGraph (AdjList must be populated).
    #>
    param(
        [Parameter(Mandatory)]
        [hashtable]$Graph
    )

    $rev = [ordered]@{}

    foreach ($fromKey in $Graph.AdjList.Keys) {
        foreach ($toKey in @($Graph.AdjList[$fromKey])) {
            if (-not $rev.Contains($toKey)) {
                $rev[$toKey] = New-Object System.Collections.Generic.List[string]
            }
            if (-not $rev[$toKey].Contains($fromKey)) {
                $rev[$toKey].Add($fromKey)
            }
        }
    }

    $Graph.ReverseAdj = $rev
}

# ---------------------------------------------------------------------------
# Find-OneImAuditGraphCycles
# ---------------------------------------------------------------------------
function Find-OneImAuditGraphCycles {
    <#
    .SYNOPSIS
    Detects all back edges (cycles) in the graph using iterative DFS with gray coloring.

    Populates Graph.CycleEdges and sets in_cycle / cycle_paths on affected nodes.
    Safe to call on graphs with hundreds of nodes (no PowerShell call-stack recursion).

    Calling this function a second time clears and recomputes cycle data.

    .PARAMETER Graph
    Graph object created by New-OneImAuditGraph (nodes and AdjList must be populated).
    #>
    param(
        [Parameter(Mandatory)]
        [hashtable]$Graph
    )

    # Reset any prior cycle data so the function is idempotent
    $Graph.CycleEdges.Clear()
    foreach ($n in @($Graph.Nodes.Values)) {
        $n.in_cycle    = $false
        $n.cycle_paths = @()
    }

    $nodes   = $Graph.Nodes
    $adjList = $Graph.AdjList
    $color   = @{}   # 0 = white, 1 = gray, 2 = black

    foreach ($startKey in @($nodes.Keys)) {
        if ($color.ContainsKey($startKey) -and $color[$startKey] -ne 0) { continue }

        # Iterative DFS using an explicit stack of frames.
        # Each frame: hashtable with Key (string) and Idx (int — next neighbor index to process).
        $stack = New-Object System.Collections.Generic.Stack[hashtable]
        $path  = New-Object System.Collections.Generic.List[string]

        $color[$startKey] = 1
        $path.Add($startKey)
        $stack.Push(@{ Key = $startKey; Idx = 0 })

        while ($stack.Count -gt 0) {
            $frame     = $stack.Peek()
            $key       = [string]$frame.Key
            $neighbors = @()
            if ($adjList.Contains($key)) { $neighbors = $adjList[$key].ToArray() }

            if ($frame.Idx -lt $neighbors.Count) {
                $neighbor = [string]$neighbors[$frame.Idx]
                $frame.Idx++

                $neighborColor = if ($color.ContainsKey($neighbor)) { $color[$neighbor] } else { 0 }

                if ($neighborColor -eq 0) {
                    # Unvisited — recurse
                    $color[$neighbor] = 1
                    $path.Add($neighbor)
                    $stack.Push(@{ Key = $neighbor; Idx = 0 })
                }
                elseif ($neighborColor -eq 1) {
                    # Back edge — cycle detected
                    $cycleStart = $path.IndexOf($neighbor)
                    $cyclePath  = @($path[$cycleStart..($path.Count - 1)]) + @($neighbor)

                    $Graph.CycleEdges.Add([pscustomobject]@{
                        from = $key
                        to   = $neighbor
                        path = $cyclePath
                    })

                    foreach ($cn in $cyclePath) {
                        if ($nodes.Contains($cn)) {
                            $nodes[$cn].in_cycle = $true
                            $existing = @($nodes[$cn].cycle_paths)
                            $nodes[$cn].cycle_paths = $existing + @(, $cyclePath)
                        }
                    }
                }
                # neighborColor == 2: already fully processed — skip
            }
            else {
                # All neighbors processed — pop frame
                $null  = $stack.Pop()
                $color[$key] = 2
                if ($path.Count -gt 0) {
                    $path.RemoveAt($path.Count - 1)
                }
            }
        }
    }
}

# ---------------------------------------------------------------------------
# Get-OneImAuditGraphStats
# ---------------------------------------------------------------------------
function Get-OneImAuditGraphStats {
    <#
    .SYNOPSIS
    Returns summary statistics for the graph.

    Returns a PSCustomObject with:
      node_count, edge_count, cycle_count, max_depth, avg_out_degree

    Call after Invoke-OneImAuditGraphBFS and Find-OneImAuditGraphCycles
    to get complete stats.

    .PARAMETER Graph
    Graph object created by New-OneImAuditGraph.
    #>
    param(
        [Parameter(Mandatory)]
        [hashtable]$Graph
    )

    $nodeCount = $Graph.Nodes.Count

    $edgeCount = 0
    foreach ($neighbors in $Graph.AdjList.Values) {
        $edgeCount += $neighbors.Count
    }

    $cycleCount = $Graph.CycleEdges.Count

    $maxDepth = 0
    if ($Graph.DepthMap.Count -gt 0) {
        $maxDepth = ($Graph.DepthMap.Values | Measure-Object -Maximum).Maximum
    }

    $avgOutDegree = if ($nodeCount -gt 0) {
        [Math]::Round($edgeCount / $nodeCount, 3)
    } else {
        0
    }

    return [pscustomobject]@{
        node_count      = $nodeCount
        edge_count      = $edgeCount
        cycle_count     = $cycleCount
        max_depth       = $maxDepth
        avg_out_degree  = $avgOutDegree
    }
}

# ---------------------------------------------------------------------------
# Find-OneImAuditSCCs
# ---------------------------------------------------------------------------
function Find-OneImAuditSCCs {
    <#
    .SYNOPSIS
    Finds all Strongly Connected Components using iterative Kosaraju's algorithm.

    Populates scc_id and scc_size on every node in Graph.Nodes.
    Safe to call on graphs with hundreds of nodes (no PowerShell call-stack recursion).
    Requires Build-OneImAuditGraphReverseAdj to have been called first.
    Calling this function a second time clears and recomputes all SCC data.

    .PARAMETER Graph
    Graph object created by New-OneImAuditGraph (AdjList and ReverseAdj must be populated).

    .OUTPUTS
    Array of PSCustomObject with:
      scc_id           - 1-based integer identifier
      members          - string[] of node keys in this component
      size             - member count
      concurrency_risk - "none" (size 1), "read-cycle" (size > 1, no writers), or
                         "write-cycle" (size > 1, at least one member node has is_writer = $true)
    #>
    param(
        [Parameter(Mandatory)]
        [hashtable]$Graph
    )

    # Reset prior SCC data so the function is idempotent
    foreach ($n in @($Graph.Nodes.Values)) {
        $n.scc_id   = 0
        $n.scc_size = 1
    }

    # -----------------------------------------------------------------------
    # Pass 1 — iterative DFS on forward graph; push nodes onto finish stack
    #          in completion order.
    # -----------------------------------------------------------------------
    $finishStack = New-Object System.Collections.Generic.Stack[string]
    $visited1    = @{}

    foreach ($startKey in @($Graph.Nodes.Keys)) {
        if ($visited1.ContainsKey($startKey)) { continue }

        $dfsStack = New-Object System.Collections.Generic.Stack[hashtable]
        $visited1[$startKey] = $true
        $dfsStack.Push(@{ Key = $startKey; Idx = 0 })

        while ($dfsStack.Count -gt 0) {
            $frame     = $dfsStack.Peek()
            $key       = [string]$frame.Key
            $neighbors = @()
            if ($Graph.AdjList.Contains($key)) { $neighbors = $Graph.AdjList[$key].ToArray() }

            if ($frame.Idx -lt $neighbors.Count) {
                $neighbor = [string]$neighbors[$frame.Idx]
                $frame.Idx++
                if (-not $visited1.ContainsKey($neighbor)) {
                    $visited1[$neighbor] = $true
                    $dfsStack.Push(@{ Key = $neighbor; Idx = 0 })
                }
            } else {
                $null = $dfsStack.Pop()
                $finishStack.Push($key)
            }
        }
    }

    # -----------------------------------------------------------------------
    # Pass 2 — process nodes in reverse finish order; DFS on reverse graph.
    #          Each DFS tree is one SCC.
    # -----------------------------------------------------------------------
    $visited2 = @{}
    $sccList  = New-Object System.Collections.Generic.List[object]
    $sccId    = 0

    while ($finishStack.Count -gt 0) {
        $startKey = $finishStack.Pop()
        if ($visited2.ContainsKey($startKey)) { continue }

        $members  = New-Object System.Collections.Generic.List[string]
        $dfsStack = New-Object System.Collections.Generic.Stack[string]
        $visited2[$startKey] = $true
        $dfsStack.Push($startKey)

        while ($dfsStack.Count -gt 0) {
            $key = $dfsStack.Pop()
            $members.Add($key)

            if ($Graph.ReverseAdj.Contains($key)) {
                foreach ($pred in @($Graph.ReverseAdj[$key])) {
                    if (-not $visited2.ContainsKey($pred)) {
                        $visited2[$pred] = $true
                        $dfsStack.Push($pred)
                    }
                }
            }
        }

        $sccId++
        $memberArray = $members.ToArray()
        $sccSize     = $memberArray.Count

        $hasWriter = $false
        if ($sccSize -gt 1) {
            foreach ($mKey in $memberArray) {
                if ($Graph.Nodes.Contains($mKey) -and $Graph.Nodes[$mKey].is_writer) {
                    $hasWriter = $true
                    break
                }
            }
        }
        $risk = if ($sccSize -gt 1) { if ($hasWriter) { "write-cycle" } else { "read-cycle" } } else { "none" }

        $sccList.Add([pscustomobject]@{
            scc_id           = $sccId
            members          = $memberArray
            size             = $sccSize
            concurrency_risk = $risk
        })

        foreach ($mKey in $memberArray) {
            if ($Graph.Nodes.Contains($mKey)) {
                $Graph.Nodes[$mKey].scc_id   = $sccId
                $Graph.Nodes[$mKey].scc_size = $sccSize
            }
        }
    }

    Write-Output -NoEnumerate $sccList.ToArray()
}

# ---------------------------------------------------------------------------
# Get-OneImAuditDepthHistogram
# ---------------------------------------------------------------------------
function Get-OneImAuditDepthHistogram {
    <#
    .SYNOPSIS
    Returns a depth-frequency histogram from the BFS depth map.

    Each entry in the returned array represents one BFS depth level and the
    number of nodes found at that depth.  The array is sorted by depth ascending.

    Call after Invoke-OneImAuditGraphBFS so that Graph.DepthMap is populated.

    .PARAMETER Graph
    Graph object created by New-OneImAuditGraph.
    #>
    param(
        [Parameter(Mandatory)]
        [hashtable]$Graph
    )

    $buckets = @{}
    foreach ($depth in $Graph.DepthMap.Values) {
        $d = [int]$depth
        if (-not $buckets.ContainsKey($d)) { $buckets[$d] = 0 }
        $buckets[$d]++
    }

    $histogram = New-Object System.Collections.Generic.List[object]
    foreach ($d in ($buckets.Keys | Sort-Object)) {
        $histogram.Add([pscustomobject]@{ depth = $d; count = $buckets[$d] })
    }

    Write-Output -NoEnumerate $histogram.ToArray()
}

# ---------------------------------------------------------------------------
# Invoke-OneImAuditTopologicalSort
# ---------------------------------------------------------------------------
function Invoke-OneImAuditTopologicalSort {
    <#
    .SYNOPSIS
    Returns a topological ordering of all non-cycle nodes using Kahn's algorithm.

    Nodes that participate in cycles cannot be linearised and are returned
    separately in cycle_node_keys.

    Must be called after Find-OneImAuditGraphCycles (or at least after
    Invoke-OneImAuditGraphBFS) so that Graph.Nodes and Graph.AdjList are populated.

    .PARAMETER Graph
    Graph object created by New-OneImAuditGraph.

    .OUTPUTS
    PSCustomObject with:
      order           - string[] of node keys in a valid evaluation order
      cycle_node_keys - string[] of keys excluded from the ordering because
                        they are members of one or more cycles
    #>
    param(
        [Parameter(Mandatory)]
        [hashtable]$Graph
    )

    # Compute in-degree for every known node
    $inDegree = @{}
    foreach ($key in @($Graph.Nodes.Keys)) {
        if (-not $inDegree.ContainsKey($key)) { $inDegree[$key] = 0 }
    }
    foreach ($fromKey in @($Graph.AdjList.Keys)) {
        foreach ($toKey in @($Graph.AdjList[$fromKey])) {
            if (-not $inDegree.ContainsKey($toKey)) { $inDegree[$toKey] = 0 }
            $inDegree[$toKey]++
        }
    }

    # Seed queue with zero-in-degree nodes (sorted for deterministic output)
    $queue = New-Object System.Collections.Generic.Queue[string]
    foreach ($key in ($inDegree.Keys | Sort-Object)) {
        if ($inDegree[$key] -eq 0) { $queue.Enqueue($key) }
    }

    $order   = New-Object System.Collections.Generic.List[string]
    $emitted = @{}

    while ($queue.Count -gt 0) {
        $key = $queue.Dequeue()
        $order.Add($key)
        $emitted[$key] = $true

        if ($Graph.AdjList.Contains($key)) {
            foreach ($neighbor in @($Graph.AdjList[$key])) {
                $inDegree[$neighbor]--
                if ($inDegree[$neighbor] -eq 0) {
                    $queue.Enqueue($neighbor)
                }
            }
        }
    }

    # Nodes not emitted are members of cycles
    $cycleNodeKeys = New-Object System.Collections.Generic.List[string]
    foreach ($key in @($Graph.Nodes.Keys)) {
        if (-not $emitted.ContainsKey($key)) {
            $cycleNodeKeys.Add($key)
        }
    }

    return [pscustomobject]@{
        order           = $order.ToArray()
        cycle_node_keys = $cycleNodeKeys.ToArray()
    }
}

# ---------------------------------------------------------------------------
# Get-OneImAuditCriticalPath
# ---------------------------------------------------------------------------
function Get-OneImAuditCriticalPath {
    <#
    .SYNOPSIS
    Computes the critical (longest-latency) path through the graph using dynamic
    programming on topologically sorted nodes.

    For each node in reverse topological order (leaves first):
      dp[node] = avg_ms[node] + max(dp[successor] for each successor in AdjList[node])

    Missing or null avg_ms values are treated as 0.0.

    .PARAMETER Graph
    Graph object created by New-OneImAuditGraph (AdjList and Nodes must be populated).

    .OUTPUTS
    PSCustomObject with:
      critical_path      - string[] of node keys from root to leaf of the heaviest chain
      total_ms           - double total latency along that path
      node_dp            - hashtable key -> double longest-path cost starting at that node
      has_benchmark_data - bool whether any node has non-null avg_ms
    #>
    param(
        [Parameter(Mandatory)]
        [hashtable]$Graph
    )

    $emptyResult = [pscustomobject]@{
        critical_path      = @()
        total_ms           = [double]0
        node_dp            = @{}
        has_benchmark_data = $false
    }

    if ($Graph.Nodes.Count -eq 0) {
        return $emptyResult
    }

    $topoResult = Invoke-OneImAuditTopologicalSort -Graph $Graph
    $topoOrder  = $topoResult.order

    if ($topoOrder.Count -eq 0) {
        return $emptyResult
    }

    $hasBench = $false
    foreach ($key in @($Graph.Nodes.Keys)) {
        if ($null -ne $Graph.Nodes[$key].avg_ms -and [double]$Graph.Nodes[$key].avg_ms -gt 0.0) {
            $hasBench = $true
            break
        }
    }

    $dp   = @{}
    $next = @{}

    foreach ($key in $topoOrder) {
        $dp[$key]   = [double]0
        $next[$key] = $null
    }

    # Process in REVERSE topological order (leaves first)
    for ($ri = $topoOrder.Count - 1; $ri -ge 0; $ri--) {
        $key = $topoOrder[$ri]

        $nodeMs = [double]0
        if ($Graph.Nodes.Contains($key) -and $null -ne $Graph.Nodes[$key].avg_ms) {
            $nodeMs = [double]$Graph.Nodes[$key].avg_ms
        }

        $bestSuccMs  = [double]0
        $bestSuccKey = $null

        if ($Graph.AdjList.Contains($key)) {
            foreach ($succ in @($Graph.AdjList[$key])) {
                if ($dp.ContainsKey($succ)) {
                    $succCost = [double]$dp[$succ]
                    if ($null -eq $bestSuccKey -or $succCost -gt $bestSuccMs) {
                        $bestSuccMs  = $succCost
                        $bestSuccKey = $succ
                    }
                }
            }
        }

        $dp[$key]   = $nodeMs + $bestSuccMs
        $next[$key] = $bestSuccKey
    }

    # Find the node with the highest dp value (start of critical path)
    $bestRootKey = $null
    $bestRootMs  = [double]-1

    foreach ($key in $topoOrder) {
        if ($dp.ContainsKey($key)) {
            $val = [double]$dp[$key]
            if ($null -eq $bestRootKey -or $val -gt $bestRootMs) {
                $bestRootMs  = $val
                $bestRootKey = $key
            }
        }
    }

    $criticalPath = New-Object System.Collections.Generic.List[string]
    if ($null -ne $bestRootKey) {
        $cur     = $bestRootKey
        $seenCp  = @{}
        while ($null -ne $cur -and -not $seenCp.ContainsKey($cur)) {
            [void]$criticalPath.Add($cur)
            $seenCp[$cur] = $true
            $cur = $next[$cur]
        }
    }

    $totalMs = [double]0
    if ($null -ne $bestRootKey -and $dp.ContainsKey($bestRootKey)) {
        $totalMs = [double]$dp[$bestRootKey]
    }

    return [pscustomobject]@{
        critical_path      = $criticalPath.ToArray()
        total_ms           = $totalMs
        node_dp            = $dp
        has_benchmark_data = $hasBench
    }
}

# ---------------------------------------------------------------------------
# Find-OneImAuditArticulationPoints
# ---------------------------------------------------------------------------
function Find-OneImAuditArticulationPoints {
    <#
    .SYNOPSIS
    Finds all articulation points in the undirected version of the graph using
    Tarjan's iterative DFS algorithm.

    Every directed edge is treated as bidirectional. An articulation point is a
    node whose removal disconnects the undirected graph -- i.e. a single point of
    failure whose breakage or slowness isolates downstream templates.

    .PARAMETER Graph
    Graph object created by New-OneImAuditGraph (AdjList must be populated).

    .OUTPUTS
    String[] of node keys that are articulation points. Empty array if none.
    #>
    param(
        [Parameter(Mandatory)]
        [hashtable]$Graph
    )

    $nodeKeys = @($Graph.Nodes.Keys)
    if ($nodeKeys.Count -eq 0) {
        $empty = @()
        Write-Output -NoEnumerate $empty
        return
    }

    # Build undirected adjacency (both directions per edge)
    $undirAdj = @{}
    foreach ($key in $nodeKeys) {
        $undirAdj[$key] = New-Object System.Collections.Generic.List[string]
    }
    foreach ($fromKey in @($Graph.AdjList.Keys)) {
        foreach ($toKey in @($Graph.AdjList[$fromKey])) {
            if (-not $undirAdj.ContainsKey($fromKey)) {
                $undirAdj[$fromKey] = New-Object System.Collections.Generic.List[string]
            }
            if (-not $undirAdj.ContainsKey($toKey)) {
                $undirAdj[$toKey] = New-Object System.Collections.Generic.List[string]
            }
            if (-not $undirAdj[$fromKey].Contains($toKey)) { [void]$undirAdj[$fromKey].Add($toKey) }
            if (-not $undirAdj[$toKey].Contains($fromKey)) { [void]$undirAdj[$toKey].Add($fromKey) }
        }
    }

    $disc  = @{}
    $low   = @{}
    $apSet = @{}
    $timer = 0

    foreach ($startKey in $nodeKeys) {
        if ($disc.ContainsKey($startKey)) { continue }

        $disc[$startKey] = $timer
        $low[$startKey]  = $timer
        $timer++

        $stack = New-Object System.Collections.Generic.Stack[object]
        $stack.Push([pscustomobject]@{
            node           = $startKey
            parentNode     = $null
            childIdx       = 0
            rootChildCount = 0
        })

        while ($stack.Count -gt 0) {
            $frame     = $stack.Peek()
            $u         = [string]$frame.node
            $uParent   = $frame.parentNode
            $neighbors = @()
            if ($undirAdj.ContainsKey($u)) { $neighbors = $undirAdj[$u].ToArray() }

            $pushed = $false
            while ($frame.childIdx -lt $neighbors.Count) {
                $v = [string]$neighbors[$frame.childIdx]
                $frame.childIdx++

                if ($null -ne $uParent -and $v -eq $uParent) { continue }

                if (-not $disc.ContainsKey($v)) {
                    # Tree edge
                    if ($null -eq $uParent) { $frame.rootChildCount++ }

                    $disc[$v] = $timer
                    $low[$v]  = $timer
                    $timer++

                    $stack.Push([pscustomobject]@{
                        node           = $v
                        parentNode     = $u
                        childIdx       = 0
                        rootChildCount = 0
                    })
                    $pushed = $true
                    break
                } else {
                    # Back edge: update low[u]
                    if ([int]$disc[$v] -lt [int]$low[$u]) { $low[$u] = $disc[$v] }
                }
            }

            if (-not $pushed) {
                $null = $stack.Pop()

                if ($stack.Count -gt 0) {
                    $pFrame = $stack.Peek()
                    $p      = [string]$pFrame.node

                    if ([int]$low[$u] -lt [int]$low[$p]) { $low[$p] = $low[$u] }

                    # AP condition for non-root p
                    if ($null -ne $pFrame.parentNode -and [int]$low[$u] -ge [int]$disc[$p]) {
                        $apSet[$p] = $true
                    }
                } else {
                    # Root: AP if it has 2+ tree children
                    if ($frame.rootChildCount -ge 2) { $apSet[$u] = $true }
                }
            }
        }
    }

    $result = [string[]]@($apSet.Keys | Sort-Object)
    Write-Output -NoEnumerate $result
}

# ---------------------------------------------------------------------------
# Get-OneImAuditFeedbackArcSet
# ---------------------------------------------------------------------------
function Get-OneImAuditFeedbackArcSet {
    <#
    .SYNOPSIS
    Computes a greedy Feedback Arc Set (FAS) for each non-trivial SCC (size > 1).

    Requires Find-OneImAuditSCCs to have been called so that scc_id and scc_size
    are set on all graph nodes.

    Algorithm per SCC:
      1. Compute within-SCC in-degree and out-degree per member.
      2. Sort members by (out_deg - in_deg) DESCENDING (greedy linear ordering).
      3. Edges from a higher-position node to a lower-position node are "backward"
         in this ordering and form the FAS for this SCC.

    Removing the returned edges makes each affected SCC acyclic with a small
    (approximately minimum) number of relationship changes.

    .PARAMETER Graph
    Graph object created by New-OneImAuditGraph with scc_id / scc_size set by
    Find-OneImAuditSCCs.

    .OUTPUTS
    PSCustomObject with:
      edges - array of PSCustomObject { from, to, scc_id }
      count - int
    #>
    param(
        [Parameter(Mandatory)]
        [hashtable]$Graph
    )

    $sccGroups = @{}
    foreach ($key in @($Graph.Nodes.Keys)) {
        $node = $Graph.Nodes[$key]
        if ([int]$node.scc_size -gt 1) {
            $sid = [int]$node.scc_id
            if (-not $sccGroups.ContainsKey($sid)) {
                $sccGroups[$sid] = New-Object System.Collections.Generic.List[string]
            }
            [void]$sccGroups[$sid].Add($key)
        }
    }

    $fasEdges = New-Object System.Collections.Generic.List[object]

    foreach ($sid in @($sccGroups.Keys)) {
        $members   = $sccGroups[$sid].ToArray()
        $memberSet = @{}
        foreach ($m in $members) { $memberSet[$m] = $true }

        $inDeg  = @{}
        $outDeg = @{}
        foreach ($m in $members) { $inDeg[$m] = 0; $outDeg[$m] = 0 }

        foreach ($m in $members) {
            if ($Graph.AdjList.Contains($m)) {
                foreach ($succ in @($Graph.AdjList[$m])) {
                    if ($memberSet.ContainsKey($succ)) {
                        $outDeg[$m]++
                        $inDeg[$succ]++
                    }
                }
            }
        }

        $sorted = @($members | Sort-Object { [int]$outDeg[$_] - [int]$inDeg[$_] } -Descending)
        $posMap = @{}
        for ($i = 0; $i -lt $sorted.Count; $i++) { $posMap[$sorted[$i]] = $i }

        foreach ($u in $members) {
            if ($Graph.AdjList.Contains($u)) {
                foreach ($v in @($Graph.AdjList[$u])) {
                    if ($memberSet.ContainsKey($v) -and [int]$posMap[$u] -gt [int]$posMap[$v]) {
                        [void]$fasEdges.Add([pscustomobject]@{ from = $u; to = $v; scc_id = $sid })
                    }
                }
            }
        }
    }

    return [pscustomobject]@{ edges = $fasEdges.ToArray(); count = $fasEdges.Count }
}

# ---------------------------------------------------------------------------
# Build-OneImAuditDominatorTree
# ---------------------------------------------------------------------------
function Build-OneImAuditDominatorTree {
    <#
    .SYNOPSIS
    Builds a dominator tree rooted at RootKey using the Cooper/Harvey/Kennedy
    iterative dominator algorithm.

    Node d dominates node n if EVERY path from RootKey to n passes through d.
    The immediate dominator of n is the closest such d.

    .PARAMETER Graph
    Graph object created by New-OneImAuditGraph (AdjList must be populated).

    .PARAMETER RootKey
    The entry node key to root the dominator tree at.

    .OUTPUTS
    PSCustomObject with:
      root           - string (RootKey)
      idom           - hashtable key -> immediate dominator key (root maps to itself)
      dominated_sets - hashtable key -> List of nodes immediately dominated by key
    #>
    param(
        [Parameter(Mandatory)]
        [hashtable]$Graph,

        [Parameter(Mandatory)]
        [string]$RootKey
    )

    if (-not $Graph.Nodes.Contains($RootKey)) {
        return [pscustomobject]@{ root = $RootKey; idom = @{}; dominated_sets = @{} }
    }

    # Step 1: iterative DFS for post-order, then reverse for RPO
    $visited   = @{}
    $postOrder = New-Object System.Collections.Generic.List[string]
    $dfsStack  = New-Object System.Collections.Generic.Stack[hashtable]

    $visited[$RootKey] = $true
    $dfsStack.Push(@{ Key = $RootKey; Idx = 0 })

    while ($dfsStack.Count -gt 0) {
        $frame = $dfsStack.Peek()
        $key   = [string]$frame.Key
        $nbrs  = @()
        if ($Graph.AdjList.Contains($key)) { $nbrs = @($Graph.AdjList[$key]) }

        if ($frame.Idx -lt $nbrs.Count) {
            $succ = [string]$nbrs[$frame.Idx]
            $frame.Idx++
            if (-not $visited.ContainsKey($succ)) {
                $visited[$succ] = $true
                $dfsStack.Push(@{ Key = $succ; Idx = 0 })
            }
        } else {
            $null = $dfsStack.Pop()
            [void]$postOrder.Add($key)
        }
    }

    $rpoOrder = New-Object System.Collections.Generic.List[string]
    for ($i = $postOrder.Count - 1; $i -ge 0; $i--) { [void]$rpoOrder.Add($postOrder[$i]) }

    $rpoIndex = @{}
    for ($i = 0; $i -lt $rpoOrder.Count; $i++) { $rpoIndex[$rpoOrder[$i]] = $i }

    # Step 2: predecessor lists (only reachable nodes)
    $preds = @{}
    foreach ($key in $rpoOrder) { $preds[$key] = New-Object System.Collections.Generic.List[string] }
    foreach ($key in $rpoOrder) {
        if ($Graph.AdjList.Contains($key)) {
            foreach ($succ in @($Graph.AdjList[$key])) {
                if ($preds.ContainsKey($succ)) { [void]$preds[$succ].Add($key) }
            }
        }
    }

    # Step 3: Cooper/Harvey/Kennedy iteration
    $idom = @{}
    $idom[$RootKey] = $RootKey

    $changed = $true
    while ($changed) {
        $changed = $false
        foreach ($b in $rpoOrder) {
            if ($b -eq $RootKey) { continue }

            $newIdom = $null
            foreach ($p in @($preds[$b])) {
                if ($idom.ContainsKey($p)) { $newIdom = $p; break }
            }
            if ($null -eq $newIdom) { continue }

            foreach ($p in @($preds[$b])) {
                if ($p -eq $newIdom -or -not $idom.ContainsKey($p)) { continue }
                # Inline intersect
                $f1 = $p
                $f2 = $newIdom
                while ($f1 -ne $f2) {
                    while ([int]$rpoIndex[$f1] -gt [int]$rpoIndex[$f2]) { $f1 = $idom[$f1] }
                    while ([int]$rpoIndex[$f2] -gt [int]$rpoIndex[$f1]) { $f2 = $idom[$f2] }
                }
                $newIdom = $f1
            }

            if (-not $idom.ContainsKey($b) -or $idom[$b] -ne $newIdom) {
                $idom[$b] = $newIdom
                $changed  = $true
            }
        }
    }

    # Step 4: build dominated_sets (children in dominator tree)
    $domSets = @{}
    foreach ($key in $rpoOrder) { $domSets[$key] = New-Object System.Collections.Generic.List[string] }
    foreach ($key in $rpoOrder) {
        if ($key -eq $RootKey) { continue }
        if ($idom.ContainsKey($key) -and $domSets.ContainsKey($idom[$key])) {
            [void]$domSets[$idom[$key]].Add($key)
        }
    }

    return [pscustomobject]@{ root = $RootKey; idom = $idom; dominated_sets = $domSets }
}

# ---------------------------------------------------------------------------
# Get-OneImAuditBetweennessCentrality
# ---------------------------------------------------------------------------
function Get-OneImAuditBetweennessCentrality {
    <#
    .SYNOPSIS
    Computes normalized betweenness centrality for every node using Brandes'
    O(VE) algorithm.

    For each source node BFS finds all shortest paths; back-propagation
    accumulates pair-dependency scores. Results are normalized by (n-1)*(n-2)
    for directed graphs (uses 1.0 when n <= 2 to avoid division by zero).

    Scores are rounded to 4 decimal places.

    .PARAMETER Graph
    Graph object created by New-OneImAuditGraph (AdjList and Nodes populated).

    .OUTPUTS
    Regular hashtable of node key -> normalized betweenness score (double).
    #>
    param(
        [Parameter(Mandatory)]
        [hashtable]$Graph
    )

    $nodeKeys = @($Graph.Nodes.Keys)
    $n        = $nodeKeys.Count
    $cb       = @{}
    foreach ($key in $nodeKeys) { $cb[$key] = [double]0 }

    if ($n -le 1) { return $cb }

    $normFactor = if ($n -le 2) { [double]1 } else { [double](($n - 1) * ($n - 2)) }

    foreach ($s in $nodeKeys) {
        $sigma    = @{}
        $dist     = @{}
        $pred     = @{}
        $delta    = @{}

        foreach ($key in $nodeKeys) {
            $sigma[$key] = [double]0
            $dist[$key]  = -1
            $pred[$key]  = New-Object System.Collections.Generic.List[string]
            $delta[$key] = [double]0
        }

        $sigma[$s] = [double]1
        $dist[$s]  = 0

        $bfsQueue = New-Object System.Collections.Generic.Queue[string]
        $bfsStack = New-Object System.Collections.Generic.Stack[string]
        $bfsQueue.Enqueue($s)

        while ($bfsQueue.Count -gt 0) {
            $v = $bfsQueue.Dequeue()
            [void]$bfsStack.Push($v)

            if ($Graph.AdjList.Contains($v)) {
                foreach ($w in @($Graph.AdjList[$v])) {
                    if (-not $sigma.ContainsKey($w)) { continue }
                    if ([int]$dist[$w] -lt 0) {
                        $dist[$w] = [int]$dist[$v] + 1
                        $bfsQueue.Enqueue($w)
                    }
                    if ([int]$dist[$w] -eq ([int]$dist[$v] + 1)) {
                        $sigma[$w] += $sigma[$v]
                        [void]$pred[$w].Add($v)
                    }
                }
            }
        }

        while ($bfsStack.Count -gt 0) {
            $w = $bfsStack.Pop()
            foreach ($v in @($pred[$w])) {
                $coeff = if ($sigma[$w] -ne [double]0) { ($sigma[$v] / $sigma[$w]) * ([double]1 + $delta[$w]) } else { [double]0 }
                $delta[$v] += $coeff
            }
            if ($w -ne $s) { $cb[$w] += $delta[$w] }
        }
    }

    $result = @{}
    foreach ($key in $nodeKeys) { $result[$key] = [Math]::Round([double]$cb[$key] / $normFactor, 4) }
    return $result
}

Export-ModuleMember -Function `
    New-OneImAuditGraph, `
    Add-OneImAuditGraphNode, `
    Add-OneImAuditGraphEdge, `
    Get-OneImAuditTemplateEdges, `
    Invoke-OneImAuditGraphBFS, `
    Build-OneImAuditGraphReverseAdj, `
    Find-OneImAuditGraphCycles, `
    Get-OneImAuditGraphStats, `
    Get-OneImAuditDepthHistogram, `
    Invoke-OneImAuditTopologicalSort, `
    Find-OneImAuditSCCs, `
    Get-OneImAuditCriticalPath, `
    Find-OneImAuditArticulationPoints, `
    Get-OneImAuditFeedbackArcSet, `
    Build-OneImAuditDominatorTree, `
    Get-OneImAuditBetweennessCentrality
