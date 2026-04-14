---
name: oneim-vbnet-auditor
description: Audit One Identity Manager VB.NET code for correctness, security, and performance using an approved evidence hierarchy. Use when Codex needs to review OneIM scripts, templates, formatting logic, table code, methods, or process-related VB.NET; apply version-aware source-backed checks for SQL, web requests, file I/O, XML, deserialization, crypto, reliability, and performance; or explain which official sources justify a finding. Do not use for generic VB.NET desktop apps, unrelated .NET web apps, or non-OneIM repositories unless the user explicitly asks for a OneIM-oriented audit.
---

# OneIM VB.NET Auditor

## Overview

This skill is for One Identity Manager VB.NET audits, not generic VB.NET reviews.

Default active version: `9.3.1`

Audit priorities are fixed:

1. correctness
2. security
3. performance

## Default Workflow

1. Confirm the target is a OneIM surface such as scripts, templates, formatting rules, table scripts, methods, or process-related code.
2. Assume OneIM `9.3.1` unless the user explicitly provides another version.
3. Require `-ReferenceRepoPath` for audit runs. Do not let the auditor run without an explicit reference repo path.
4. Validate that `-ReferenceRepoPath` resolves to one of these OneIM `9.3.1` layouts:
   - `<repo-root>\reference-library\oneim-9.3.1\...`
   - `<reference-library-root>\oneim-9.3.1\...`
   - `<version-root>\ootb\...`
5. Require all of these subfolders under the version root: `ootb`, `promoted-custom`, `candidate-custom`, `rejected`, and `intake-manifests`.
6. Require `ootb` to contain at least one VB.NET reference file before treating the structure as valid.
7. If the user supplies a raw System Debugger export instead of a curated reference library, inform them that the structure is not valid yet and ask whether they want it restructured so the auditor can run successfully. Use `scripts/register_reference_export.ps1` when they confirm or when an explicit automation switch such as `-AutoRestructureIfNeeded` is present.
8. Use the approved source policy before forming strong findings.
9. Prefer exact local code evidence with file and line references.
10. Report only high-confidence findings as strong conclusions.
11. Downgrade uncertain or incomplete evidence to advisory or manual-review status.
12. Treat `assets/audit-rules.json` as the reviewable source of truth for rule metadata. If the rule set needs to be reviewed, exported, disabled, re-severitized, or re-scored, change that catalog first and keep the detector modules aligned with it.
13. Suppressions are intentionally disabled during the current rule-tuning phase. Keep `assets/suppressions.example.json` only as dormant reference material for a later phase.
14. Use `max_examples_per_file` in `assets/audit-rules.json` to cap duplicate-heavy examples for a single rule in a single file without disabling that rule.

## Approved Evidence Policy

Use only these approved authorities for evidence that can affect findings:

1. Version-matched local One Identity API Server CHM pages indexed in `assets/apiserver-doc-index.json`
2. One Identity official docs on `support.oneidentity.com`
3. Microsoft Learn on `learn.microsoft.com`
4. OWASP cheat sheets and OWASP community guidance on `cheatsheetseries.owasp.org` and `owasp.org`

Evidence priority is fixed:

1. Local API Server CHM pages for version-matched API Server types, properties, and request-pipeline helpers
2. One Identity for broader OneIM behavior and version context
3. Microsoft Learn for VB.NET and .NET semantics, analyzers, reliability, and performance
4. OWASP for vulnerability classes where vendor guidance is not specific enough

Blocked sources:

- blogs
- Stack Overflow
- GitHub issues
- forums
- AI summaries
- vendor marketing pages

Never let a blocked source create or upgrade a gating finding.

Regenerate `assets/apiserver-doc-index.json` with `scripts/generate_apiserver_doc_index.ps1` whenever the skill moves to another machine or the installed One Identity API Server docs change.

## Confidence Rules

High-confidence findings require all of the following:

- direct code evidence
- a matching approved source
- a clear sink, failure mode, or correctness break
- version-matched OneIM context when OneIM behavior materially affects the conclusion

Medium-confidence findings are allowed when the code evidence is direct but OneIM runtime context is incomplete.

Low-confidence findings stay advisory when they are mostly heuristic, cross-version, or only weakly tied to a sink.

If a code pattern has no approved source mapping yet, label it `needs-manual-review` rather than inventing a strong rule.

## What To Check

Classify findings under:

- correctness
- security
- performance

Look explicitly for:

- `Nothing` and null-handling defects
- implicit conversion problems
- dynamic SQL or unsafe query building
- unsafe outbound web requests and certificate handling
- risky file reads and writes
- XML and deserialization hazards
- process execution or shell launch patterns
- exception swallowing
- hidden side effects in read-mostly scripts
- repeated database or object access in loops
- expensive string-building and repeated enumeration

## Source-Mapped Rule Families

- SQL and DB access: `CA2100` plus OWASP SQL injection guidance
- Web requests: `HttpClient` guidance, `SYSLIB0014`, `CA5359`, `CA5364`, and OWASP SSRF guidance
- File reading and writing: `CA3003`, OWASP Path Traversal, and OWASP File Upload guidance
- XML and deserialization: `CA3075`, OWASP XXE, `CA2300`, and `CA2310`
- Process execution: OWASP OS Command Injection guidance
- Reliability with security impact: `CA1031`, `CA2000`, `Option Strict`, `Option Explicit`, and VB string comparison guidance
- Performance: `CA1827`, `CA1851`, `StringBuilder` guidance, and OneIM System Debugger query logging context

## Reporting

When you produce an audit, include:

- executive summary
- findings
- severity
- triggering scenario
- remediation
- test ideas
- unresolved questions
- confidence notes

## Rule Authoring Workflow

Use this workflow to add a new declarative rule without touching detector code.

### Add a rule

1. Run `scripts/new_audit_rule.ps1` with the required parameters. This appends a `draft` declarative rule to `assets/audit-rules.json`.
   ```
   scripts/new_audit_rule.ps1 `
     -Id SEC180 -Title "Forbidden API call" `
     -Category security -Severity high `
     -Pattern "(?i)ForbiddenApi\s*\(" `
     -Why "ForbiddenApi leaks credentials" `
     -TriggeringScenario "Any call to ForbiddenApi" `
     -Remediation "Replace with SafeApi" `
     -TestIdeas "File that calls ForbiddenApi"
   ```
2. Run `scripts/validate_audit_rules.ps1` to confirm the rule is structurally valid (unique ID, valid enums, regex compiles, required declarative fields present).
3. Change `state` from `draft` to `active` in `assets/audit-rules.json` when the rule is ready.
4. Run `scripts/run_auditor_tests.ps1` to verify no regressions.

### Declarative match kinds

| match_kind | Fires when |
|---|---|
| `line-pattern` | Pattern matches on any line — one finding per matching line |
| `header-required` | Pattern absent from the first 40 lines — finding at line 1 |
| `line-absence` | No line in the file matches pattern — finding at line 1 |

### Path scoping

Add `include_paths` or `exclude_paths` glob arrays to restrict the rule to specific relative paths:
```json
"include_paths": ["Scripts\\*", "Methods\\*"],
"exclude_paths": ["Scripts\\Generated\\*"]
```
Uses PowerShell `WildcardPattern` (case-insensitive) on the relative file path from the audit root.

### Export the active rule set for review

```
scripts/export_audit_rules.ps1 -Format Bundle -RuleState Active
```

Writes `audit-rules.md`, `audit-rules.json`, and `audit-rules.csv` to `output\oneim-audit-rules-export\<timestamp>\`.

---

## Live Schema Snapshot (Lane 2)

Capture OneIM database structure for FK-aware analysis and cascade resolution:

```
scripts/export_oneim_schema_snapshot.ps1
  [-TestAssistRoot <path>] [-ProjectConfigPath <path>]
  [-AccessMode Auto|Session|Direct]
  [-OutputDir <path>] [-Force]
```

Output: `output\oneim-schema\<env-fingerprint>\schema-snapshot.json`

Cache policy: existing snapshot is reused unless `-Force` is supplied.

---

## Benchmarking (Lane 3)

Measure OneIM templates, script methods, and/or processes:

```
scripts/invoke_oneim_benchmark.ps1
  -TemplateNames Person.FirstName, Person.LastName
  [-ScriptMethodNames <name>] [-ProcessNames <name>]
  [-WarmupCount 1] [-MeasuredRunCount 10]
  [-ThresholdsFile thresholds.json]
  [-SchemaSnapshotPath <path>]
```

Output: `output\oneim-benchmark\<timestamp>\benchmark-report.json`

Metrics per target: avg_ms, stddev_ms, min_ms, max_ms, p95_ms, raw samples.

### Cascade report

Build an HTML dependency graph for a single template:

```
scripts/export_template_cascade_report.ps1
  -TemplateName Person.FirstName
  [-SchemaSnapshotPath <path>]
  [-TemplateCatalogPath <path>]
  [-BenchmarkReportPath <path>]
  [-ThresholdsFile <path>]
  [-OutputDir <path>]
```

Output: `output\oneim-cascade\<timestamp>\cascade-<name>.html` plus a companion `.json`.

HTML report features: predecessor/successor collapsible trees, bottleneck node highlighted in red, cycle nodes in amber, threshold overruns in red.

### Ingest benchmark evidence into an audit run

```
scripts/invoke_oneim_audit.ps1
  -TargetPath <path> -ReferenceRepoPath <path>
  -BenchmarkReportPath output\oneim-benchmark\...\benchmark-report.json
  -SchemaSnapshotPath  output\oneim-schema\...\schema-snapshot.json
  -ThresholdsFile      thresholds.json
```

When `-BenchmarkReportPath` and `-ThresholdsFile` are both supplied, targets that exceed their threshold produce additional `PERF-BENCH-THRESHOLD` performance findings in the audit report.

---

## Resources

- `references/source-policy.md`: human-readable approved evidence policy
- `assets/approved-sources.json`: machine-readable source catalog and rule mapping
- `assets/audit-rules.json`: reviewable rule catalog that defines the active audit rules, their severities, confidence, detector family, and source mappings
- `assets/suppressions.example.json`: dormant example file kept only as reference while suppressions are disabled in the current phase
- `scripts/extract_custom_reference_files.ps1`: extracts custom-marked VB snippets from a raw System Debugger export
- `scripts/materialize_sanitized_ootb_export.ps1`: creates a heuristic OOTB baseline by removing extracted `CCC` custom ranges from a mixed export
- `scripts/register_reference_export.ps1`: registers a raw export as `mixed-export` and seeds `candidate-custom` from extracted custom snippets
- `scripts/invoke_oneim_audit.ps1`: main audit runner; requires `-ReferenceRepoPath`, accepts one or more explicit `-TargetPath` file or folder selections, including a single shell-safe `|` delimited target list for `powershell -File` automation, validates reference structure, and offers or performs restructure when a raw export is supplied instead of a managed library
- `scripts/export_audit_rules.ps1`: exports the active audit rule set as Markdown, JSON, CSV, or a Bundle (all three together) for CTO or auditor review; accepts `-RuleState [All|Active|Draft|Disabled]` and `-OutputDir`
- `scripts/validate_audit_rules.ps1`: validates `assets/audit-rules.json` for structural correctness — unique IDs, valid enums, required fields per engine type, regex compilation, and optional source-ID resolution
- `scripts/new_audit_rule.ps1`: scaffolds a new `draft` declarative rule into `assets/audit-rules.json`; validates the regex before writing and rejects duplicate IDs
- `scripts/export_oneim_schema_snapshot.ps1`: connects to the live OneIM database and exports table, column, and FK-relation metadata as `schema-snapshot.json`; caches the snapshot and reuses it on subsequent runs unless `-Force` is supplied
- `scripts/invoke_oneim_benchmark.ps1`: benchmarks OneIM templates, script methods, and/or processes; uses a built-in stopwatch + GC sampler (or BenchmarkDotNet if available); writes `benchmark-report.json` with avg/stddev/min/max/p95 per target
- `scripts/export_template_cascade_report.ps1`: builds a cascade dependency graph for a root template, detects cycles via DFS, and writes a self-contained HTML report with predecessor/successor trees, bottleneck highlighting, and threshold overrun indicators
- `scripts/export_candidate_review_plan.ps1`: generates a snippet-by-snippet JSON and Markdown review plan for a candidate entry without moving it
- `scripts/split_candidate_reference.ps1`: splits selected review-plan bands, such as `strong-custom`, into a new focused candidate entry and leaves the weaker residue behind
- `scripts/review_custom_reference.ps1`: updates candidate confidence scoring, reviewer notes, and promotion readiness without moving the entry
- `scripts/promote_custom_reference.ps1`: promotes a reviewed candidate entry into `promoted-custom` when its confidence meets the promotion threshold, or when an explicit override is used
- `scripts/reject_custom_reference.ps1`: moves a candidate entry into `rejected`, records the rejection rationale, and leaves a rejection manifest trail
- `scripts/run_auditor_tests.ps1`: runs the local Pester regression suite for the PowerShell auditor
- `scripts/modules/OneimAudit.Common.psm1`: shared path, directory, and confidence helpers
- `scripts/modules/OneimAudit.RuleCatalog.psm1`: rule-catalog loading, finding creation, gating logic, and rule export helpers
- `scripts/modules/OneimAudit.Reference.psm1`: mandatory reference-path validation and raw-export bootstrap logic
- `scripts/modules/OneimAudit.Detectors.psm1`: file-level detector functions organized around rule families
- `scripts/modules/OneimAudit.PostProcessing.psm1`: suppression handling and duplicate-example caps driven by the rule catalog
- `scripts/modules/OneimAudit.Reporting.psm1`: HTML report rendering
- `scripts/modules/OneimAudit.LiveSession.psm1`: shared TestAssist session bootstrap, project config parsing, connection string builder, and SQL query helper (Session / Direct / Auto modes) used by the schema, benchmark, and cascade scripts
- `tests/Oneim.VbNet.Auditor.Tests.ps1`: regression coverage for reference handling, detectors, post-processing, and the end-to-end runner
- `agents/openai.yaml`: UI metadata for the skill
