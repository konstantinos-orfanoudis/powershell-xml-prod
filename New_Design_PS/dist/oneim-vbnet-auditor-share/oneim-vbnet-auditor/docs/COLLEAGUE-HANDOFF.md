# OneIM VB.NET Auditor Handoff Guide

## What this package is

This package contains a portable review copy of the `oneim-vbnet-auditor` skill.
It audits One Identity Manager VB.NET code for correctness, security, and performance.

The package includes:

- the auditor skill source
- rule catalogs and approved-source mappings
- example compliant and violating VB.NET files
- the PowerShell test suite
- teammate-facing setup and usage guidance

The package intentionally excludes the original `output/` folder because it contained machine-specific runtime artifacts and sensitive connection details that should not be shared.

## Main use cases

- audit custom OneIM scripts, templates, formatting rules, and process-related VB.NET
- review OneIM code against a managed reference library with `ootb`, `promoted-custom`, `candidate-custom`, `rejected`, and `intake-manifests`
- generate HTML and JSON audit reports for peer review
- benchmark templates, script methods, and processes against thresholds
- export a schema snapshot and build cascade reports for template dependency analysis
- review or extend the rule catalog in `assets/audit-rules.json`

## Required dependencies

### For basic static auditing

- Windows PowerShell 5.1 or PowerShell 7
- read/write access to the skill folder and chosen output folder
- a managed OneIM reference repository passed through `-ReferenceRepoPath`

### For running the test suite

- `Pester`
- PowerShell 7 (`pwsh`) for the PS7 test lanes

### For live schema / benchmark / cascade features

- `TestAssist` installation containing `Setup.ps1` and `Intragen.TestAssist.psd1`
- a valid `projectConfig.xml`
- access to the target OneIM database
- `DM_PASS` environment variable if the password is not stored in `projectConfig.xml`

### Optional dependencies

- `BenchmarkDotNet.dll` under the TestAssist root if you want the benchmark script to use BenchmarkDotNet when available
- Codex / ChatGPT skill hosting if you want to use the package as a Codex skill instead of running the PowerShell scripts directly

## Path configuration

The packaged copy was adjusted to avoid hardcoded `aiuser` paths.

The live-session scripts now resolve defaults in this order:

- explicit parameter such as `-TestAssistRoot` or `-ProjectConfigPath`
- environment variables `ONEIM_TESTASSIST_ROOT` and `ONEIM_PROJECT_CONFIG_PATH`
- common fallback locations under the current user's profile

Recommended setup:

```powershell
$env:ONEIM_TESTASSIST_ROOT = 'C:\Tools\TestAssist-1.2.2'
$env:ONEIM_PROJECT_CONFIG_PATH = 'C:\OneIM\Config\projectConfig.xml'
```

## Installation options

### Option 1: review as source only

Unzip the package anywhere and inspect the folder directly.

### Option 2: install as a Codex skill

Copy the `oneim-vbnet-auditor` folder to:

```text
%USERPROFILE%\.codex\skills\oneim-vbnet-auditor
```

The minimum files to keep are:

- `SKILL.md`
- `agents/openai.yaml`
- `assets/`
- `scripts/`

The `examples/`, `references/`, `tests/`, and `docs/` folders are strongly recommended for review and maintenance.

## Quick verification checklist

1. Open `SKILL.md` and confirm the skill description and workflow make sense.
2. Run `Get-Command pwsh` and `Get-Command Invoke-Pester` if tests will be executed.
3. Confirm the reference repository layout exists before running an audit.
4. Set `ONEIM_TESTASSIST_ROOT` and `ONEIM_PROJECT_CONFIG_PATH` if live features will be used.
5. Run one of the sample commands below.

## Usage examples

### 1. Static audit of a custom VB.NET folder

```powershell
pwsh -NoProfile -File .\scripts\invoke_oneim_audit.ps1 `
  -TargetPath 'C:\Work\OneIM\CustomCode' `
  -ReferenceRepoPath 'C:\Work\OneIM\reference-library' `
  -OutputDir '.\output\oneim-vbnet-audit'
```

### 2. Audit a single file

```powershell
pwsh -NoProfile -File .\scripts\invoke_oneim_audit.ps1 `
  -TargetPath 'C:\Work\OneIM\CustomCode\TSB_Custom.vb' `
  -ReferenceRepoPath 'C:\Work\OneIM\reference-library'
```

### 3. Export the active rule set for review

```powershell
pwsh -NoProfile -File .\scripts\export_audit_rules.ps1 `
  -Format Bundle `
  -RuleState Active
```

### 4. Validate the rule catalog after editing `assets/audit-rules.json`

```powershell
pwsh -NoProfile -File .\scripts\validate_audit_rules.ps1
```

### 5. Run the regression suite

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\run_auditor_tests.ps1
```

### 6. Export a live schema snapshot

```powershell
pwsh -NoProfile -File .\scripts\export_oneim_schema_snapshot.ps1 `
  -AccessMode Auto `
  -OutputDir '.\output\oneim-schema'
```

### 7. Benchmark selected templates

```powershell
pwsh -NoProfile -File .\scripts\invoke_oneim_benchmark.ps1 `
  -TemplateNames 'Person.FirstName','Person.LastName' `
  -WarmupCount 1 `
  -MeasuredRunCount 10 `
  -OutputDir '.\output\oneim-benchmark'
```

### 8. Build a cascade report for one template

```powershell
pwsh -NoProfile -File .\scripts\export_template_cascade_report.ps1 `
  -TemplateName 'Person.FirstName' `
  -OutputDir '.\output\oneim-cascade'
```

## Notes for reviewers

- The audit engine is local-first. The approved source catalog is stored in `assets/approved-sources.json`.
- The rule catalog is intentionally reviewable in `assets/audit-rules.json`.
- `examples/` contains living examples for many rule IDs and is a good starting point for tool validation.
- The benchmark, schema, and cascade lanes depend on a live OneIM environment and should be treated as environment-coupled.
- The packaged copy removed historical run output, so a reviewer should generate fresh output on their own machine.
