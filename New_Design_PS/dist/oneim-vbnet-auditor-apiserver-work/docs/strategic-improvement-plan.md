# Strategic Improvement Plan: OneIM VB.NET Auditor

## Orientation Summary

The codebase has three well-separated concerns: a static analysis engine (Lane 1, well-tested), a schema exporter (Lane 2, untested), and a benchmark + cascade graph engine (Lane 3, untested). The core engine in `OneimAudit.Detectors.psm1` uses a single large `Get-OneImFileFindings` function (a line-by-line imperative scan) whose growing size is the primary maintainability risk. The cascade script uses BFS for graph expansion and iterative DFS for cycle detection, but stops there — the graph is richer than the code currently exploits.

---

## 1. Priority Ranking of Improvements

### Priority 1 — Test Coverage for Lanes 2 and 3 (highest leverage)

The 32 Pester tests cover only Lane 1. Lanes 2 and 3 have zero automated coverage, yet they process the most structurally complex data (schema JSON with 997 tables and 2108 FK edges, and multi-run timing samples). Any refactor or extension to the graph algorithms or benchmark metrics is risky without a regression harness.

**What to do first:**

- Create `tests/OneimAudit.Schema.Tests.ps1`: unit tests for `export_oneim_schema_snapshot.ps1`'s index-building logic (`column_to_fk_target`, `parent_to_children`). Use a small synthetic JSON fixture - 10 tables, 20 columns, 8 FK edges - not a live connection. Test: correct key format, bidirectional edge presence, handling of tables with no FK edges, handling of duplicate FK edges.

- Create `tests/OneimAudit.Graph.Tests.ps1`: unit tests for the graph functions currently embedded inline in `export_template_cascade_report.ps1`. These include `Get-TemplateEdges`, `Get-Or-AddNode`, `Add-Edge`, `Find-Cycles`, and the tree renderer. Before these can be tested, the functions need to be extracted into a module (see Priority 2).

- Create `tests/OneimAudit.Benchmark.Tests.ps1`: unit tests for `Get-SampleStats` (the only pure-function in the benchmark script). Current gaps: `p95` boundary conditions when `$count` is exactly 1, 2, 19, 20; `stddev_ms` for uniform input (should be 0); behavior when all `memory_delta_bytes` are negative (GC compaction); `avg_cpu_ms` rounding.

**PS5.1 vs PS7 compatibility note:** The tests currently target PS5.1 (`run_auditor_tests.ps1` invokes Pester in the default shell, which is PS5.1 on this Windows Server host). The live scripts (`export_oneim_schema_snapshot.ps1`, `invoke_oneim_benchmark.ps1`, `export_template_cascade_report.ps1`) require PS7 because they use `ConvertFrom-Json` in ways that produce `PSCustomObject` property access that PS5.1 handles slightly differently. The resolution is a split-test strategy:
- Tag Lane 1 tests `#Requires -Version 5.1` - keep running on PS5.1.
- Tag Lane 2 and 3 tests `#Requires -Version 7` - run in a separate PS7 invocation inside `run_auditor_tests.ps1` using `pwsh.exe -File`.

### Priority 2 — Extract Graph Logic into a Module

`export_template_cascade_report.ps1` is a 615-line script where graph construction, cycle detection, and HTML rendering are all inlined with no separating abstractions. This is the single biggest maintainability risk because every graph extension (SCCs, centrality, topological sort) must be bolt-on additions to the same file.

**What to do:**

Create `scripts/modules/OneimAudit.Graph.psm1` that exports:

- `New-OneImAuditGraph` - initializes the node + adjacency list hash tables as a single graph object passed by reference.
- `Add-OneImAuditGraphEdge` - wraps the current `Add-Edge` function.
- `Get-OneImAuditTemplateEdges` - the regex edge parser (currently `Get-TemplateEdges`), unchanged.
- `Invoke-OneImAuditGraphBFS` - the BFS expansion loop.
- `Find-OneImAuditGraphCycles` - the DFS cycle detector, returning a structured cycle list.
- `Get-OneImAuditGraphStats` - returns `node_count`, `edge_count`, `cycle_count`, `max_depth`, `avg_out_degree`.

`export_template_cascade_report.ps1` becomes a thin orchestration script that calls these functions and handles HTML rendering, which is already self-contained. The Pester tests for Lane 3 then test the module directly, not the script.

### Priority 3 — Error Handling Robustness

Current gaps observed:

1. `invoke_oneim_benchmark.ps1`: the catch block for templates adds a minimal error object but does not record which backend was in use at the time of failure. On partial failures (5 of 10 targets error), the report `backend` field in `report_metadata` is correct but individual error entries lack it, which makes post-processing harder.

2. `export_template_cascade_report.ps1`: the `Find-Cycles` function is recursive and uses PowerShell call stacks. With 997 tables and a deep BFS graph, a degenerate path can reach hundreds of levels of recursion. PowerShell's default stack depth is ~1000 frames; a pathological FK graph hitting `MaxDepth = 20` is safe, but the actual DFS over `$nodes.Keys` is unbounded by `MaxDepth` because `MaxDepth` only limits the HTML renderer, not the DFS. Add a `$maxDfsDepth` guard inside `Find-Cycles`.

3. `OneimAudit.LiveSession.psm1`: the `Get-OneImAuditProjectConfig` function reads a password from `DM_PASS` if absent from the XML. No warning is emitted if neither source provides a password, leading to a silent null being passed to the connection string. Add an explicit warning.

4. `Get-OneImAuditRuleCatalog` in `OneimAudit.RuleCatalog.psm1`: the required-field validation loop throws on the first missing field but does not identify *which rule entry* (by index or partial id) caused the failure. Add the rule index to the error message.

### Priority 4 — Rule Catalog Growth Strategy

Currently 22 rules, all in a single JSON file with two engine types (`coded` and `declarative`). Growth risks:

- The `Get-OneImFileFindings` function already has ~280 lines of `if` chains. At 40 rules this becomes unmanageable.
- The declarative pass (`Invoke-OneImDeclarativeRulePass`, referenced at line 629 of Detectors.psm1) is called after coded checks - it is a second pass with its own loop, meaning all lines are scanned twice for files with declarative rules active.

**Growth strategy:**

- Introduce a `detector_group` field in the JSON. Group rules into `header`, `security`, `reliability`, `performance`, `oneim-specific`, `concurrency` (new, see section 4). Load each group into a separate hashtable and dispatch per-file based on which groups are active.
- Convert the `Get-OneImFileFindings` `if` chain into a dispatch table: a hashtable keyed by rule ID mapping to a scriptblock. Each scriptblock receives `($lines, $index, $trimmed, $loopDepthMap, $findings, $seen)`. This makes adding a rule a matter of adding a new entry rather than editing a growing function body.
- Add a `draft_rules` array alongside `rules` in `audit-rules.json` for rules under development that load but never gate CI - they emit findings with `confidence_label = "low"` regardless of their score.

### Priority 5 — Caching and Idempotency

`export_oneim_schema_snapshot.ps1` already implements a cache check with `-Force` bypass. `invoke_oneim_benchmark.ps1` and `export_template_cascade_report.ps1` do not. The benchmark script should accept a `-SkipIfExists` switch that exits 0 if a `benchmark-report.json` already exists under the same timestamp-named output directory. More importantly, the cascade script's BFS `$visited` hashtable prevents re-queuing but does not prevent the DFS cycle detector from re-traversing already-colored nodes across multiple root calls - the `$dfsColor` hashtable is scoped to the outer script rather than per-root-call, which is correct, but worth making explicit with a comment.



## 2. Graph Theory Extensions

The cascade script produces nodes (templates as `Table.Column`) and a directed adjacency list (`$adjList`). With 997 tables and 2108 FK edges loaded into the index, the full graph is substantial. Here are the specific algorithms to add, ordered by implementation difficulty in PowerShell:

### 2a. Dependency Depth Histogram (Easy, immediate value)

**What it reveals:** How deep the template evaluation chain is. Templates at depth 10+ are "evaluation hotspots" where a single field change fans out through many layers.

**Implementation sketch in PowerShell:**
After BFS completes, `$visited` already contains all reachable nodes. Add a `$depthMap` hashtable filled during BFS by passing `depth + 1` when enqueuing children. The histogram is `$depthMap.Values | Group-Object | Sort-Object Name`. Write it as a `depth_histogram` array in the cascade JSON output.

This requires zero new dependencies and adds ~20 lines to the existing BFS loop.

### 2b. Topological Sort for Safe Evaluation Order (Easy, directly actionable)

**What it reveals:** The order in which templates must be evaluated so that every template's dependencies are resolved before it runs. Cycle nodes cannot be sorted (they are already flagged); non-cycle nodes can be safely ordered.

**Implementation:** Kahn's algorithm using the existing `$adjList` and `$reverseAdj`. Compute in-degrees from `$reverseAdj`, initialize a queue of zero-in-degree nodes, dequeue and emit while decrementing neighbors' in-degrees. Any node that never reaches zero in-degree belongs to a cycle (cross-check with existing `$cycleEdges`).

Pure PowerShell, ~40 lines. Output: a `topological_order` array in the JSON, plus a new HTML section "Safe evaluation order" above the node table.

### 2c. Betweenness Centrality - Hub Templates (Medium, high value)

**What it reveals:** Templates that sit on the most paths between other templates. High-betweenness nodes are structural hubs: if they evaluate slowly or throw, they block many downstream paths. This is more precise than fan-in count because it measures transitivity.

**Algorithm:** Brandes' algorithm. For each source node `s`, run BFS to compute shortest path counts (`sigma[v]`) and predecessor lists. Back-propagate dependency weights (`delta[v]`) from leaves to root. Accumulate `delta[s]` into centrality score.

**Feasibility in PowerShell:** Feasible but slow for large graphs. With 997 table nodes the inner BFS is O(V + E) per source, giving O(V(V + E)) overall. For a typical cascade subgraph of 50-200 nodes this completes in under 1 second. For a full schema traversal with all templates, add a `-TopCentralityNodes 20` parameter to limit output. The algorithm does not require any .NET interop - pure hash tables and queues.

**Output:** Add `centrality_score` to each node object in the JSON, sort the node table by centrality descending in HTML, highlight the top-5 central nodes with a distinct CSS badge.

### 2d. Strongly Connected Components - SCCs (Medium, critical for deadlock analysis)

**What it reveals:** The current cycle detection finds *individual back edges*. SCCs find *all groups of mutually reachable nodes*. An SCC with more than one node is a group of templates that can all reach each other - a full mutual dependency cluster. This is the prerequisite for deadlock analysis (section 4).

**Algorithm:** Kosaraju's two-pass DFS. Pass 1: DFS on the forward graph (`$adjList`), push nodes to a stack in finish order. Pass 2: DFS on the reverse graph (`$reverseAdj`) in stack order, each DFS tree is one SCC.

**Feasibility in PowerShell:** Straightforward. The reverse graph is already built (`$reverseAdj`). Two recursive DFS passes. For graphs > 500 nodes, convert DFS to iterative using an explicit stack (a `System.Collections.Generic.Stack[string]`) to avoid PowerShell call stack overflow - this is important given the DFS depth risk noted in Priority 3.

**Output:** Add `scc_id` and `scc_size` to each node, emit a `strongly_connected_components` array in JSON (each SCC as a list of member keys + size), add an "SCC clusters" section to the HTML showing SCCs with size > 1 in amber.

### 2e. Dominator Tree (Hard, highest architectural value)

**What it reveals:** For each template node `v`, the dominator `d` is the unique node that lies on every path from the root to `v`. If `d` is removed or fails, `v` cannot be reached. Dominator trees expose which templates are "single points of failure" for entire subtrees.

**Algorithm:** Lengauer-Tarjan dominators using DFS tree, semi-dominators, and link-cut compression. This is the most complex algorithm in the set.

**Feasibility in PowerShell:** Implementable but the compressed semi-dominator path requires careful index management. A simpler iterative dataflow approach (Cooper-Harvey-Kennedy) converges for most practical graphs in a few passes and is ~100 lines of PowerShell. It runs in O(V^2) which is acceptable for cascade subgraphs up to ~500 nodes. For the full schema, limit to the subgraph reachable from the root template.

**Output:** Add `immediate_dominator` to each node, render a collapsible "Dominator tree" panel in HTML.

### 2f. Graph Diff Between Schema Versions (Medium, operational value)

**What it reveals:** When a new schema snapshot is taken after a OneIM patch or customization deployment, which FK edges were added, removed, or had their parent/child table changed. This catches when a customization inadvertently re-routes a FK that other templates depend on.

**Implementation:** A new script `scripts/compare_schema_snapshots.ps1` that accepts `-BaselinePath` and `-CurrentPath`. Load both `fk_relations` arrays, build sets of `"child_table.child_column -> parent_table.parent_column"` strings, compute set difference in both directions. Also diff `tables` (new/removed) and `columns` (new/removed/template flag changed).

**Pure PowerShell, no new dependencies.** The output is a `schema-diff.json` and optionally an HTML diff report. This is independent of the cascade script but uses the same schema snapshot format.

### 2g. Community Detection / Bipartite Analysis (Lower priority)

Community detection (e.g., label propagation) is feasible in PowerShell but produces noisy results on FK graphs, which are not natural community graphs - FK edges are directional and often star-shaped around hub tables. Defer until SCC + centrality data is available to validate whether community clusters add information beyond what SCCs already show.

Bipartite analysis (tables as one partition, columns as the other, FK edges as the bipartite edge set) is already implicit in the schema snapshot structure. The value proposition in this specific codebase is limited because every edge already has table+column on both ends.

---

## 3. Additional Benchmark Metrics

Evaluated against two implementation constraints: (a) must work in PowerShell without requiring SQL DMV access during every benchmark run, and (b) must not add significant overhead that inflates the measurement itself.

### Tier A - Implementable Now (Pure PowerShell, no new dependencies)

**Coefficient of Variation (CV = stddev / avg):** The most immediately useful missing metric. A template with `avg_ms = 5, stddev_ms = 4` is far more operationally risky than one with `avg_ms = 50, stddev_ms = 1`. CV quantifies this. Add `cv_pct = Round((stddev_ms / avg_ms) * 100, 1)` to `Get-SampleStats`. Emit a `stability = "stable" | "variable" | "unstable"` label using thresholds: CV < 10% = stable, 10-30% = variable, > 30% = unstable.

**Percentile spread (p50, p75, p99):** The existing code computes only p95. Extending `Get-SampleStats` to compute p50, p75, p99 is trivial - re-use the sorted array already computed for p95. The p99 is particularly useful for detecting rare spikes in long-running benchmark sessions.

**Warmup effect ratio:** `warmup_effect_ratio = first_measured_run_ms / avg_ms`. Currently `raw_samples` is written to the JSON but the first-run vs. steady-state ratio is never surfaced. Capture `$samples[0].elapsed_ms / $stats.avg_ms` after `Invoke-BuiltinSampler` returns and emit it. Values > 3.0 indicate the warmup count is insufficient.

**GC collection count delta:** `[System.GC]::CollectionCount(0)` through `CollectionCount(2)` return Gen0/1/2 collection counts since process start. Sample before and after each measured run in `Invoke-BuiltinSampler` and emit `gc_gen0_delta`, `gc_gen1_delta`, `gc_gen2_delta`. A benchmark target with `gc_gen2_delta > 0` per run is promoting objects to the large object heap - a strong indicator of memory pressure.

**Thread count delta:** `[System.Diagnostics.Process]::GetCurrentProcess().Threads.Count` sampled before/after each run. A growing thread count across runs indicates thread pool exhaustion or leaked thread handles in the invoked code.

### Tier B - SQL DMV Metrics (Requires `AccessMode = Direct` and SQL login with VIEW SERVER STATE)

These are all implementable in PowerShell via the `System.Data.SqlClient.SqlConnection` that `OneimAudit.LiveSession.psm1` already wraps. The benchmark script would need a `-CollectSqlMetrics` switch that opens a second ADO.NET connection and runs DMV queries before and after the benchmark block.

**Logical reads via `SET STATISTICS IO ON`:** Not a DMV query - this is a session-level setting. In Direct mode, wrap the benchmark query in a `SqlCommand` with `SET STATISTICS IO ON` before execution. Parse the informational message returned in `SqlConnection.InfoMessage` for `logical reads` and `physical reads` per table. This is the most actionable SQL metric because it directly measures query plan efficiency rather than wall-clock time.

**Lock wait time (`sys.dm_os_wait_stats`):** Sample `SELECT wait_type, waiting_tasks_count, wait_time_ms FROM sys.dm_os_wait_stats WHERE wait_type LIKE 'LCK%'` before and after the benchmark run. Delta `waiting_tasks_count` and `wait_time_ms` for `LCK_M_X` (exclusive lock waits) and `LCK_M_S` (shared lock waits) indicates lock contention caused by the template evaluation path. This is the single most important metric for deadlock risk correlation.

**Connection pool saturation (`sys.dm_exec_connections`):** `SELECT COUNT(*) FROM sys.dm_exec_connections WHERE client_net_address = '...'` gives active connection count. Useful to confirm the benchmark is not opening extra connections on each run iteration.

**Query execution plan cost (`sys.dm_exec_query_stats`):** After each run, query `sys.dm_exec_query_stats` filtered by `last_execution_time`. The `total_worker_time` / `execution_count` ratio gives average CPU cost in microseconds from the SQL engine's perspective - independent of PowerShell timing overhead. This requires `VIEW SERVER STATE` permission.

**Regression detection against baseline JSON:** Add a `-BaselineBenchmarkPath` parameter. After computing stats, load the baseline JSON, find the matching `name + surface` entry, and compute `regression_pct = ((avg_ms - baseline_avg_ms) / baseline_avg_ms) * 100`. Emit `regressed = true` when regression exceeds a configurable threshold (default: 20%). Write a `regressions` array in the report summary.

### Tier C - Not Feasible in PowerShell Without Native Interop

**SQL cursor detection at runtime:** Cursor usage can be detected statically (section 4) but measuring live cursor overhead requires SQL Profiler or Extended Events - not accessible via simple DMV queries in PowerShell.

**Row-level lock escalation:** `sys.dm_tran_locks` can show active locks during a transaction but sampling it accurately within a benchmark iteration is racy because it requires a concurrent monitoring connection.

---

## 4. Deadlock and Concurrency Risk Detection

This is the most novel dimension. The key insight is that the cascade graph already encodes enough structure to derive a significant portion of classical deadlock analysis without any runtime instrumentation.

### What is Feasible via Static Analysis

**Lock ordering analysis from FK traversal order:**

In `Get-TemplateEdges`, the order in which `FK(Table.Column)` references appear in a template expression is the order in which that template will attempt to read from those tables during evaluation. If template A's expression contains `FK(Person.UID_Org)` before `FK(Org.UID_Department)`, it reads Person then Org. If template B contains `FK(Org.UID_Department)` before `FK(Person.UID_Org)`, it reads Org then Person. Under concurrent evaluation with row-level locking, this is a textbook lock inversion.

Implementation: after graph construction, build a `lock_access_sequences` hashtable: key = template key, value = ordered list of `FK()` targets extracted from the expression text (preserving match order from `[regex]::Matches`). For every pair of templates (A, B) that share two or more FK targets in opposite order, emit a `CNC600` finding: "Potential lock-order inversion between template A and template B." This is O(T^2 * F) where T = templates with FK refs, F = FK refs per template - tractable for hundreds of templates.

**Templates that write (mutation pattern detection):**

`PutValue` and `ExecuteTemplate` are already detected by rules `OIM500` and `REL220`. Extend the graph model: mark each node as `is_writer = true` if its expression text contains `PutValue` or `ExecuteTemplate`. A writer node that appears in a cycle (already detected by `$cycleEdges`) is a "write-cycle participant" - it can modify data that indirectly causes its own re-evaluation, a potential infinite-loop-under-write scenario. Emit a `CNC610` finding for writer nodes in cycles.

**Circular FK dependencies under concurrent evaluation:**

SCCs with size > 1 (from algorithm 2d) that contain at least one writer node are the highest-risk combination. Two templates in an SCC that both write to their respective tables form a closed write-read-write cycle that under concurrent evaluation maps exactly to the two-transaction deadlock pattern: T1 holds lock on Table A, waits for Table B; T2 holds lock on Table B, waits for Table A.

Add a `concurrency_risk` field to each SCC entry: `"write-cycle"` if it contains a writer + cycle, `"read-cycle"` if all nodes are read-only, `"none"` if the SCC has size 1.

**SQL anti-patterns in script methods:**

Extend the `Get-OneImFileFindings` detector to a new `OneimAudit.ConcurrencyDetectors.psm1` (separate module to keep the existing detector clean) with the following new rules:

- `CNC600` - Lock-order inversion candidate (described above, requires graph data, cannot be coded inline)
- `CNC601` - `NOLOCK` / `WITH(NOLOCK)` hint in string-built SQL: paradoxically, NOLOCK hints in custom scripts indicate the developer was aware of locking pressure but worked around it instead of fixing the root cause. Flag for review.
- `CNC602` - `SqlTransaction` / `BeginTransaction` without a paired `Commit` or `Rollback` in the same lexical scope (detected by scanning forward from `BeginTransaction` to end of method without finding `Commit`/`Rollback`/`Using`).
- `CNC603` - Nested transaction pattern: `BeginTransaction` when a `SqlTransaction` variable is already in scope (detected by tracking transaction variable declarations).
- `CNC604` - Unbounded `Do While` / `While True` / `Do Until False` loops without an obvious exit condition referencing a counter or collection length. These can hold implicit locks open indefinitely.
- `CNC605` - `Thread.Sleep` inside script methods: indicates polling patterns that hold resources open during the wait.

**Template evaluation order violations:**

If template A's expression contains `$ColumnB$` (a same-table substitution to ColumnB) and template B's expression contains `$ColumnC$` (another same-table substitution to ColumnC), and ColumnC is the column A is defined on - meaning B reads the value that A computes - then if both evaluate in the same save event, evaluation order matters. This is detectable from the substitution edges in `Get-TemplateEdges`. The topological sort (section 2b) surfaces the correct order; a violation occurs when a template is triggered to evaluate before its predecessor in topological order has finished.

Emit a `CNC606` finding for template pairs where the substitution dependency graph has a topological ordering but the OneIM process step does not respect it (detectable if the process step is available in the template catalog).

### What Requires Runtime Rather Than Static Analysis

**Actual SQL lock acquisition sequence:** Which statements hold which locks at which times cannot be determined from expression text alone when `PutValue` calls are conditional. Static analysis can only flag *possible* inversion; runtime DMV sampling (Tier B in section 3) confirms whether the inversion actually materializes.

**Adaptive lock escalation:** SQL Server escalates row locks to table locks when a transaction holds > ~5000 row locks. This threshold is runtime-dependent and not visible in the VB.NET code.

**Connection pool deadlocks:** When a template method exhausts all connection pool entries and blocks waiting for one, a deadlock can occur at the ADO.NET layer without any SQL lock contention. Detecting this statically requires knowing the pool size configuration, which is in `projectConfig.xml` but not available to the graph analysis.

**Recommendation:** Frame the `CNC600-CNC606` rules as "concurrency risk" findings with `severity = "medium"`, `confidence = 65-70` - actionable as a design review trigger, not as a deterministic deadlock proof. Pair each finding's `test_ideas` with the SQL DMV metric queries from Tier B, so the developer knows exactly which runtime data to collect to confirm or rule out the finding.

---

## 5. Concrete Next Steps

Listed in implementation sequence, with file paths:

**Step 1: Extract graph logic into a module.**
New file: `scripts/modules/OneimAudit.Graph.psm1`
This unblocks Steps 2, 3, and the graph algorithm extensions. The `export_template_cascade_report.ps1` script becomes a thin consumer of the new module - no behavior change, but the internal functions become independently testable.

**Step 2: Write the Lane 2 and Lane 3 Pester tests.**
New file: `tests/OneimAudit.Graph.Tests.ps1` - tests for the extracted graph module using synthetic fixtures.
New file: `tests/OneimAudit.Benchmark.Tests.ps1` - tests for `Get-SampleStats` in isolation.
Modify: `scripts/run_auditor_tests.ps1` - add a `pwsh.exe -File` invocation for the PS7 test files.

**Step 3: Add CV, p50/p75/p99, warmup ratio, GC delta to the benchmark.**
Modify: `scripts/invoke_oneim_benchmark.ps1` in `Get-SampleStats` and `Invoke-BuiltinSampler`.
These are additive-only changes - existing JSON consumers continue to work because new fields are appended.

**Step 4: Implement topological sort and depth histogram in the graph module.**
Modify: `scripts/modules/OneimAudit.Graph.psm1` (after Step 1).
Modify: `scripts/export_template_cascade_report.ps1` - consume the new functions, add a "Safe evaluation order" section to the HTML.

**Step 5: Implement SCC detection.**
Modify: `scripts/modules/OneimAudit.Graph.psm1` - add `Find-OneImAuditSCCs` using iterative Kosaraju.
Modify: `scripts/export_template_cascade_report.ps1` - add `strongly_connected_components` to JSON output and an SCC panel to HTML.

**Step 6: Add regression detection to the benchmark.**
Modify: `scripts/invoke_oneim_benchmark.ps1` - add `-BaselineBenchmarkPath` parameter, compute `regression_pct`, emit a `regressions` summary array.

**Step 7: Implement SQL DMV metrics.**
Modify: `scripts/modules/OneimAudit.LiveSession.psm1` - add `Invoke-OneImAuditSqlDmvSample` that runs the LCK wait stats and logical reads queries.
Modify: `scripts/invoke_oneim_benchmark.ps1` - add `-CollectSqlMetrics` switch that calls the new function before and after each measured block.

**Step 8: Add lock-order inversion detection (CNC600) and the writer-in-cycle rule (CNC610).**
New file: `scripts/modules/OneimAudit.ConcurrencyDetectors.psm1`
New entries in: `assets/audit-rules.json` under a new `concurrency` category.
Modify: `scripts/export_template_cascade_report.ps1` - consume concurrency findings from the graph pass and merge them into the cascade JSON output.

**Step 9: Add schema diff script.**
New file: `scripts/compare_schema_snapshots.ps1` - standalone, no module dependencies.

**Step 10: Refactor `Get-OneImFileFindings` into a dispatch table.**
Modify: `scripts/modules/OneimAudit.Detectors.psm1` - this is the highest-risk refactor (all 32 tests must stay green) and should be done last, after the test suite has been extended to cover edge cases in each rule.

---

## Critical Files for Implementation

| File | Role |
|---|---|
| `scripts/modules/OneimAudit.Detectors.psm1` | Core static analysis engine; extend with dispatch table and new CNC detectors |
| `scripts/export_template_cascade_report.ps1` | Source of all graph logic to extract into `OneimAudit.Graph.psm1` |
| `scripts/invoke_oneim_benchmark.ps1` | Extend `Get-SampleStats` and `Invoke-BuiltinSampler` with Tier A metrics |
| `assets/audit-rules.json` | Add `concurrency` category entries (CNC600-CNC606) and `detector_group` field |
| `tests/Oneim.VbNet.Auditor.Tests.ps1` | Fixture pattern to replicate in new Lane 2/3 test files |
| `scripts/modules/OneimAudit.Graph.psm1` | NEW - extracted graph module |
| `scripts/modules/OneimAudit.ConcurrencyDetectors.psm1` | NEW - CNC600-CNC610 rules |
| `tests/OneimAudit.Graph.Tests.ps1` | NEW - graph module unit tests |
| `tests/OneimAudit.Benchmark.Tests.ps1` | NEW - benchmark stats unit tests |
| `scripts/compare_schema_snapshots.ps1` | NEW - schema diff script |
