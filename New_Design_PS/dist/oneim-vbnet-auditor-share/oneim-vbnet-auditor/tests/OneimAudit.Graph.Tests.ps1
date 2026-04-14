#Requires -Version 7
$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$skillRoot  = Split-Path -Parent $PSScriptRoot
$moduleRoot = Join-Path $skillRoot "scripts" "modules"

Import-Module (Join-Path $moduleRoot "OneimAudit.Graph.psm1") -Force

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
function New-FkChild {
    param([string]$Table, [string]$Column)
    [pscustomobject]@{ child_table = $Table; child_column = $Column }
}

# ---------------------------------------------------------------------------
# Get-OneImAuditTemplateEdges
# ---------------------------------------------------------------------------
Describe "OneimAudit.Graph - Get-OneImAuditTemplateEdges" {

    Context "empty / blank text" {
        It "returns empty array for empty string" {
            $edges = Get-OneImAuditTemplateEdges -TableName "T" -TemplateText ""
            $edges.Count | Should -Be 0
        }

        It "returns empty array for whitespace-only string" {
            $edges = Get-OneImAuditTemplateEdges -TableName "T" -TemplateText "   "
            $edges.Count | Should -Be 0
        }
    }

    Context "GetTriggerValue edges" {
        It "extracts a single trigger-field edge" {
            $edges = Get-OneImAuditTemplateEdges -TableName "Person" -TemplateText 'GetTriggerValue("FirstName")'
            $edges.Count | Should -Be 1
            $edges[0].kind        | Should -Be "trigger-field"
            $edges[0].target      | Should -Be "Person.FirstName"
            $edges[0].target_table | Should -Be "Person"
            $edges[0].target_col  | Should -Be "FirstName"
        }

        It "handles whitespace inside GetTriggerValue" {
            $edges = Get-OneImAuditTemplateEdges -TableName "T" -TemplateText 'GetTriggerValue ( "Field" )'
            $edges.Count | Should -Be 1
            $edges[0].target_col | Should -Be "Field"
        }

        It "extracts multiple GetTriggerValue calls" {
            $text  = 'GetTriggerValue("A") + GetTriggerValue("B")'
            $edges = Get-OneImAuditTemplateEdges -TableName "T" -TemplateText $text
            $edges.Count | Should -Be 2
            ($edges | Where-Object { $_.target_col -eq "A" }).Count | Should -Be 1
            ($edges | Where-Object { $_.target_col -eq "B" }).Count | Should -Be 1
        }
    }

    Context "substitution edges" {
        It "extracts a single substitution edge" {
            $edges = Get-OneImAuditTemplateEdges -TableName "Person" -TemplateText '$LastName$'
            $edges.Count | Should -Be 1
            $edges[0].kind       | Should -Be "substitution"
            $edges[0].target     | Should -Be "Person.LastName"
            $edges[0].target_col | Should -Be "LastName"
        }

        It "does not extract single-dollar tokens" {
            $edges = Get-OneImAuditTemplateEdges -TableName "T" -TemplateText '$notSub'
            $edges.Count | Should -Be 0
        }
    }

    Context "FK explicit edges" {
        It "extracts a single FK edge" {
            $edges = Get-OneImAuditTemplateEdges -TableName "Person" -TemplateText 'FK(Org.UID_Org)'
            $edges.Count | Should -Be 1
            $edges[0].kind         | Should -Be "fk-explicit"
            $edges[0].target       | Should -Be "Org.UID_Org"
            $edges[0].target_table | Should -Be "Org"
            $edges[0].target_col   | Should -Be "UID_Org"
        }

        It "handles whitespace inside FK()" {
            $edges = Get-OneImAuditTemplateEdges -TableName "T" -TemplateText 'FK( TableA.ColB )'
            $edges.Count | Should -Be 1
            $edges[0].target | Should -Be "TableA.ColB"
        }
    }

    Context "mixed edge types" {
        It "extracts all three types from one expression" {
            $text  = 'GetTriggerValue("F1") + $Sub1$ + FK(OtherTable.Col)'
            $edges = Get-OneImAuditTemplateEdges -TableName "Root" -TemplateText $text
            $edges.Count | Should -Be 3
            ($edges | Where-Object { $_.kind -eq "trigger-field" }).Count  | Should -Be 1
            ($edges | Where-Object { $_.kind -eq "substitution" }).Count   | Should -Be 1
            ($edges | Where-Object { $_.kind -eq "fk-explicit" }).Count    | Should -Be 1
        }
    }
}

# ---------------------------------------------------------------------------
# New-OneImAuditGraph
# ---------------------------------------------------------------------------
Describe "OneimAudit.Graph - New-OneImAuditGraph" {

    Context "structure" {
        $g = New-OneImAuditGraph

        It "has Nodes key" {
            $g.ContainsKey("Nodes") | Should -Be $true
        }

        It "has AdjList key" {
            $g.ContainsKey("AdjList") | Should -Be $true
        }

        It "has ReverseAdj key" {
            $g.ContainsKey("ReverseAdj") | Should -Be $true
        }

        It "has CycleEdges key" {
            $g.ContainsKey("CycleEdges") | Should -Be $true
        }

        It "has DepthMap key" {
            $g.ContainsKey("DepthMap") | Should -Be $true
        }

        It "starts with empty Nodes" {
            $g.Nodes.Count | Should -Be 0
        }

        It "accepts BenchData and TemplateCatalog" {
            $g2 = New-OneImAuditGraph -BenchData @{ "template::T.C" = @{} } -TemplateCatalog @{ "T.C" = "text" }
            $g2.BenchData.Count       | Should -Be 1
            $g2.TemplateCatalog.Count | Should -Be 1
        }
    }
}

# ---------------------------------------------------------------------------
# Add-OneImAuditGraphNode
# ---------------------------------------------------------------------------
Describe "OneimAudit.Graph - Add-OneImAuditGraphNode" {

    Context "adding nodes" {
        It "adds a node to Graph.Nodes" {
            $g = New-OneImAuditGraph
            Add-OneImAuditGraphNode -Graph $g -Key "Person.FirstName" | Out-Null
            $g.Nodes.Contains("Person.FirstName") | Should -Be $true
        }

        It "returns the node object" {
            $g = New-OneImAuditGraph
            $n = Add-OneImAuditGraphNode -Graph $g -Key "T.Col"
            $n | Should -Not -BeNullOrEmpty
            $n.key | Should -Be "T.Col"
        }

        It "sets table_name and column_name correctly" {
            $g = New-OneImAuditGraph
            $n = Add-OneImAuditGraphNode -Graph $g -Key "MyTable.MyCol"
            $n.table_name  | Should -Be "MyTable"
            $n.column_name | Should -Be "MyCol"
        }

        It "creates an empty AdjList entry for the new node" {
            $g = New-OneImAuditGraph
            Add-OneImAuditGraphNode -Graph $g -Key "T.C" | Out-Null
            $g.AdjList.Contains("T.C") | Should -Be $true
            $g.AdjList["T.C"].Count    | Should -Be 0
        }

        It "is idempotent - second call returns same node" {
            $g  = New-OneImAuditGraph
            $n1 = Add-OneImAuditGraphNode -Graph $g -Key "T.C"
            $n2 = Add-OneImAuditGraphNode -Graph $g -Key "T.C"
            [object]::ReferenceEquals($n1, $n2) | Should -Be $true
            $g.Nodes.Count | Should -Be 1
        }

        It "sets has_template true when key is in TemplateCatalog" {
            $g = New-OneImAuditGraph -TemplateCatalog @{ "T.C" = "some expression" }
            $n = Add-OneImAuditGraphNode -Graph $g -Key "T.C"
            $n.has_template | Should -Be $true
        }

        It "sets has_template false when key is absent from TemplateCatalog" {
            $g = New-OneImAuditGraph
            $n = Add-OneImAuditGraphNode -Graph $g -Key "T.C"
            $n.has_template | Should -Be $false
        }

        It "merges avg_ms from BenchData when available" {
            $bd = @{ "template::T.C" = [pscustomobject]@{ avg_ms = 42.5; p95_ms = 80.0; threshold_exceeded = $false } }
            $g  = New-OneImAuditGraph -BenchData $bd
            $n  = Add-OneImAuditGraphNode -Graph $g -Key "T.C"
            $n.avg_ms | Should -Be 42.5
            $n.p95_ms | Should -Be 80.0
        }

        It "leaves avg_ms null when no bench data exists" {
            $g = New-OneImAuditGraph
            $n = Add-OneImAuditGraphNode -Graph $g -Key "T.C"
            $n.avg_ms | Should -BeNullOrEmpty
        }
    }
}

# ---------------------------------------------------------------------------
# Add-OneImAuditGraphEdge
# ---------------------------------------------------------------------------
Describe "OneimAudit.Graph - Add-OneImAuditGraphEdge" {

    Context "adding edges" {
        It "adds an edge to AdjList" {
            $g = New-OneImAuditGraph
            Add-OneImAuditGraphNode -Graph $g -Key "A.X" | Out-Null
            Add-OneImAuditGraphNode -Graph $g -Key "B.Y" | Out-Null
            Add-OneImAuditGraphEdge -Graph $g -From "A.X" -To "B.Y"
            $g.AdjList["A.X"] -contains "B.Y" | Should -Be $true
        }

        It "is idempotent - duplicate edge is not added twice" {
            $g = New-OneImAuditGraph
            Add-OneImAuditGraphNode -Graph $g -Key "A.X" | Out-Null
            Add-OneImAuditGraphEdge -Graph $g -From "A.X" -To "B.Y"
            Add-OneImAuditGraphEdge -Graph $g -From "A.X" -To "B.Y"
            $g.AdjList["A.X"].Count | Should -Be 1
        }

        It "creates AdjList entry for From when node was not pre-added" {
            $g = New-OneImAuditGraph
            Add-OneImAuditGraphEdge -Graph $g -From "X.A" -To "Y.B"
            $g.AdjList.Contains("X.A") | Should -Be $true
        }
    }
}

# ---------------------------------------------------------------------------
# Invoke-OneImAuditGraphBFS
# ---------------------------------------------------------------------------
Describe "OneimAudit.Graph - Invoke-OneImAuditGraphBFS" {

    Context "root only (no catalog, no FK children)" {
        It "adds root node with depth 0" {
            $g = New-OneImAuditGraph
            Invoke-OneImAuditGraphBFS -Graph $g -RootKey "T.C" -ParentToChildren @{}
            $g.Nodes.Contains("T.C") | Should -Be $true
            $g.DepthMap["T.C"]       | Should -Be 0
        }

        It "produces exactly one node when root has no edges" {
            $g = New-OneImAuditGraph
            Invoke-OneImAuditGraphBFS -Graph $g -RootKey "T.C" -ParentToChildren @{}
            $g.Nodes.Count | Should -Be 1
        }
    }

    Context "template expression expansion" {
        It "adds nodes for template edges and sets correct depths" {
            $catalog = @{ "Root.Col" = 'FK(Child.Col)' }
            $g = New-OneImAuditGraph -TemplateCatalog $catalog
            Invoke-OneImAuditGraphBFS -Graph $g -RootKey "Root.Col" -ParentToChildren @{}

            $g.Nodes.Contains("Root.Col")  | Should -Be $true
            $g.Nodes.Contains("Child.Col") | Should -Be $true
            $g.DepthMap["Child.Col"]       | Should -Be 1
        }

        It "adds an edge between root and the referenced node" {
            $catalog = @{ "Root.Col" = '$SubField$' }
            $g = New-OneImAuditGraph -TemplateCatalog $catalog
            Invoke-OneImAuditGraphBFS -Graph $g -RootKey "Root.Col" -ParentToChildren @{}
            $g.AdjList["Root.Col"] -contains "Root.SubField" | Should -Be $true
        }
    }

    Context "FK successor expansion (ParentToChildren)" {
        It "adds child nodes from the schema FK index" {
            $p2c = @{ "Org.UID_Org" = @( New-FkChild "Person" "UID_Org" ) }
            $g = New-OneImAuditGraph
            Invoke-OneImAuditGraphBFS -Graph $g -RootKey "Org.UID_Org" -ParentToChildren $p2c

            $g.Nodes.Contains("Person.UID_Org") | Should -Be $true
            $g.DepthMap["Person.UID_Org"]        | Should -Be 1
        }

        It "does not visit the same node twice" {
            # Two parents both point to the same child
            $p2c = @{
                "Org.UID_Org"   = @( New-FkChild "Person" "UID_Org" )
                "Person.UID_Org" = @( New-FkChild "Person" "UID_Org" )   # self-loop would revisit
            }
            $g = New-OneImAuditGraph
            # Should not hang or add duplicates
            Invoke-OneImAuditGraphBFS -Graph $g -RootKey "Org.UID_Org" -ParentToChildren $p2c
            $g.Nodes.Count | Should -BeGreaterOrEqual 2
        }
    }

    Context "depth map" {
        It "records correct depth for multi-hop chain" {
            $catalog = @{
                "A.C" = 'FK(B.C)'
                "B.C" = 'FK(C.C)'
            }
            $g = New-OneImAuditGraph -TemplateCatalog $catalog
            Invoke-OneImAuditGraphBFS -Graph $g -RootKey "A.C" -ParentToChildren @{}
            $g.DepthMap["A.C"] | Should -Be 0
            $g.DepthMap["B.C"] | Should -Be 1
            $g.DepthMap["C.C"] | Should -Be 2
        }
    }
}

# ---------------------------------------------------------------------------
# Build-OneImAuditGraphReverseAdj
# ---------------------------------------------------------------------------
Describe "OneimAudit.Graph - Build-OneImAuditGraphReverseAdj" {

    Context "reverse adjacency" {
        It "creates reverse edge B->A for forward edge A->B" {
            $g = New-OneImAuditGraph
            Add-OneImAuditGraphNode -Graph $g -Key "A.X" | Out-Null
            Add-OneImAuditGraphNode -Graph $g -Key "B.Y" | Out-Null
            Add-OneImAuditGraphEdge -Graph $g -From "A.X" -To "B.Y"
            Build-OneImAuditGraphReverseAdj -Graph $g
            $g.ReverseAdj.Contains("B.Y") | Should -Be $true
            $g.ReverseAdj["B.Y"] -contains "A.X" | Should -Be $true
        }

        It "does not add reverse entry for nodes with no incoming edges" {
            $g = New-OneImAuditGraph
            Add-OneImAuditGraphNode -Graph $g -Key "A.X" | Out-Null
            Add-OneImAuditGraphNode -Graph $g -Key "B.Y" | Out-Null
            Add-OneImAuditGraphEdge -Graph $g -From "A.X" -To "B.Y"
            Build-OneImAuditGraphReverseAdj -Graph $g
            $g.ReverseAdj.Contains("A.X") | Should -Be $false
        }

        It "collects multiple predecessors for a shared target" {
            $g = New-OneImAuditGraph
            foreach ($k in @("A.X","B.Y","C.Z")) { Add-OneImAuditGraphNode -Graph $g -Key $k | Out-Null }
            Add-OneImAuditGraphEdge -Graph $g -From "A.X" -To "C.Z"
            Add-OneImAuditGraphEdge -Graph $g -From "B.Y" -To "C.Z"
            Build-OneImAuditGraphReverseAdj -Graph $g
            $g.ReverseAdj["C.Z"].Count | Should -Be 2
        }
    }
}

# ---------------------------------------------------------------------------
# Find-OneImAuditGraphCycles
# ---------------------------------------------------------------------------
Describe "OneimAudit.Graph - Find-OneImAuditGraphCycles" {

    Context "DAG (no cycles)" {
        It "produces no cycle edges for a straight chain A->B->C" {
            $g = New-OneImAuditGraph
            foreach ($k in @("A.X","B.Y","C.Z")) { Add-OneImAuditGraphNode -Graph $g -Key $k | Out-Null }
            Add-OneImAuditGraphEdge -Graph $g -From "A.X" -To "B.Y"
            Add-OneImAuditGraphEdge -Graph $g -From "B.Y" -To "C.Z"
            Find-OneImAuditGraphCycles -Graph $g
            $g.CycleEdges.Count | Should -Be 0
        }

        It "leaves in_cycle false for all nodes in a DAG" {
            $g = New-OneImAuditGraph
            foreach ($k in @("A.X","B.Y","C.Z")) { Add-OneImAuditGraphNode -Graph $g -Key $k | Out-Null }
            Add-OneImAuditGraphEdge -Graph $g -From "A.X" -To "B.Y"
            Add-OneImAuditGraphEdge -Graph $g -From "B.Y" -To "C.Z"
            Find-OneImAuditGraphCycles -Graph $g
            @($g.Nodes.Values | Where-Object { $_.in_cycle }).Count | Should -Be 0
        }
    }

    Context "simple 2-node cycle A->B->A" {
        It "detects a back edge" {
            $g = New-OneImAuditGraph
            foreach ($k in @("A.X","B.Y")) { Add-OneImAuditGraphNode -Graph $g -Key $k | Out-Null }
            Add-OneImAuditGraphEdge -Graph $g -From "A.X" -To "B.Y"
            Add-OneImAuditGraphEdge -Graph $g -From "B.Y" -To "A.X"
            Find-OneImAuditGraphCycles -Graph $g
            $g.CycleEdges.Count | Should -BeGreaterOrEqual 1
        }

        It "marks both nodes as in_cycle" {
            $g = New-OneImAuditGraph
            foreach ($k in @("A.X","B.Y")) { Add-OneImAuditGraphNode -Graph $g -Key $k | Out-Null }
            Add-OneImAuditGraphEdge -Graph $g -From "A.X" -To "B.Y"
            Add-OneImAuditGraphEdge -Graph $g -From "B.Y" -To "A.X"
            Find-OneImAuditGraphCycles -Graph $g
            $g.Nodes["A.X"].in_cycle | Should -Be $true
            $g.Nodes["B.Y"].in_cycle | Should -Be $true
        }

        It "cycle path contains both nodes and closes back to start" {
            $g = New-OneImAuditGraph
            foreach ($k in @("A.X","B.Y")) { Add-OneImAuditGraphNode -Graph $g -Key $k | Out-Null }
            Add-OneImAuditGraphEdge -Graph $g -From "A.X" -To "B.Y"
            Add-OneImAuditGraphEdge -Graph $g -From "B.Y" -To "A.X"
            Find-OneImAuditGraphCycles -Graph $g
            $path = $g.CycleEdges[0].path
            $path[0]            | Should -Be $path[$path.Count - 1]   # closed loop
            $path.Count         | Should -BeGreaterOrEqual 2
        }
    }

    Context "self-loop A->A" {
        It "detects a single-node self-loop" {
            $g = New-OneImAuditGraph
            Add-OneImAuditGraphNode -Graph $g -Key "A.X" | Out-Null
            Add-OneImAuditGraphEdge -Graph $g -From "A.X" -To "A.X"
            Find-OneImAuditGraphCycles -Graph $g
            $g.CycleEdges.Count     | Should -BeGreaterOrEqual 1
            $g.Nodes["A.X"].in_cycle | Should -Be $true
        }
    }

    Context "idempotency" {
        It "clears previous cycle data on second call" {
            $g = New-OneImAuditGraph
            foreach ($k in @("A.X","B.Y")) { Add-OneImAuditGraphNode -Graph $g -Key $k | Out-Null }
            Add-OneImAuditGraphEdge -Graph $g -From "A.X" -To "B.Y"
            Add-OneImAuditGraphEdge -Graph $g -From "B.Y" -To "A.X"
            Find-OneImAuditGraphCycles -Graph $g
            $firstCount = $g.CycleEdges.Count
            Find-OneImAuditGraphCycles -Graph $g
            $g.CycleEdges.Count | Should -Be $firstCount
        }
    }
}

# ---------------------------------------------------------------------------
# Get-OneImAuditGraphStats
# ---------------------------------------------------------------------------
Describe "OneimAudit.Graph - Get-OneImAuditGraphStats" {

    Context "empty graph" {
        It "returns zeros for all counts" {
            $g = New-OneImAuditGraph
            $s = Get-OneImAuditGraphStats -Graph $g
            $s.node_count     | Should -Be 0
            $s.edge_count     | Should -Be 0
            $s.cycle_count    | Should -Be 0
            $s.max_depth      | Should -Be 0
            $s.avg_out_degree | Should -Be 0
        }
    }

    Context "simple chain A->B->C" {
        $g = New-OneImAuditGraph -TemplateCatalog @{ "A.C" = 'FK(B.C)'; "B.C" = 'FK(C.C)' }
        Invoke-OneImAuditGraphBFS -Graph $g -RootKey "A.C" -ParentToChildren @{}
        Find-OneImAuditGraphCycles -Graph $g
        $s = Get-OneImAuditGraphStats -Graph $g

        It "node_count is 3" {
            $s.node_count | Should -Be 3
        }

        It "edge_count is 2" {
            $s.edge_count | Should -Be 2
        }

        It "cycle_count is 0" {
            $s.cycle_count | Should -Be 0
        }

        It "max_depth is 2" {
            $s.max_depth | Should -Be 2
        }

        It "avg_out_degree is edge_count / node_count" {
            # 2/3 = 0.667
            $s.avg_out_degree | Should -Be ([Math]::Round(2/3, 3))
        }
    }

    Context "graph with cycle" {
        It "cycle_count reflects cycles found by Find-OneImAuditGraphCycles" {
            $g = New-OneImAuditGraph
            foreach ($k in @("A.X","B.Y")) { Add-OneImAuditGraphNode -Graph $g -Key $k | Out-Null }
            Add-OneImAuditGraphEdge -Graph $g -From "A.X" -To "B.Y"
            Add-OneImAuditGraphEdge -Graph $g -From "B.Y" -To "A.X"
            Find-OneImAuditGraphCycles -Graph $g
            $s = Get-OneImAuditGraphStats -Graph $g
            $s.cycle_count | Should -BeGreaterOrEqual 1
        }
    }

    Context "output shape" {
        It "result has all required fields" {
            $g = New-OneImAuditGraph
            $s = Get-OneImAuditGraphStats -Graph $g
            $props = $s.PSObject.Properties.Name
            $props | Should -Contain "node_count"
            $props | Should -Contain "edge_count"
            $props | Should -Contain "cycle_count"
            $props | Should -Contain "max_depth"
            $props | Should -Contain "avg_out_degree"
        }
    }
}

# ---------------------------------------------------------------------------
# Get-OneImAuditDepthHistogram
# ---------------------------------------------------------------------------
Describe "OneimAudit.Graph - Get-OneImAuditDepthHistogram" {

    Context "empty graph (no BFS run)" {
        It "returns an empty array when DepthMap is empty" {
            $g = New-OneImAuditGraph
            $h = Get-OneImAuditDepthHistogram -Graph $g
            $h.Count | Should -Be 0
        }
    }

    Context "single root node" {
        It "returns one bucket at depth 0 with count 1" {
            $g = New-OneImAuditGraph
            Invoke-OneImAuditGraphBFS -Graph $g -RootKey "A.X" -ParentToChildren @{}
            $h = Get-OneImAuditDepthHistogram -Graph $g
            $h.Count      | Should -Be 1
            $h[0].depth   | Should -Be 0
            $h[0].count   | Should -Be 1
        }
    }

    Context "chain A->B->C (depths 0, 1, 2)" {
        $g = New-OneImAuditGraph -TemplateCatalog @{ "A.C" = 'FK(B.C)'; "B.C" = 'FK(C.C)' }
        Invoke-OneImAuditGraphBFS -Graph $g -RootKey "A.C" -ParentToChildren @{}
        $h = Get-OneImAuditDepthHistogram -Graph $g

        It "produces three depth buckets" {
            $h.Count | Should -Be 3
        }

        It "each depth has exactly one node" {
            $h[0].count | Should -Be 1
            $h[1].count | Should -Be 1
            $h[2].count | Should -Be 1
        }

        It "buckets are sorted ascending by depth" {
            $h[0].depth | Should -Be 0
            $h[1].depth | Should -Be 1
            $h[2].depth | Should -Be 2
        }
    }

    Context "diamond: A -> B, A -> C, B -> D, C -> D (two nodes at depth 1)" {
        $catalog = @{
            "A.X" = 'FK(B.Y) FK(C.Z)'
            "B.Y" = 'FK(D.W)'
            "C.Z" = 'FK(D.W)'
        }
        $g = New-OneImAuditGraph -TemplateCatalog $catalog
        Invoke-OneImAuditGraphBFS -Graph $g -RootKey "A.X" -ParentToChildren @{}
        $h = Get-OneImAuditDepthHistogram -Graph $g

        It "depth 1 bucket has count 2" {
            $depth1 = $h | Where-Object { $_.depth -eq 1 }
            $depth1.count | Should -Be 2
        }

        It "depth 2 bucket has count 1 (D is visited only once)" {
            $depth2 = $h | Where-Object { $_.depth -eq 2 }
            $depth2.count | Should -Be 1
        }
    }

    Context "output shape" {
        It "each histogram entry has depth and count fields" {
            $g = New-OneImAuditGraph
            Invoke-OneImAuditGraphBFS -Graph $g -RootKey "T.Col" -ParentToChildren @{}
            $h = Get-OneImAuditDepthHistogram -Graph $g
            $props = $h[0].PSObject.Properties.Name
            $props | Should -Contain "depth"
            $props | Should -Contain "count"
        }
    }
}

# ---------------------------------------------------------------------------
# Invoke-OneImAuditTopologicalSort
# ---------------------------------------------------------------------------
Describe "OneimAudit.Graph - Invoke-OneImAuditTopologicalSort" {

    Context "empty graph" {
        It "returns empty order and empty cycle_node_keys" {
            $g = New-OneImAuditGraph
            $r = Invoke-OneImAuditTopologicalSort -Graph $g
            $r.order.Count           | Should -Be 0
            $r.cycle_node_keys.Count | Should -Be 0
        }
    }

    Context "single node, no edges" {
        It "order contains the single node" {
            $g = New-OneImAuditGraph
            Add-OneImAuditGraphNode -Graph $g -Key "A.X" | Out-Null
            $r = Invoke-OneImAuditTopologicalSort -Graph $g
            $r.order           | Should -Contain "A.X"
            $r.cycle_node_keys | Should -Not -Contain "A.X"
        }
    }

    Context "chain A->B->C (DAG)" {
        $g = New-OneImAuditGraph -TemplateCatalog @{ "A.X" = 'FK(B.Y)'; "B.Y" = 'FK(C.Z)' }
        Invoke-OneImAuditGraphBFS -Graph $g -RootKey "A.X" -ParentToChildren @{}
        Find-OneImAuditGraphCycles -Graph $g
        $r = Invoke-OneImAuditTopologicalSort -Graph $g

        It "all three nodes are in the order" {
            $r.order.Count | Should -Be 3
        }

        It "A.X appears before B.Y in the ordering" {
            $idxA = [Array]::IndexOf($r.order, "A.X")
            $idxB = [Array]::IndexOf($r.order, "B.Y")
            $idxA | Should -BeLessThan $idxB
        }

        It "B.Y appears before C.Z in the ordering" {
            $idxB = [Array]::IndexOf($r.order, "B.Y")
            $idxC = [Array]::IndexOf($r.order, "C.Z")
            $idxB | Should -BeLessThan $idxC
        }

        It "no cycle_node_keys for a DAG" {
            $r.cycle_node_keys.Count | Should -Be 0
        }
    }

    Context "graph with a 2-node cycle A->B->A" {
        $g = New-OneImAuditGraph
        foreach ($k in @("A.X","B.Y")) { Add-OneImAuditGraphNode -Graph $g -Key $k | Out-Null }
        Add-OneImAuditGraphEdge -Graph $g -From "A.X" -To "B.Y"
        Add-OneImAuditGraphEdge -Graph $g -From "B.Y" -To "A.X"
        Find-OneImAuditGraphCycles -Graph $g
        $r = Invoke-OneImAuditTopologicalSort -Graph $g

        It "cycle nodes are excluded from order" {
            $r.order.Count | Should -Be 0
        }

        It "both nodes appear in cycle_node_keys" {
            $r.cycle_node_keys | Should -Contain "A.X"
            $r.cycle_node_keys | Should -Contain "B.Y"
        }
    }

    Context "mixed graph: DAG node + cycle" {
        # Root -> A (in cycle A->B->A); Root -> C (pure DAG leaf)
        $g = New-OneImAuditGraph
        foreach ($k in @("Root.X","A.X","B.Y","C.Z")) {
            Add-OneImAuditGraphNode -Graph $g -Key $k | Out-Null
        }
        Add-OneImAuditGraphEdge -Graph $g -From "Root.X" -To "A.X"
        Add-OneImAuditGraphEdge -Graph $g -From "Root.X" -To "C.Z"
        Add-OneImAuditGraphEdge -Graph $g -From "A.X"    -To "B.Y"
        Add-OneImAuditGraphEdge -Graph $g -From "B.Y"    -To "A.X"
        Find-OneImAuditGraphCycles -Graph $g
        $r = Invoke-OneImAuditTopologicalSort -Graph $g

        It "non-cycle nodes (Root.X, C.Z) are in the order" {
            $r.order | Should -Contain "Root.X"
            $r.order | Should -Contain "C.Z"
        }

        It "cycle nodes (A.X, B.Y) are in cycle_node_keys" {
            $r.cycle_node_keys | Should -Contain "A.X"
            $r.cycle_node_keys | Should -Contain "B.Y"
        }

        It "Root.X appears before C.Z (dependency order)" {
            $idxRoot = [Array]::IndexOf($r.order, "Root.X")
            $idxC    = [Array]::IndexOf($r.order, "C.Z")
            $idxRoot | Should -BeLessThan $idxC
        }
    }

    Context "output shape" {
        It "result has order and cycle_node_keys fields" {
            $g = New-OneImAuditGraph
            $r = Invoke-OneImAuditTopologicalSort -Graph $g
            $props = $r.PSObject.Properties.Name
            $props | Should -Contain "order"
            $props | Should -Contain "cycle_node_keys"
        }
    }
}

# ---------------------------------------------------------------------------
# Find-OneImAuditSCCs
# ---------------------------------------------------------------------------
Describe "OneimAudit.Graph - Find-OneImAuditSCCs" {

    # Helper: build a graph, wire edges, build reverse adj, then call Find-OneImAuditSCCs
    function New-SccGraph {
        param([string[]]$Keys, [string[][]]$Edges)
        $g = New-OneImAuditGraph
        foreach ($k in $Keys) { Add-OneImAuditGraphNode -Graph $g -Key $k | Out-Null }
        foreach ($e in $Edges) { Add-OneImAuditGraphEdge -Graph $g -From $e[0] -To $e[1] }
        Build-OneImAuditGraphReverseAdj -Graph $g
        return $g
    }

    Context "empty graph" {
        It "returns an empty array when the graph has no nodes" {
            $g = New-OneImAuditGraph
            Build-OneImAuditGraphReverseAdj -Graph $g
            $sccs = Find-OneImAuditSCCs -Graph $g
            $sccs.Count | Should -Be 0
        }
    }

    Context "single node, no edges" {
        $g   = New-SccGraph -Keys @("A.X") -Edges @()
        $sccs = Find-OneImAuditSCCs -Graph $g

        It "produces exactly one SCC" {
            $sccs.Count | Should -Be 1
        }

        It "SCC has size 1" {
            $sccs[0].size | Should -Be 1
        }

        It "concurrency_risk is 'none' for a singleton SCC" {
            $sccs[0].concurrency_risk | Should -Be "none"
        }

        It "node gets scc_id set" {
            $g.Nodes["A.X"].scc_id | Should -BeGreaterThan 0
        }

        It "node scc_size is 1" {
            $g.Nodes["A.X"].scc_size | Should -Be 1
        }
    }

    Context "DAG chain A->B->C (no cycles)" {
        $g    = New-SccGraph -Keys @("A.X","B.Y","C.Z") -Edges @(@("A.X","B.Y"),@("B.Y","C.Z"))
        $sccs = Find-OneImAuditSCCs -Graph $g

        It "produces three SCCs (each node is its own component)" {
            $sccs.Count | Should -Be 3
        }

        It "all SCCs have size 1" {
            @($sccs | Where-Object { $_.size -ne 1 }).Count | Should -Be 0
        }

        It "all SCCs have concurrency_risk 'none'" {
            @($sccs | Where-Object { $_.concurrency_risk -ne "none" }).Count | Should -Be 0
        }

        It "every node gets a unique scc_id" {
            $ids = @($g.Nodes.Values | ForEach-Object { $_.scc_id })
            ($ids | Sort-Object -Unique).Count | Should -Be 3
        }
    }

    Context "simple 2-node cycle A->B->A" {
        $g    = New-SccGraph -Keys @("A.X","B.Y") -Edges @(@("A.X","B.Y"),@("B.Y","A.X"))
        $sccs = Find-OneImAuditSCCs -Graph $g

        It "produces exactly one SCC" {
            $sccs.Count | Should -Be 1
        }

        It "SCC contains both nodes" {
            $sccs[0].members | Should -Contain "A.X"
            $sccs[0].members | Should -Contain "B.Y"
        }

        It "SCC size is 2" {
            $sccs[0].size | Should -Be 2
        }

        It "concurrency_risk is 'read-cycle'" {
            $sccs[0].concurrency_risk | Should -Be "read-cycle"
        }

        It "both nodes share the same scc_id" {
            $g.Nodes["A.X"].scc_id | Should -Be $g.Nodes["B.Y"].scc_id
        }

        It "both nodes have scc_size 2" {
            $g.Nodes["A.X"].scc_size | Should -Be 2
            $g.Nodes["B.Y"].scc_size | Should -Be 2
        }
    }

    Context "self-loop A->A" {
        # Comma operator prevents @() from unrolling the single inner array
        $g    = New-SccGraph -Keys @("A.X") -Edges @(,@("A.X","A.X"))
        $sccs = Find-OneImAuditSCCs -Graph $g

        It "produces one SCC" {
            $sccs.Count | Should -Be 1
        }

        It "SCC size is 1 (single node despite self-loop)" {
            $sccs[0].size | Should -Be 1
        }

        It "concurrency_risk is 'none' for self-loop singleton" {
            $sccs[0].concurrency_risk | Should -Be "none"
        }
    }

    Context "3-node cycle A->B->C->A" {
        $g    = New-SccGraph -Keys @("A.X","B.Y","C.Z") -Edges @(@("A.X","B.Y"),@("B.Y","C.Z"),@("C.Z","A.X"))
        $sccs = Find-OneImAuditSCCs -Graph $g

        It "produces one SCC" {
            $sccs.Count | Should -Be 1
        }

        It "SCC size is 3" {
            $sccs[0].size | Should -Be 3
        }

        It "all three nodes are members" {
            $sccs[0].members | Should -Contain "A.X"
            $sccs[0].members | Should -Contain "B.Y"
            $sccs[0].members | Should -Contain "C.Z"
        }
    }

    Context "mixed: tail -> cycle -> sink (E->A->B->A, B->D)" {
        # E is a tail (no back-edges into cycle)
        # A, B form a cycle
        # D is a sink
        $keys  = @("E.X","A.X","B.Y","D.Z")
        $edges = @(@("E.X","A.X"),@("A.X","B.Y"),@("B.Y","A.X"),@("B.Y","D.Z"))
        $g     = New-SccGraph -Keys $keys -Edges $edges
        $sccs  = Find-OneImAuditSCCs -Graph $g

        It "produces three SCCs total" {
            $sccs.Count | Should -Be 3
        }

        It "the cycle SCC (A, B) has size 2" {
            $cycleScc = $sccs | Where-Object { $_.size -eq 2 }
            $cycleScc | Should -Not -BeNullOrEmpty
            $cycleScc.members | Should -Contain "A.X"
            $cycleScc.members | Should -Contain "B.Y"
        }

        It "E and D are singleton SCCs" {
            ($sccs | Where-Object { $_.size -eq 1 }).Count | Should -Be 2
        }

        It "E.X and D.Z have scc_size 1" {
            $g.Nodes["E.X"].scc_size | Should -Be 1
            $g.Nodes["D.Z"].scc_size | Should -Be 1
        }

        It "A and B share scc_id and scc_size 2" {
            $g.Nodes["A.X"].scc_id   | Should -Be $g.Nodes["B.Y"].scc_id
            $g.Nodes["A.X"].scc_size | Should -Be 2
        }
    }

    Context "idempotency" {
        It "clears and recomputes scc_id on second call" {
            $g = New-SccGraph -Keys @("A.X","B.Y") -Edges @(@("A.X","B.Y"),@("B.Y","A.X"))
            $null = Find-OneImAuditSCCs -Graph $g
            $firstId = $g.Nodes["A.X"].scc_id
            $null = Find-OneImAuditSCCs -Graph $g
            $g.Nodes["A.X"].scc_id | Should -Be $firstId
            $g.Nodes["A.X"].scc_size | Should -Be 2
        }
    }

    Context "output shape" {
        It "each SCC entry has required fields" {
            $g    = New-SccGraph -Keys @("A.X") -Edges @()
            $sccs = Find-OneImAuditSCCs -Graph $g
            $props = $sccs[0].PSObject.Properties.Name
            $props | Should -Contain "scc_id"
            $props | Should -Contain "members"
            $props | Should -Contain "size"
            $props | Should -Contain "concurrency_risk"
        }

        It "nodes have scc_id and scc_size fields after Add-OneImAuditGraphNode" {
            $g = New-OneImAuditGraph
            $n = Add-OneImAuditGraphNode -Graph $g -Key "T.Col"
            $n.PSObject.Properties.Name | Should -Contain "scc_id"
            $n.PSObject.Properties.Name | Should -Contain "scc_size"
        }

        Context "is_writer flag and write-cycle upgrade" {

            It "node has is_writer=false by default" {
                $g = New-OneImAuditGraph
                $n = Add-OneImAuditGraphNode -Graph $g -Key "A.X"
                $n.is_writer | Should -Be $false
            }

            It "node has is_writer=true when -IsWriter is set" {
                $g = New-OneImAuditGraph
                $n = Add-OneImAuditGraphNode -Graph $g -Key "A.X" -IsWriter
                $n.is_writer | Should -Be $true
            }

            It "concurrency_risk is 'read-cycle' when no member is a writer" {
                $g = New-OneImAuditGraph
                Add-OneImAuditGraphNode -Graph $g -Key "A.X" | Out-Null
                Add-OneImAuditGraphNode -Graph $g -Key "B.Y" | Out-Null
                Add-OneImAuditGraphEdge -Graph $g -From "A.X" -To "B.Y"
                Add-OneImAuditGraphEdge -Graph $g -From "B.Y" -To "A.X"
                Build-OneImAuditGraphReverseAdj -Graph $g
                $sccs = @(Find-OneImAuditSCCs -Graph $g)
                $cycleScc = @($sccs | Where-Object { $_.size -eq 2 })
                $cycleScc[0].concurrency_risk | Should -Be "read-cycle"
            }

            It "concurrency_risk is 'write-cycle' when at least one member is a writer" {
                $g = New-OneImAuditGraph
                Add-OneImAuditGraphNode -Graph $g -Key "A.X" -IsWriter | Out-Null
                Add-OneImAuditGraphNode -Graph $g -Key "B.Y" | Out-Null
                Add-OneImAuditGraphEdge -Graph $g -From "A.X" -To "B.Y"
                Add-OneImAuditGraphEdge -Graph $g -From "B.Y" -To "A.X"
                Build-OneImAuditGraphReverseAdj -Graph $g
                $sccs = @(Find-OneImAuditSCCs -Graph $g)
                $cycleScc = @($sccs | Where-Object { $_.size -eq 2 })
                $cycleScc[0].concurrency_risk | Should -Be "write-cycle"
            }

            It "singleton SCCs remain 'none' even when is_writer is set" {
                $g = New-OneImAuditGraph
                Add-OneImAuditGraphNode -Graph $g -Key "A.X" -IsWriter | Out-Null
                Build-OneImAuditGraphReverseAdj -Graph $g
                $sccs = @(Find-OneImAuditSCCs -Graph $g)
                $sccs[0].concurrency_risk | Should -Be "none"
            }

            It "3-node cycle is 'write-cycle' when any one member is a writer" {
                $g = New-OneImAuditGraph
                Add-OneImAuditGraphNode -Graph $g -Key "A.X" | Out-Null
                Add-OneImAuditGraphNode -Graph $g -Key "B.Y" | Out-Null
                Add-OneImAuditGraphNode -Graph $g -Key "C.Z" -IsWriter | Out-Null
                Add-OneImAuditGraphEdge -Graph $g -From "A.X" -To "B.Y"
                Add-OneImAuditGraphEdge -Graph $g -From "B.Y" -To "C.Z"
                Add-OneImAuditGraphEdge -Graph $g -From "C.Z" -To "A.X"
                Build-OneImAuditGraphReverseAdj -Graph $g
                $sccs = @(Find-OneImAuditSCCs -Graph $g)
                $cycleScc = @($sccs | Where-Object { $_.size -eq 3 })
                $cycleScc[0].concurrency_risk | Should -Be "write-cycle"
            }
        }
    }
}

# ---------------------------------------------------------------------------
# Get-OneImAuditCriticalPath
# ---------------------------------------------------------------------------
Describe "OneimAudit.Graph - Get-OneImAuditCriticalPath" {

    # Helper: build a directed graph with optional avg_ms on nodes
    function New-CpGraph {
        param([string[]]$Keys, [string[][]]$Edges, [hashtable]$AvgMs = @{})
        $bench = @{}
        foreach ($k in $AvgMs.Keys) { $bench["template::$k"] = [pscustomobject]@{ stats = [pscustomobject]@{ avg_ms = $AvgMs[$k] } } }
        $g = New-OneImAuditGraph -BenchData $bench
        foreach ($k in $Keys) { Add-OneImAuditGraphNode -Graph $g -Key $k | Out-Null }
        foreach ($e in $Edges) { Add-OneImAuditGraphEdge -Graph $g -From $e[0] -To $e[1] }
        Build-OneImAuditGraphReverseAdj -Graph $g
        return $g
    }

    Context "empty graph" {
        It "returns empty critical_path and total_ms=0" {
            $g = New-OneImAuditGraph
            $r = Get-OneImAuditCriticalPath -Graph $g
            $r.critical_path.Count | Should -Be 0
            $r.total_ms             | Should -Be 0
        }

        It "has_benchmark_data is false for empty graph" {
            $g = New-OneImAuditGraph
            $r = Get-OneImAuditCriticalPath -Graph $g
            $r.has_benchmark_data | Should -Be $false
        }
    }

    Context "single node, no benchmark data" {
        It "path contains the single node, total_ms=0, has_benchmark_data=false" {
            $g = New-CpGraph -Keys @("A.X") -Edges @()
            $r = Get-OneImAuditCriticalPath -Graph $g
            $r.total_ms             | Should -Be 0
            $r.has_benchmark_data   | Should -Be $false
        }
    }

    Context "single node with avg_ms" {
        It "total_ms equals the single node avg_ms" {
            # Set avg_ms directly on the node rather than via bench lookup
            $g = New-CpGraph -Keys @("A.X") -Edges @()
            $g.Nodes["A.X"].avg_ms = 10.0
            $r = Get-OneImAuditCriticalPath -Graph $g
            $r.total_ms           | Should -Be 10.0
            $r.has_benchmark_data | Should -Be $true
        }

        It "critical_path contains the single node key" {
            $g = New-CpGraph -Keys @("A.X") -Edges @()
            $g.Nodes["A.X"].avg_ms = 5.0
            $r = Get-OneImAuditCriticalPath -Graph $g
            $r.critical_path | Should -Contain "A.X"
        }
    }

    Context "linear chain A(10) -> B(5) -> C(2)" {
        $g = New-CpGraph -Keys @("A.X","B.Y","C.Z") -Edges @(@("A.X","B.Y"),@("B.Y","C.Z"))
        $g.Nodes["A.X"].avg_ms = 10.0
        $g.Nodes["B.Y"].avg_ms = 5.0
        $g.Nodes["C.Z"].avg_ms = 2.0
        $r = Get-OneImAuditCriticalPath -Graph $g

        It "total_ms is sum of all node costs (17)" {
            $r.total_ms | Should -Be 17.0
        }

        It "critical_path contains all three nodes in order" {
            $r.critical_path[0] | Should -Be "A.X"
            $r.critical_path[1] | Should -Be "B.Y"
            $r.critical_path[2] | Should -Be "C.Z"
        }

        It "has_benchmark_data is true" {
            $r.has_benchmark_data | Should -Be $true
        }
    }

    Context "diamond: A->B(20), A->C(5), B->D, C->D; D(1)" {
        # Critical path: A->B->D (heavier arm)
        $g = New-CpGraph -Keys @("A.W","B.X","C.Y","D.Z") `
            -Edges @(@("A.W","B.X"),@("A.W","C.Y"),@("B.X","D.Z"),@("C.Y","D.Z"))
        $g.Nodes["A.W"].avg_ms = 0.0
        $g.Nodes["B.X"].avg_ms = 20.0
        $g.Nodes["C.Y"].avg_ms = 5.0
        $g.Nodes["D.Z"].avg_ms = 1.0
        $r = Get-OneImAuditCriticalPath -Graph $g

        It "critical path passes through B.X (heavier arm)" {
            $r.critical_path | Should -Contain "B.X"
        }

        It "total_ms equals heavier arm cost (0+20+1=21)" {
            $r.total_ms | Should -Be 21.0
        }
    }

    Context "output shape" {
        It "result has critical_path, total_ms, node_dp, has_benchmark_data" {
            $g = New-CpGraph -Keys @("A.X") -Edges @()
            $r = Get-OneImAuditCriticalPath -Graph $g
            $props = $r.PSObject.Properties.Name
            $props | Should -Contain "critical_path"
            $props | Should -Contain "total_ms"
            $props | Should -Contain "node_dp"
            $props | Should -Contain "has_benchmark_data"
        }
    }
}

# ---------------------------------------------------------------------------
# Find-OneImAuditArticulationPoints
# ---------------------------------------------------------------------------
Describe "OneimAudit.Graph - Find-OneImAuditArticulationPoints" {

    # Helper: directed edges are mirrored to undirected inside the function
    function New-ApGraph {
        param([string[]]$Keys, [string[][]]$Edges)
        $g = New-OneImAuditGraph
        foreach ($k in $Keys) { Add-OneImAuditGraphNode -Graph $g -Key $k | Out-Null }
        foreach ($e in $Edges) { Add-OneImAuditGraphEdge -Graph $g -From $e[0] -To $e[1] }
        Build-OneImAuditGraphReverseAdj -Graph $g
        return $g
    }

    Context "empty graph" {
        It "returns empty array" {
            $g  = New-OneImAuditGraph
            # Do not wrap with @() — NoEnumerate causes @() to produce a nested array
            $ap = Find-OneImAuditArticulationPoints -Graph $g
            $ap.Count | Should -Be 0
        }
    }

    Context "single node, no edges" {
        It "returns empty array (a single node cannot be an AP)" {
            $g  = New-ApGraph -Keys @("A.X") -Edges @()
            $ap = Find-OneImAuditArticulationPoints -Graph $g
            $ap.Count | Should -Be 0
        }
    }

    Context "two nodes connected by a single edge" {
        It "neither node is an AP (removing either leaves a singleton)" {
            # With only 2 nodes an AP would require 2+ components after removal,
            # but each remaining component has only 1 node -- still connected.
            $g  = New-ApGraph -Keys @("A.X","B.Y") -Edges @(,@("A.X","B.Y"))
            $ap = Find-OneImAuditArticulationPoints -Graph $g
            $ap.Count | Should -Be 0
        }
    }

    Context "chain A.X -> B.Y -> C.Z (treated undirected: A-B-C)" {
        $g  = New-ApGraph -Keys @("A.X","B.Y","C.Z") -Edges @(@("A.X","B.Y"),@("B.Y","C.Z"))
        $ap = Find-OneImAuditArticulationPoints -Graph $g

        It "B.Y is the only articulation point" {
            $ap | Should -Contain "B.Y"
            $ap.Count | Should -Be 1
        }
    }

    Context "triangle A-B-C (A->B->C->A) — no APs" {
        It "returns empty array because every node has an alternative path" {
            $g  = New-ApGraph -Keys @("A.X","B.Y","C.Z") `
                -Edges @(@("A.X","B.Y"),@("B.Y","C.Z"),@("C.Z","A.X"))
            $ap = Find-OneImAuditArticulationPoints -Graph $g
            $ap.Count | Should -Be 0
        }
    }

    Context "two triangles joined by a bridge C.Z -> D.W" {
        # Triangle 1: A.X - B.Y - C.Z - A.X
        # Bridge:     C.Z - D.W
        # Triangle 2: D.W - E.V - F.U - D.W
        # Removing C.Z or D.W disconnects the two clusters.
        $keys  = @("A.X","B.Y","C.Z","D.W","E.V","F.U")
        $edges = @(
            @("A.X","B.Y"), @("B.Y","C.Z"), @("C.Z","A.X"),   # triangle 1
            @("C.Z","D.W"),                                      # bridge
            @("D.W","E.V"), @("E.V","F.U"), @("F.U","D.W")     # triangle 2
        )
        $g  = New-ApGraph -Keys $keys -Edges $edges
        $ap = Find-OneImAuditArticulationPoints -Graph $g

        It "C.Z is an articulation point" {
            $ap | Should -Contain "C.Z"
        }

        It "D.W is an articulation point" {
            $ap | Should -Contain "D.W"
        }

        It "triangle interior nodes (A.X, B.Y, E.V, F.U) are not APs" {
            $ap | Should -Not -Contain "A.X"
            $ap | Should -Not -Contain "B.Y"
            $ap | Should -Not -Contain "E.V"
            $ap | Should -Not -Contain "F.U"
        }
    }
}

# ---------------------------------------------------------------------------
# Get-OneImAuditFeedbackArcSet
# ---------------------------------------------------------------------------
Describe "OneimAudit.Graph - Get-OneImAuditFeedbackArcSet" {

    # Helper: builds graph, calls Find-OneImAuditSCCs so scc_id / scc_size are set
    function New-FasGraph {
        param([string[]]$Keys, [string[][]]$Edges)
        $g = New-OneImAuditGraph
        foreach ($k in $Keys) { Add-OneImAuditGraphNode -Graph $g -Key $k | Out-Null }
        foreach ($e in $Edges) { Add-OneImAuditGraphEdge -Graph $g -From $e[0] -To $e[1] }
        Build-OneImAuditGraphReverseAdj -Graph $g
        $null = Find-OneImAuditSCCs -Graph $g
        return $g
    }

    Context "acyclic graph (no multi-node SCCs)" {
        It "count is 0 and edges is empty" {
            $g   = New-FasGraph -Keys @("A.X","B.Y","C.Z") -Edges @(@("A.X","B.Y"),@("B.Y","C.Z"))
            $fas = Get-OneImAuditFeedbackArcSet -Graph $g
            $fas.count          | Should -Be 0
            $fas.edges.Count    | Should -Be 0
        }
    }

    Context "2-node cycle A.X <-> B.Y" {
        $g   = New-FasGraph -Keys @("A.X","B.Y") -Edges @(@("A.X","B.Y"),@("B.Y","A.X"))
        $fas = Get-OneImAuditFeedbackArcSet -Graph $g

        It "returns exactly 1 feedback edge" {
            $fas.count | Should -Be 1
        }

        It "the feedback edge connects the two cycle nodes" {
            $e = $fas.edges[0]
            @("A.X","B.Y") | Should -Contain $e.from
            @("A.X","B.Y") | Should -Contain $e.to
        }

        It "each edge has from, to, scc_id fields" {
            $props = $fas.edges[0].PSObject.Properties.Name
            $props | Should -Contain "from"
            $props | Should -Contain "to"
            $props | Should -Contain "scc_id"
        }
    }

    Context "3-node cycle A->B->C->A" {
        It "returns at least 1 feedback edge (greedy minimum)" {
            $g   = New-FasGraph -Keys @("A.X","B.Y","C.Z") `
                -Edges @(@("A.X","B.Y"),@("B.Y","C.Z"),@("C.Z","A.X"))
            $fas = Get-OneImAuditFeedbackArcSet -Graph $g
            $fas.count | Should -BeGreaterThan 0
        }
    }

    Context "output shape" {
        It "result has edges array and count int" {
            $g   = New-FasGraph -Keys @("A.X") -Edges @()
            $fas = Get-OneImAuditFeedbackArcSet -Graph $g
            $props = $fas.PSObject.Properties.Name
            $props | Should -Contain "edges"
            $props | Should -Contain "count"
        }
    }
}

# ---------------------------------------------------------------------------
# Build-OneImAuditDominatorTree
# ---------------------------------------------------------------------------
Describe "OneimAudit.Graph - Build-OneImAuditDominatorTree" {

    function New-DomGraph {
        param([string[]]$Keys, [string[][]]$Edges)
        $g = New-OneImAuditGraph
        foreach ($k in $Keys) { Add-OneImAuditGraphNode -Graph $g -Key $k | Out-Null }
        foreach ($e in $Edges) { Add-OneImAuditGraphEdge -Graph $g -From $e[0] -To $e[1] }
        Build-OneImAuditGraphReverseAdj -Graph $g
        return $g
    }

    Context "root key not in graph" {
        It "returns empty idom and dominated_sets" {
            $g = New-DomGraph -Keys @("A.X") -Edges @()
            $d = Build-OneImAuditDominatorTree -Graph $g -RootKey "Missing.Node"
            $d.idom.Count           | Should -Be 0
            $d.dominated_sets.Count | Should -Be 0
        }
    }

    Context "single node graph, root = that node" {
        $g = New-DomGraph -Keys @("A.X") -Edges @()
        $d = Build-OneImAuditDominatorTree -Graph $g -RootKey "A.X"

        It "root property equals RootKey" {
            $d.root | Should -Be "A.X"
        }

        It "idom[root] = root (root dominates itself)" {
            $d.idom["A.X"] | Should -Be "A.X"
        }

        It "root has no immediately dominated children" {
            $d.dominated_sets["A.X"].Count | Should -Be 0
        }
    }

    Context "linear chain A.X -> B.Y -> C.Z, root=A.X" {
        $g = New-DomGraph -Keys @("A.X","B.Y","C.Z") -Edges @(@("A.X","B.Y"),@("B.Y","C.Z"))
        $d = Build-OneImAuditDominatorTree -Graph $g -RootKey "A.X"

        It "idom[B.Y] = A.X" {
            $d.idom["B.Y"] | Should -Be "A.X"
        }

        It "idom[C.Z] = B.Y" {
            $d.idom["C.Z"] | Should -Be "B.Y"
        }

        It "A.X immediately dominates B.Y" {
            $d.dominated_sets["A.X"] | Should -Contain "B.Y"
        }

        It "B.Y immediately dominates C.Z" {
            $d.dominated_sets["B.Y"] | Should -Contain "C.Z"
        }
    }

    Context "diamond: A.W->B.X, A.W->C.Y, B.X->D.Z, C.Y->D.Z; root=A.W" {
        # A dominates all. B dominates only B. C dominates only C.
        # D's immediate dominator is A (both B and C paths go through A).
        $g = New-DomGraph -Keys @("A.W","B.X","C.Y","D.Z") `
            -Edges @(@("A.W","B.X"),@("A.W","C.Y"),@("B.X","D.Z"),@("C.Y","D.Z"))
        $d = Build-OneImAuditDominatorTree -Graph $g -RootKey "A.W"

        It "idom[D.Z] = A.W (both paths merge back through A)" {
            $d.idom["D.Z"] | Should -Be "A.W"
        }

        It "idom[B.X] = A.W" {
            $d.idom["B.X"] | Should -Be "A.W"
        }

        It "idom[C.Y] = A.W" {
            $d.idom["C.Y"] | Should -Be "A.W"
        }
    }

    Context "output shape" {
        It "result has root, idom, dominated_sets" {
            $g = New-DomGraph -Keys @("A.X") -Edges @()
            $d = Build-OneImAuditDominatorTree -Graph $g -RootKey "A.X"
            $props = $d.PSObject.Properties.Name
            $props | Should -Contain "root"
            $props | Should -Contain "idom"
            $props | Should -Contain "dominated_sets"
        }
    }
}

# ---------------------------------------------------------------------------
# Get-OneImAuditBetweennessCentrality
# ---------------------------------------------------------------------------
Describe "OneimAudit.Graph - Get-OneImAuditBetweennessCentrality" {

    function New-BcGraph {
        param([string[]]$Keys, [string[][]]$Edges)
        $g = New-OneImAuditGraph
        foreach ($k in $Keys) { Add-OneImAuditGraphNode -Graph $g -Key $k | Out-Null }
        foreach ($e in $Edges) { Add-OneImAuditGraphEdge -Graph $g -From $e[0] -To $e[1] }
        Build-OneImAuditGraphReverseAdj -Graph $g
        return $g
    }

    Context "empty graph" {
        It "returns empty hashtable" {
            $g  = New-OneImAuditGraph
            $bc = Get-OneImAuditBetweennessCentrality -Graph $g
            $bc.Count | Should -Be 0
        }
    }

    Context "single node" {
        It "score is 0 for a node with no edges" {
            $g  = New-BcGraph -Keys @("A.X") -Edges @()
            $bc = Get-OneImAuditBetweennessCentrality -Graph $g
            $bc["A.X"] | Should -Be 0
        }
    }

    Context "two nodes" {
        It "both scores are 0 (no node mediates any path between others)" {
            $g  = New-BcGraph -Keys @("A.X","B.Y") -Edges @(,@("A.X","B.Y"))
            $bc = Get-OneImAuditBetweennessCentrality -Graph $g
            $bc["A.X"] | Should -Be 0
            $bc["B.Y"] | Should -Be 0
        }
    }

    Context "chain A.X -> B.Y -> C.Z" {
        $g  = New-BcGraph -Keys @("A.X","B.Y","C.Z") -Edges @(@("A.X","B.Y"),@("B.Y","C.Z"))
        $bc = Get-OneImAuditBetweennessCentrality -Graph $g

        It "B.Y has the highest score (it mediates the A->C path)" {
            $bc["B.Y"] | Should -BeGreaterThan $bc["A.X"]
            $bc["B.Y"] | Should -BeGreaterThan $bc["C.Z"]
        }

        It "all three nodes are present in the result" {
            $bc.ContainsKey("A.X") | Should -Be $true
            $bc.ContainsKey("B.Y") | Should -Be $true
            $bc.ContainsKey("C.Z") | Should -Be $true
        }
    }

    Context "result is a regular hashtable (not PSCustomObject)" {
        It "result has ContainsKey method (i.e. is a hashtable)" {
            $g  = New-BcGraph -Keys @("A.X") -Edges @()
            $bc = Get-OneImAuditBetweennessCentrality -Graph $g
            { $bc.ContainsKey("A.X") } | Should -Not -Throw
        }
    }

    Context "star topology: hub H.X with 3 spokes A.X B.Y C.Z (all edges to hub)" {
        # A.X->H.X, B.Y->H.X, C.Z->H.X
        # H.X mediates no directed paths (it's a sink), spokes have no paths through each other.
        # All scores should be 0 in a directed graph where hub is a pure sink.
        It "hub score is 0 in a pure-sink directed star" {
            $g  = New-BcGraph -Keys @("H.X","A.X","B.Y","C.Z") `
                -Edges @(@("A.X","H.X"),@("B.Y","H.X"),@("C.Z","H.X"))
            $bc = Get-OneImAuditBetweennessCentrality -Graph $g
            $bc["H.X"] | Should -Be 0
        }
    }

    Context "scores are normalized (between 0 and 1 inclusive)" {
        It "no score exceeds 1.0 for a simple chain" {
            $g  = New-BcGraph -Keys @("A.X","B.Y","C.Z","D.W") `
                -Edges @(@("A.X","B.Y"),@("B.Y","C.Z"),@("C.Z","D.W"))
            $bc = Get-OneImAuditBetweennessCentrality -Graph $g
            foreach ($key in $bc.Keys) {
                $bc[$key] | Should -BeLessOrEqual 1.0
                $bc[$key] | Should -BeGreaterOrEqual 0.0
            }
        }
    }
}
