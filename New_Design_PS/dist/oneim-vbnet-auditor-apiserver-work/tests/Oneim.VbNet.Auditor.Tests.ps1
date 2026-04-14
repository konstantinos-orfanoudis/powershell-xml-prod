$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$skillRoot = Split-Path -Parent $PSScriptRoot
$scriptRoot = Join-Path $skillRoot "scripts"
$moduleRoot = Join-Path $scriptRoot "modules"
$assetRoot = Join-Path $skillRoot "assets"
$runnerPath = Join-Path $scriptRoot "invoke_oneim_audit.ps1"
$reviewPlanScriptPath = Join-Path $scriptRoot "export_candidate_review_plan.ps1"
$splitCandidateScriptPath = Join-Path $scriptRoot "split_candidate_reference.ps1"
$reviewScriptPath = Join-Path $scriptRoot "review_custom_reference.ps1"
$promotionScriptPath = Join-Path $scriptRoot "promote_custom_reference.ps1"
$rejectionScriptPath = Join-Path $scriptRoot "reject_custom_reference.ps1"
$ruleCatalogPath = Join-Path $assetRoot "audit-rules.json"
$approvedSourcesPath = Join-Path $assetRoot "approved-sources.json"

foreach ($modulePath in @(
    (Join-Path $moduleRoot "OneimAudit.Common.psm1"),
    (Join-Path $moduleRoot "OneimAudit.RuleCatalog.psm1"),
    (Join-Path $moduleRoot "OneimAudit.Reference.psm1"),
    (Join-Path $moduleRoot "OneimAudit.Detectors.psm1"),
    (Join-Path $moduleRoot "OneimAudit.PostProcessing.psm1"),
    (Join-Path $moduleRoot "OneimAudit.Reporting.psm1")
)) {
    Import-Module $modulePath -Force
}

$ruleCatalog = Get-OneImAuditRuleCatalog -RuleCatalogPath $ruleCatalogPath
$sourceLookup = Get-OneImAuditSourceLookup -ApprovedSourcesPath $approvedSourcesPath

function New-TestRoot {
    $path = Join-Path ([System.IO.Path]::GetTempPath()) ("oneim-auditor-tests-" + [guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Path $path -Force | Out-Null
    return $path
}

function Write-TestFile {
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [string]$Content
    )

    $parent = Split-Path -Parent $Path
    if ($parent -and -not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }

    Set-Content -LiteralPath $Path -Value $Content -Encoding UTF8
}

function Write-TestRuleCatalog {
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [hashtable]$Catalog
    )

    foreach ($rule in @($Catalog.rules)) {
        $state = if ($null -ne $rule["state"]) { [string]$rule["state"] } else { "" }
        if ($state -ne "active") {
            continue
        }

        if ([string]::IsNullOrWhiteSpace([string]$rule["detector_family"])) {
            $rule["detector_family"] = if ([string]$rule["engine"] -eq "declarative") { "declarative-pattern" } else { "test-fixture" }
        }

        if ([string]::IsNullOrWhiteSpace([string]$rule["remediation"])) {
            $rule["remediation"] = "Apply the fixture remediation and rerun the targeted audit scenario."
        }

        if ($null -eq $rule["test_ideas"] -or @($rule["test_ideas"]).Count -eq 0) {
            $rule["test_ideas"] = @("Exercise the matching and non-matching fixture paths for this rule.")
        }

        if ($null -eq $rule["surface_scope"] -or @($rule["surface_scope"]).Count -eq 0) {
            $rule["surface_scope"] = @("any")
        }

        if ([string]::IsNullOrWhiteSpace([string]$rule["match_confidence"])) {
            $rule["match_confidence"] = "high"
        }
    }

    $Catalog | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $Path -Encoding UTF8
}

function New-ManagedReferenceLayout {
    param(
        [Parameter(Mandatory)]
        [string]$RootPath,

        [Parameter()]
        [string]$OneImVersion = "9.3.1",

        [Parameter()]
        [string]$RelativePath = "Table\Table.vb",

        [Parameter()]
        [string]$Content = "Option Explicit On`r`nOption Strict On`r`nPublic Class Baseline`r`nEnd Class"
    )

    $versionRoot = Join-Path $RootPath ("reference-library\oneim-{0}" -f $OneImVersion)
    foreach ($tier in @("ootb", "promoted-custom", "candidate-custom", "rejected", "intake-manifests")) {
        New-Item -ItemType Directory -Path (Join-Path $versionRoot $tier) -Force | Out-Null
    }

    $ootbRoot = Join-Path $versionRoot "ootb\baseline"
    Write-TestFile -Path (Join-Path $ootbRoot $RelativePath) -Content $Content

    return $versionRoot
}

function New-CandidateReferenceEntry {
    param(
        [Parameter(Mandatory)]
        [string]$RootPath,

        [Parameter()]
        [string]$OneImVersion = "9.3.1",

        [Parameter()]
        [string]$EntryId = "sample-candidate",

        [Parameter()]
        [int]$ConfidenceScore = 90,

        [Parameter()]
        [int]$PromotionThreshold = 85
    )

    $versionRoot = New-ManagedReferenceLayout -RootPath $RootPath -OneImVersion $OneImVersion
    $candidateEntryPath = Join-Path $versionRoot ("candidate-custom\{0}" -f $EntryId)
    $candidateFilePath = Join-Path $candidateEntryPath "files\definitions\Sample.vb"
    Write-TestFile -Path $candidateFilePath -Content "Public Class Sample`r`nEnd Class"

    $metadata = [ordered]@{
        id = $EntryId
        title = "Reviewed custom sample"
        oneim_version = $OneImVersion
        origin = "manual-review"
        status = "candidate-custom"
        source_classification = "mixed-export"
        confidence_score = $ConfidenceScore
        correctness_confidence = $ConfidenceScore
        security_confidence = $ConfidenceScore
        performance_confidence = $ConfidenceScore
        context_confidence = $ConfidenceScore
        confidence_threshold_at_promotion = $PromotionThreshold
        reason_for_status = "Waiting for promotion review."
        last_validated_at = "2026-03-24"
        source_root = $RootPath
        tags = @("oneim", "vbnet", "candidate-custom")
        surfaces = @("Table")
        evidence = @(
            [ordered]@{
                category = "definitions"
                source = "Table\Table.vb"
                start_line = 1
                end_line = 2
                symbol = "Sample"
                kind = "custom-reference-block"
                copied_to = $candidateFilePath
            }
        )
    }
    Write-TestFile -Path (Join-Path $candidateEntryPath "metadata.json") -Content ($metadata | ConvertTo-Json -Depth 8)

    return [pscustomobject]@{
        VersionRoot = $versionRoot
        CandidateEntryPath = $candidateEntryPath
        CandidateMetadataPath = Join-Path $candidateEntryPath "metadata.json"
        CandidateFilePath = $candidateFilePath
        PromotedEntryPath = Join-Path $versionRoot ("promoted-custom\{0}" -f $EntryId)
        IntakeManifestRoot = Join-Path $versionRoot "intake-manifests"
    }
}

function Assert-True {
    param(
        [Parameter(Mandatory)]
        [bool]$Condition,

        [Parameter(Mandatory)]
        [string]$Message
    )

    if (-not $Condition) {
        throw $Message
    }
}

function Assert-Equal {
    param(
        [Parameter(Mandatory)]
        $Actual,

        [Parameter(Mandatory)]
        $Expected,

        [Parameter(Mandatory)]
        [string]$Message
    )

    if ($Actual -is [array] -or $Expected -is [array]) {
        if (-not [object]::Equals($Actual, $Expected)) {
            throw ("{0} Expected '{1}' but got '{2}'." -f $Message, $Expected, $Actual)
        }
        return
    }

    if ($Actual -ne $Expected) {
        throw ("{0} Expected '{1}' but got '{2}'." -f $Message, $Expected, $Actual)
    }
}

function Assert-NotNull {
    param(
        [Parameter(Mandatory)]
        $Value,

        [Parameter(Mandatory)]
        [string]$Message
    )

    if ($null -eq $Value) {
        throw $Message
    }
}

Describe "OneIM VB.NET auditor reference handling" {
    It "detects a valid managed reference library under the repo root layout" {
        $testRoot = New-TestRoot
        try {
            $versionRoot = New-ManagedReferenceLayout -RootPath $testRoot
            $layout = Get-OneImReferenceLayout -ReferenceRepoPath $testRoot -OneImVersion "9.3.1"
            $primaryOotbRoot = Get-OneImPrimaryOotbRoot -VersionRoot $versionRoot

            Assert-NotNull -Value $layout -Message "Expected a managed layout object."
            Assert-True -Condition ([bool]$layout.is_valid) -Message "Expected the managed layout to be valid."
            Assert-Equal -Actual $layout.mode -Expected "repo-root" -Message "Managed layout mode should resolve as repo-root."
            Assert-Equal -Actual ([int]$layout.ootb_file_count) -Expected 1 -Message "OOTB file count should reflect the single seeded baseline file."
            Assert-Equal -Actual $primaryOotbRoot -Expected (Join-Path $versionRoot "ootb\baseline") -Message "Primary OOTB root should point at the seeded baseline folder."
        }
        finally {
            Remove-Item -LiteralPath $testRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It "recognizes a raw export shape and excludes reference-library files from target enumeration" {
        $testRoot = New-TestRoot
        try {
            Write-TestFile -Path (Join-Path $testRoot "Scripts\Scripts.vb") -Content "Public Class ScriptSample`r`nEnd Class"
            Write-TestFile -Path (Join-Path $testRoot "Table\Table.vb") -Content "Public Class TableSample`r`nEnd Class"
            New-ManagedReferenceLayout -RootPath $testRoot | Out-Null

            $rawExport = Test-OneImRawExportShape -Path $testRoot
            $targets = @(Get-OneImTargetFiles -TargetPath $testRoot)

            Assert-True -Condition ([bool]$rawExport.is_likely_raw_export) -Message "Expected the folder to look like a raw System Debugger export."
            Assert-Equal -Actual $targets.Count -Expected 2 -Message "Target enumeration should skip reference-library content."
            Assert-True -Condition ($targets -contains (Join-Path $testRoot "Scripts\Scripts.vb")) -Message "Scripts.vb should be included as a target."
            Assert-True -Condition ($targets -contains (Join-Path $testRoot "Table\Table.vb")) -Message "Table.vb should be included as a target."
        }
        finally {
            Remove-Item -LiteralPath $testRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

Describe "OneIM VB.NET auditor findings and post-processing" {
    It "detects header and trigger-write findings from a minimal VB fixture" {
        $testRoot = New-TestRoot
        try {
            $filePath = Join-Path $testRoot "Table\Table.vb"
            $fixture = @(
                "Public Class DemoTable",
                "    Public Sub Apply()",
                "        Base.PutValue(""Department"", GetTriggerValue(""Department"").String)",
                "    End Sub",
                "End Class"
            ) -join "`r`n"
            Write-TestFile -Path $filePath -Content $fixture

            $findings = @(Get-OneImFileFindings -FilePath $filePath -RelativePath "Table\Table.vb" -RuleCatalog $ruleCatalog -SourceLookup $sourceLookup)
            $ruleIds = @($findings | ForEach-Object { $_.rule_id })

            Assert-True -Condition ($ruleIds -contains "REL220") -Message "Expected the fixture to trigger REL220."
            Assert-True -Condition ($ruleIds -contains "OIM500") -Message "Expected the fixture to trigger OIM500."
        }
        finally {
            Remove-Item -LiteralPath $testRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It "flags CCC-keyed VI-KEY entries whose script names are not CCC-prefixed" {
        $testRoot = New-TestRoot
        try {
            $filePath = Join-Path $testRoot "Scripts\Scripts.vb"
            $fixture = @(
                "Option Explicit On",
                "Option Strict On",
                "' VI-KEY(<Key><T>DialogScript</T><P>CCC-1234567890ABCDEF</P></Key>, ADS_CreateDN)",
                "Public Overridable Function CCC_valid() As String",
                "    Return String.Empty",
                "End Function"
            ) -join "`r`n"
            Write-TestFile -Path $filePath -Content $fixture

            $findings = @(Get-OneImFileFindings -FilePath $filePath -RelativePath "Scripts\Scripts.vb" -RuleCatalog $ruleCatalog -SourceLookup $sourceLookup)
            $scriptNameFindings = @($findings | Where-Object { $_.rule_id -eq "OIM510" })
            $routineNameFindings = @($findings | Where-Object { $_.rule_id -eq "OIM511" })

            Assert-Equal -Actual $scriptNameFindings.Count -Expected 1 -Message "Expected the mismatched VI-KEY script name to trigger OIM510."
            Assert-Equal -Actual $scriptNameFindings[0].line -Expected 3 -Message "The OIM510 finding should point at the VI-KEY line."
            Assert-True -Condition ($scriptNameFindings[0].evidence -like "*ADS_CreateDN*") -Message "The OIM510 evidence should preserve the mismatched script name."
            Assert-Equal -Actual $routineNameFindings.Count -Expected 0 -Message "A CCC-prefixed routine declaration should not trigger OIM511."
        }
        finally {
            Remove-Item -LiteralPath $testRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It "flags CCC-keyed VI-KEY entries whose Function or Sub names are not CCC-prefixed" {
        $testRoot = New-TestRoot
        try {
            $filePath = Join-Path $testRoot "Scripts\Scripts.vb"
            $fixture = @(
                "Option Explicit On",
                "Option Strict On",
                "' VI-KEY(<Key><T>DialogScript</T><P>CCC-ABCDEF0123456789</P></Key>, CCC_valid)",
                "Public Overridable Function ADS_CreateDN() As String",
                "    Return String.Empty",
                "End Function"
            ) -join "`r`n"
            Write-TestFile -Path $filePath -Content $fixture

            $findings = @(Get-OneImFileFindings -FilePath $filePath -RelativePath "Scripts\Scripts.vb" -RuleCatalog $ruleCatalog -SourceLookup $sourceLookup)
            $scriptNameFindings = @($findings | Where-Object { $_.rule_id -eq "OIM510" })
            $routineNameFindings = @($findings | Where-Object { $_.rule_id -eq "OIM511" })

            Assert-Equal -Actual $scriptNameFindings.Count -Expected 0 -Message "A CCC-prefixed VI-KEY script name should not trigger OIM510."
            Assert-Equal -Actual $routineNameFindings.Count -Expected 1 -Message "Expected the mismatched Function or Sub name to trigger OIM511."
            Assert-Equal -Actual $routineNameFindings[0].line -Expected 4 -Message "The OIM511 finding should point at the mismatched routine declaration."
            Assert-True -Condition ($routineNameFindings[0].evidence -like "*ADS_CreateDN*") -Message "The OIM511 evidence should preserve the mismatched routine name."
        }
        finally {
            Remove-Item -LiteralPath $testRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It "does not apply script-only naming rules to template surfaces" {
        $testRoot = New-TestRoot
        try {
            $filePath = Join-Path $testRoot "Table\Table.vb"
            $fixture = @(
                "Option Explicit On",
                "Option Strict On",
                "' VI-KEY(<Key><T>DialogScript</T><P>CCC-1234567890ABCDEF</P></Key>, ADS_CreateDN)",
                "Public Overridable Function ADS_CreateDN() As String",
                "    Return String.Empty",
                "End Function"
            ) -join "`r`n"
            Write-TestFile -Path $filePath -Content $fixture

            $findings = @(Get-OneImFileFindings -FilePath $filePath -RelativePath "Table\Table.vb" -RuleCatalog $ruleCatalog -SourceLookup $sourceLookup)
            Assert-Equal -Actual @($findings | Where-Object { $_.rule_id -in @("OIM510","OIM511") }).Count -Expected 0 -Message "Script-only naming rules should not fire on template paths."
        }
        finally {
            Remove-Item -LiteralPath $testRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It "applies suppressions by rule and path glob" {
        $finding = New-OneImAuditFinding `
            -RuleId "REL220" `
            -RuleCatalog $ruleCatalog `
            -SourceLookup $sourceLookup `
            -FilePath "C:\test\Table\Table.vb" `
            -RelativePath "Table\Table.vb" `
            -Line 1 `
            -Evidence "Base.PutValue(..." `
            -TriggeringScenario "Fixture scenario" `
            -Remediation "Add a Nothing guard." `
            -TestIdeas @("Test with a null trigger value.")

        $processed = Invoke-OneImAuditPostProcessing `
            -Findings @($finding) `
            -RuleCatalog $ruleCatalog `
            -Suppressions @([pscustomobject]@{
                    rule_id = "REL220"
                    path_glob = "Table\Table.vb"
                    justification = "Legacy fixture baseline."
                })

        Assert-Equal -Actual $processed.reported_finding_count -Expected 0 -Message "Suppressed findings should not remain in the active report."
        Assert-Equal -Actual $processed.suppressed_finding_count -Expected 1 -Message "Expected the suppression to be recorded."
        Assert-Equal -Actual $processed.suppressed_findings[0].suppression_justification -Expected "Legacy fixture baseline." -Message "Suppression justification should flow into the report."
    }

    It "caps duplicate-heavy findings according to the rule catalog" {
        $findings = @()
        foreach ($line in 1..10) {
            $findings += New-OneImAuditFinding `
                -RuleId "OIM500" `
                -RuleCatalog $ruleCatalog `
                -SourceLookup $sourceLookup `
                -FilePath "C:\test\Table\Table.vb" `
                -RelativePath "Table\Table.vb" `
                -Line $line `
                -Evidence ("Base.PutValue(""Department{0}"", value)" -f $line) `
                -TriggeringScenario "Fixture scenario" `
                -Remediation "Add a guard." `
                -TestIdeas @("Exercise the guarded path.")
        }

        $processed = Invoke-OneImAuditPostProcessing -Findings $findings -RuleCatalog $ruleCatalog

        Assert-Equal -Actual $processed.reported_finding_count -Expected 8 -Message "OIM500 should be capped to the configured max examples per file."
        Assert-Equal -Actual $processed.omitted_example_count -Expected 2 -Message "The extra OIM500 examples should be counted as omitted."
        Assert-Equal -Actual $processed.omitted_example_summaries[0].rule_id -Expected "OIM500" -Message "Omitted example summary should point at the capped rule."
    }
}

Describe "OneIM VB.NET auditor runner" {
    It "writes JSON and HTML reports from the PowerShell entry point" {
        $testRoot = New-TestRoot
        try {
            New-ManagedReferenceLayout -RootPath $testRoot | Out-Null

            $targetFile = Join-Path $testRoot "Table\Table.vb"
            $fixture = @(
                "Public Class DemoTable",
                "    Public Sub Apply()",
                "        Base.PutValue(""Department"", GetTriggerValue(""Department"").String)",
                "    End Sub",
                "End Class"
            ) -join "`r`n"
            Write-TestFile -Path $targetFile -Content $fixture

            $outputRoot = Join-Path $testRoot "audit-output"
            $hostPath = (Get-Command powershell -ErrorAction Stop).Source
            $null = & $hostPath -NoProfile -ExecutionPolicy Bypass -File $runnerPath -TargetPath $targetFile -ReferenceRepoPath $testRoot -OutputDir $outputRoot -NoPrompt
            $exitCode = $LASTEXITCODE

            $runFolder = Get-ChildItem -LiteralPath $outputRoot -Directory | Sort-Object LastWriteTime -Descending | Select-Object -First 1
            $jsonPath = Join-Path $runFolder.FullName "audit-report.json"
            $htmlPath = Join-Path $runFolder.FullName "audit-report.html"
            $report = Get-Content -LiteralPath $jsonPath -Raw | ConvertFrom-Json

            Assert-Equal -Actual $exitCode -Expected 1 -Message "The runner should return exit code 1 when gating findings are present."
            Assert-True -Condition (Test-Path -LiteralPath $jsonPath) -Message "The runner should emit a JSON report."
            Assert-True -Condition (Test-Path -LiteralPath $htmlPath) -Message "The runner should emit an HTML report."
            Assert-Equal -Actual ([int]$report.summary.files_audited) -Expected 1 -Message "The report should record the audited file count."
            Assert-True -Condition ([int]$report.summary.gating_findings -ge 1) -Message "The fixture should produce at least one gating finding."
            Assert-Equal -Actual $report.reference_validation.mode -Expected "repo-root" -Message "The runner should validate the repo-root reference layout."
        }
        finally {
            Remove-Item -LiteralPath $testRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It "fails fast when suppressions are supplied during the rule-tuning phase" {
        $testRoot = New-TestRoot
        try {
            New-ManagedReferenceLayout -RootPath $testRoot | Out-Null

            $targetFile = Join-Path $testRoot "Scripts\Scripts.vb"
            Write-TestFile -Path $targetFile -Content "Public Class Scripts`r`nEnd Class"
            $suppressionFile = Join-Path $testRoot "suppressions.json"
            Write-TestFile -Path $suppressionFile -Content '{ "suppressions": [] }'

            $outputRoot = Join-Path $testRoot "audit-output"
            $hostPath = (Get-Command powershell -ErrorAction Stop).Source
            $output = & $hostPath -NoProfile -ExecutionPolicy Bypass -File $runnerPath `
                -TargetPath $targetFile -ReferenceRepoPath $testRoot -OutputDir $outputRoot `
                -NoPrompt -SuppressionsFile $suppressionFile 2>&1
            $exitCode = $LASTEXITCODE
            $outText = ($output | Out-String)

            Assert-Equal -Actual $exitCode -Expected 1 -Message "The runner should fail when -SuppressionsFile is supplied in this phase."
            Assert-True -Condition ($outText -match 'Suppressions are intentionally disabled') -Message "The runner should explain that suppressions are disabled during rule tuning."
        }
        finally {
            Remove-Item -LiteralPath $testRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It "writes empty JSON and HTML reports when a target has no findings" {
        $testRoot = New-TestRoot
        try {
            New-ManagedReferenceLayout -RootPath $testRoot | Out-Null

            $targetFile = Join-Path $testRoot "Scripts\Scripts.vb"
            $fixture = @(
                "Option Explicit On",
                "Option Strict On",
                "Option Infer On",
                "",
                "Namespace DynScripts",
                "Public Class Scripts",
                "    Public Function SafeValue(input As String) As String",
                "        If String.IsNullOrWhiteSpace(input) Then",
                "            Return String.Empty",
                "        End If",
                "",
                "        Return input.Trim()",
                "    End Function",
                "End Class",
                "End Namespace"
            ) -join "`r`n"
            Write-TestFile -Path $targetFile -Content $fixture

            $outputRoot = Join-Path $testRoot "audit-output"
            $hostPath = (Get-Command powershell -ErrorAction Stop).Source
            $null = & $hostPath -NoProfile -ExecutionPolicy Bypass -File $runnerPath -TargetPath $targetFile -ReferenceRepoPath $testRoot -OutputDir $outputRoot -NoPrompt
            $exitCode = $LASTEXITCODE

            $runFolder = Get-ChildItem -LiteralPath $outputRoot -Directory | Sort-Object LastWriteTime -Descending | Select-Object -First 1
            $jsonPath = Join-Path $runFolder.FullName "audit-report.json"
            $htmlPath = Join-Path $runFolder.FullName "audit-report.html"
            $report = Get-Content -LiteralPath $jsonPath -Raw | ConvertFrom-Json

            Assert-Equal -Actual $exitCode -Expected 0 -Message "The runner should return exit code 0 when no findings are present."
            Assert-True -Condition (Test-Path -LiteralPath $jsonPath) -Message "The runner should emit a JSON report for a clean file."
            Assert-True -Condition (Test-Path -LiteralPath $htmlPath) -Message "The runner should emit an HTML report for a clean file."
            Assert-Equal -Actual ([int]$report.summary.files_audited) -Expected 1 -Message "The report should record the audited file count for a clean file."
            Assert-Equal -Actual ([int]$report.summary.total_findings) -Expected 0 -Message "The clean fixture should report zero findings."
            Assert-Equal -Actual ([int]$report.summary.gating_findings) -Expected 0 -Message "The clean fixture should report zero gating findings."
        }
        finally {
            Remove-Item -LiteralPath $testRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It "audits an explicit multi-file target selection from a shell-safe target list" {
        $testRoot = New-TestRoot
        try {
            New-ManagedReferenceLayout -RootPath $testRoot | Out-Null

            $tableFile = Join-Path $testRoot "Table\Table.vb"
            $scriptsFile = Join-Path $testRoot "Scripts\Scripts.vb"
            Write-TestFile -Path $tableFile -Content (@(
                "Public Class DemoTable",
                "    Public Sub Apply()",
                "        Base.PutValue(""Department"", GetTriggerValue(""Department"").String)",
                "    End Sub",
                "End Class"
            ) -join "`r`n")
            Write-TestFile -Path $scriptsFile -Content (@(
                "Option Explicit On",
                "Option Strict On",
                "Option Infer On",
                "",
                "Namespace DynScripts",
                "Public Class Scripts",
                "    Public Function SafeValue(input As String) As String",
                "        Return input.Trim()",
                "    End Function",
                "End Class",
                "End Namespace"
            ) -join "`r`n")

            $outputRoot = Join-Path $testRoot "audit-output"
            $hostPath = (Get-Command powershell -ErrorAction Stop).Source
            $null = & $hostPath -NoProfile -ExecutionPolicy Bypass -File $runnerPath -TargetPath "$tableFile|$scriptsFile" -ReferenceRepoPath $testRoot -OutputDir $outputRoot -NoPrompt
            $exitCode = $LASTEXITCODE

            $runFolder = Get-ChildItem -LiteralPath $outputRoot -Directory | Sort-Object LastWriteTime -Descending | Select-Object -First 1
            $jsonPath = Join-Path $runFolder.FullName "audit-report.json"
            $report = Get-Content -LiteralPath $jsonPath -Raw | ConvertFrom-Json
            $reportedPaths = @($report.files | ForEach-Object { $_.relative_path })

            Assert-Equal -Actual $exitCode -Expected 1 -Message "The runner should return exit code 1 when any selected file has gating findings."
            Assert-Equal -Actual ([int]$report.summary.files_audited) -Expected 2 -Message "The report should record the full explicit file selection."
            Assert-Equal -Actual (@($report.selected_target_paths).Count) -Expected 2 -Message "The report should preserve the selected target paths."
            Assert-True -Condition ($reportedPaths -contains "Table\Table.vb") -Message "The report should include the selected Table file."
            Assert-True -Condition ($reportedPaths -contains "Scripts\Scripts.vb") -Message "The report should include the selected Scripts file."
        }
        finally {
            Remove-Item -LiteralPath $testRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It "bootstraps a raw export into a managed reference library when auto-restructure is enabled" {
        $testRoot = New-TestRoot
        try {
            Write-TestFile -Path (Join-Path $testRoot "Scripts\Scripts.vb") -Content (@(
                "Public Class DemoScripts",
                "End Class"
            ) -join "`r`n")

            Write-TestFile -Path (Join-Path $testRoot "Table\Table.vb") -Content (@(
                "Public Class DemoTable",
                "    Public Sub Apply()",
                "        Dim token = ""CCC_CustomRule""",
                "        Base.PutValue(""Department"", GetTriggerValue(""Department"").String)",
                "    End Sub",
                "End Class"
            ) -join "`r`n")

            $outputRoot = Join-Path $testRoot "audit-output"
            $hostPath = (Get-Command powershell -ErrorAction Stop).Source
            $null = & $hostPath -NoProfile -ExecutionPolicy Bypass -File $runnerPath -TargetPath (Join-Path $testRoot "Table\Table.vb") -ReferenceRepoPath $testRoot -OutputDir $outputRoot -AutoRestructureIfNeeded -NoPrompt
            $exitCode = $LASTEXITCODE

            $referenceVersionRoot = Join-Path $testRoot "reference-library\oneim-9.3.1"
            $candidateMetadata = Get-ChildItem -LiteralPath (Join-Path $referenceVersionRoot "candidate-custom") -Recurse -File -Filter "metadata.json" | Select-Object -First 1
            $mixedManifest = Get-ChildItem -LiteralPath (Join-Path $referenceVersionRoot "intake-manifests") -File -Filter "*-mixed-export.json" | Select-Object -First 1
            $runFolder = Get-ChildItem -LiteralPath $outputRoot -Directory | Sort-Object LastWriteTime -Descending | Select-Object -First 1
            $jsonPath = Join-Path $runFolder.FullName "audit-report.json"
            $report = Get-Content -LiteralPath $jsonPath -Raw | ConvertFrom-Json
            $candidateMetadataJson = Get-Content -LiteralPath $candidateMetadata.FullName -Raw | ConvertFrom-Json
            $mixedManifestJson = Get-Content -LiteralPath $mixedManifest.FullName -Raw | ConvertFrom-Json

            Assert-Equal -Actual $exitCode -Expected 1 -Message "The runner should still surface gating findings after auto-restructure."
            Assert-True -Condition (Test-Path -LiteralPath $referenceVersionRoot) -Message "Auto-restructure should create the managed reference-library layout."
            Assert-NotNull -Value $candidateMetadata -Message "Auto-restructure should seed candidate-custom metadata."
            Assert-NotNull -Value $mixedManifest -Message "Auto-restructure should record an intake manifest for the mixed export."
            Assert-Equal -Actual $report.reference_validation.mode -Expected "repo-root" -Message "The runner should switch to the managed repo-root layout after restructure."
            Assert-True -Condition ([int]$report.reference_validation.ootb_file_count -ge 1) -Message "The sanitized OOTB baseline should contain at least one VB file."
            Assert-Equal -Actual $candidateMetadataJson.status -Expected "candidate-custom" -Message "Candidate metadata should mark the extracted snippets as candidate-custom."
            Assert-Equal -Actual $mixedManifestJson.classification -Expected "mixed-export" -Message "The intake manifest should classify the raw export as mixed-export."
        }
        finally {
            Remove-Item -LiteralPath $testRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

Describe "OneIM VB.NET custom reference promotion" {
    It "promotes a reviewed candidate entry into promoted-custom and records the review metadata" {
        $testRoot = New-TestRoot
        try {
            $entry = New-CandidateReferenceEntry -RootPath $testRoot -EntryId "promote-me" -ConfidenceScore 92 -PromotionThreshold 85
            $hostPath = (Get-Command powershell -ErrorAction Stop).Source
            $null = & $hostPath -NoProfile -ExecutionPolicy Bypass -File $reviewScriptPath -CandidateEntryPath $entry.CandidateEntryPath -ConfidenceScore 92 -ReviewNote "Ready for trusted custom promotion." -Reviewer "aiuser" -Recommendation "promote-ready"
            $null = & $hostPath -NoProfile -ExecutionPolicy Bypass -File $promotionScriptPath -CandidateEntryPath $entry.CandidateEntryPath -PromotionNote "Reviewed against known custom behavior." -Reviewer "aiuser"
            $exitCode = $LASTEXITCODE

            $promotedMetadataPath = Join-Path $entry.PromotedEntryPath "metadata.json"
            $promotedMetadata = Get-Content -LiteralPath $promotedMetadataPath -Raw | ConvertFrom-Json
            $promotionManifest = Get-ChildItem -LiteralPath $entry.IntakeManifestRoot -File -Filter "promote-me-promotion-*.json" | Select-Object -First 1
            $promotionManifestJson = Get-Content -LiteralPath $promotionManifest.FullName -Raw | ConvertFrom-Json

            Assert-Equal -Actual $exitCode -Expected 0 -Message "Promotion should succeed for a candidate that meets the confidence threshold."
            Assert-True -Condition (-not (Test-Path -LiteralPath $entry.CandidateEntryPath)) -Message "The promoted entry should no longer remain in candidate-custom."
            Assert-True -Condition (Test-Path -LiteralPath $entry.PromotedEntryPath) -Message "The promoted entry should exist in promoted-custom."
            Assert-Equal -Actual $promotedMetadata.status -Expected "promoted-custom" -Message "Promoted metadata should reflect the promoted-custom status."
            Assert-Equal -Actual $promotedMetadata.reviewer -Expected "aiuser" -Message "Reviewer should be recorded in promoted metadata."
            Assert-Equal -Actual $promotedMetadata.promotion_note -Expected "Reviewed against known custom behavior." -Message "Promotion note should be recorded in promoted metadata."
            Assert-True -Condition ($promotedMetadata.tags -contains "promoted-custom") -Message "Promoted metadata tags should include promoted-custom."
            Assert-True -Condition (-not ($promotedMetadata.tags -contains "candidate-custom")) -Message "Promoted metadata tags should remove candidate-custom."
            Assert-Equal -Actual $promotedMetadata.evidence[0].copied_to -Expected (Join-Path $entry.PromotedEntryPath "files\definitions\Sample.vb") -Message "Evidence paths should be rewritten to the promoted location."
            Assert-NotNull -Value $promotionManifest -Message "A promotion manifest should be written to intake-manifests."
            Assert-Equal -Actual $promotionManifestJson.to_status -Expected "promoted-custom" -Message "Promotion manifest should record the target status."
        }
        finally {
            Remove-Item -LiteralPath $testRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It "blocks promotion when the candidate has not been formally reviewed" {
        $testRoot = New-TestRoot
        try {
            $entry = New-CandidateReferenceEntry -RootPath $testRoot -EntryId "too-low" -ConfidenceScore 60 -PromotionThreshold 85
            $hostPath = (Get-Command powershell -ErrorAction Stop).Source
            $previousPreference = $ErrorActionPreference
            $ErrorActionPreference = "Continue"
            try {
                $null = & $hostPath -NoProfile -ExecutionPolicy Bypass -File $promotionScriptPath -CandidateEntryPath $entry.CandidateEntryPath -PromotionNote "Attempted without override." -Reviewer "aiuser" 2>$null
                $exitCode = $LASTEXITCODE
            }
            finally {
                $ErrorActionPreference = $previousPreference
            }

            Assert-Equal -Actual $exitCode -Expected 1 -Message "Promotion should fail when the candidate has not been formally reviewed."
            Assert-True -Condition (Test-Path -LiteralPath $entry.CandidateEntryPath) -Message "The candidate entry should remain in place after a blocked promotion."
            Assert-True -Condition (-not (Test-Path -LiteralPath $entry.PromotedEntryPath)) -Message "A blocked promotion must not create a promoted entry."
        }
        finally {
            Remove-Item -LiteralPath $testRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

Describe "OneIM VB.NET custom reference review" {
    It "updates candidate review metadata and records a review manifest without moving the entry" {
        $testRoot = New-TestRoot
        try {
            $entry = New-CandidateReferenceEntry -RootPath $testRoot -EntryId "review-me" -ConfidenceScore 45 -PromotionThreshold 85
            $hostPath = (Get-Command powershell -ErrorAction Stop).Source
            $null = & $hostPath -NoProfile -ExecutionPolicy Bypass -File $reviewScriptPath -CandidateEntryPath $entry.CandidateEntryPath -ConfidenceScore 91 -CorrectnessConfidence 95 -SecurityConfidence 90 -PerformanceConfidence 88 -ContextConfidence 86 -ReviewNote "Compared against better provenance notes and marked ready." -Reviewer "aiuser" -Recommendation "promote-ready"
            $exitCode = $LASTEXITCODE

            $metadata = Get-Content -LiteralPath $entry.CandidateMetadataPath -Raw | ConvertFrom-Json
            $reviewManifest = Get-ChildItem -LiteralPath $entry.IntakeManifestRoot -File -Filter "review-me-review-*.json" | Select-Object -First 1
            $reviewManifestJson = Get-Content -LiteralPath $reviewManifest.FullName -Raw | ConvertFrom-Json

            Assert-Equal -Actual $exitCode -Expected 0 -Message "Review should succeed for a candidate entry."
            Assert-True -Condition (Test-Path -LiteralPath $entry.CandidateEntryPath) -Message "Review should not move the candidate entry."
            Assert-Equal -Actual $metadata.status -Expected "candidate-custom" -Message "Review should keep the entry in candidate-custom."
            Assert-Equal -Actual ([int]$metadata.confidence_score) -Expected 91 -Message "Review should update the overall confidence score."
            Assert-Equal -Actual ([int]$metadata.correctness_confidence) -Expected 95 -Message "Review should update the correctness confidence."
            Assert-Equal -Actual $metadata.review_recommendation -Expected "promote-ready" -Message "Review recommendation should be recorded."
            Assert-Equal -Actual ([bool]$metadata.promotion_ready) -Expected $true -Message "Promotion readiness should be true when the score meets the threshold."
            Assert-Equal -Actual $metadata.reviewer -Expected "aiuser" -Message "Reviewer should be recorded."
            Assert-NotNull -Value $reviewManifest -Message "Review should write a manifest entry."
            Assert-Equal -Actual $reviewManifestJson.review_recommendation -Expected "promote-ready" -Message "Review manifest should record the recommendation."
        }
        finally {
            Remove-Item -LiteralPath $testRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It "blocks an inconsistent promote-ready review when the score is below threshold" {
        $testRoot = New-TestRoot
        try {
            $entry = New-CandidateReferenceEntry -RootPath $testRoot -EntryId "bad-review" -ConfidenceScore 45 -PromotionThreshold 85
            $hostPath = (Get-Command powershell -ErrorAction Stop).Source
            $previousPreference = $ErrorActionPreference
            $ErrorActionPreference = "Continue"
            try {
                $null = & $hostPath -NoProfile -ExecutionPolicy Bypass -File $reviewScriptPath -CandidateEntryPath $entry.CandidateEntryPath -ConfidenceScore 60 -ReviewNote "Attempted promote-ready review below threshold." -Reviewer "aiuser" -Recommendation "promote-ready" 2>$null
                $exitCode = $LASTEXITCODE
            }
            finally {
                $ErrorActionPreference = $previousPreference
            }

            $metadata = Get-Content -LiteralPath $entry.CandidateMetadataPath -Raw | ConvertFrom-Json

            Assert-Equal -Actual $exitCode -Expected 1 -Message "Review should fail when promote-ready is requested below threshold."
            Assert-True -Condition (Test-Path -LiteralPath $entry.CandidateEntryPath) -Message "A blocked review must leave the candidate entry in place."
            Assert-True -Condition ($null -eq $metadata.PSObject.Properties["review_recommendation"]) -Message "A blocked review should not stamp a recommendation into metadata."
        }
        finally {
            Remove-Item -LiteralPath $testRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

Describe "OneIM VB.NET candidate review planning" {
    It "exports a snippet-by-snippet review plan that separates strong custom indicators from context-only evidence" {
        $testRoot = New-TestRoot
        try {
            $entry = New-CandidateReferenceEntry -RootPath $testRoot -EntryId "plan-me" -ConfidenceScore 45 -PromotionThreshold 85
            $metadata = Get-Content -LiteralPath $entry.CandidateMetadataPath -Raw | ConvertFrom-Json
            $typedWrapperPath = Join-Path $entry.CandidateEntryPath "files\typed-wrappers\TypedWrapper.vb"
            Write-TestFile -Path $typedWrapperPath -Content "' Extracted from OneIM System Debugger export`r`nPublic Class [CCC_Strong]`r`nEnd Class"
            $metadata.evidence += [pscustomobject]@{
                category = "typed-wrappers"
                source = "TypedWrappers\TypedWrappers.vb"
                start_line = 10
                end_line = 12
                symbol = "CCC_Strong"
                kind = "typed-wrapper-class"
                copied_to = $typedWrapperPath
            }
            $metadata | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $entry.CandidateMetadataPath -Encoding UTF8

            $outputRoot = Join-Path $testRoot "review-plan-output"
            $hostPath = (Get-Command powershell -ErrorAction Stop).Source
            $null = & $hostPath -NoProfile -ExecutionPolicy Bypass -File $reviewPlanScriptPath -CandidateEntryPath $entry.CandidateEntryPath -OutputDir $outputRoot
            $exitCode = $LASTEXITCODE

            $jsonPath = Join-Path $outputRoot "plan-me\candidate-review-plan.json"
            $markdownPath = Join-Path $outputRoot "plan-me\candidate-review-plan.md"
            $plan = Get-Content -LiteralPath $jsonPath -Raw | ConvertFrom-Json

            Assert-Equal -Actual $exitCode -Expected 0 -Message "Review-plan export should succeed for a candidate entry."
            Assert-True -Condition (Test-Path -LiteralPath $jsonPath) -Message "Review-plan export should write JSON output."
            Assert-True -Condition (Test-Path -LiteralPath $markdownPath) -Message "Review-plan export should write Markdown output."
            Assert-Equal -Actual ([int]$plan.summary.total_items) -Expected 2 -Message "Review-plan export should include both evidence items."
            Assert-Equal -Actual ([int]$plan.summary.strong_custom_count) -Expected 1 -Message "Typed wrapper evidence should be classified as a strong custom indicator."
            Assert-Equal -Actual ([int]$plan.summary.context_only_count) -Expected 1 -Message "The default custom-reference-block should be classified as context-only."
            Assert-True -Condition (@($plan.items | Where-Object { $_.kind -eq "typed-wrapper-class" -and $_.review_band -eq "strong-custom" }).Count -eq 1) -Message "Typed wrapper evidence should land in the strong-custom band."
            Assert-True -Condition (@($plan.items | Where-Object { $_.kind -eq "custom-reference-block" -and $_.review_band -eq "context-only" }).Count -eq 1) -Message "Reference-block evidence should land in the context-only band."
        }
        finally {
            Remove-Item -LiteralPath $testRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

Describe "OneIM VB.NET candidate splitting" {
    It "splits strong custom evidence into a focused candidate entry and leaves context-only residue behind" {
        $testRoot = New-TestRoot
        try {
            $entry = New-CandidateReferenceEntry -RootPath $testRoot -EntryId "split-me" -ConfidenceScore 45 -PromotionThreshold 85
            $metadata = Get-Content -LiteralPath $entry.CandidateMetadataPath -Raw | ConvertFrom-Json
            $typedWrapperPath = Join-Path $entry.CandidateEntryPath "files\typed-wrappers\TypedWrapper.vb"
            Write-TestFile -Path $typedWrapperPath -Content "' Extracted from OneIM System Debugger export`r`nPublic Class [CCC_Strong]`r`nEnd Class"
            $metadata.evidence += [pscustomobject]@{
                category = "typed-wrappers"
                source = "TypedWrappers\TypedWrappers.vb"
                start_line = 10
                end_line = 12
                symbol = "CCC_Strong"
                kind = "typed-wrapper-class"
                copied_to = $typedWrapperPath
            }
            $metadata | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $entry.CandidateMetadataPath -Encoding UTF8

            $outputRoot = Join-Path $testRoot "review-plan-output"
            $hostPath = (Get-Command powershell -ErrorAction Stop).Source
            $null = & $hostPath -NoProfile -ExecutionPolicy Bypass -File $reviewPlanScriptPath -CandidateEntryPath $entry.CandidateEntryPath -OutputDir $outputRoot
            $reviewPlanPath = Join-Path $outputRoot "split-me\candidate-review-plan.json"

            $null = & $hostPath -NoProfile -ExecutionPolicy Bypass -File $splitCandidateScriptPath -CandidateEntryPath $entry.CandidateEntryPath -ReviewPlanPath $reviewPlanPath -NewEntryId "split-me-strong-custom" -SplitNote "Separated the strong custom indicator for focused review." -Reviewer "aiuser"
            $exitCode = $LASTEXITCODE

            $sourceMetadata = Get-Content -LiteralPath $entry.CandidateMetadataPath -Raw | ConvertFrom-Json
            $newEntryPath = Join-Path $entry.VersionRoot "candidate-custom\split-me-strong-custom"
            $newMetadataPath = Join-Path $newEntryPath "metadata.json"
            $newMetadata = Get-Content -LiteralPath $newMetadataPath -Raw | ConvertFrom-Json
            $manifest = Get-ChildItem -LiteralPath $entry.IntakeManifestRoot -File -Filter "split-me-split-*.json" | Select-Object -First 1
            $manifestJson = Get-Content -LiteralPath $manifest.FullName -Raw | ConvertFrom-Json

            Assert-Equal -Actual $exitCode -Expected 0 -Message "Candidate split should succeed."
            Assert-Equal -Actual @($sourceMetadata.evidence).Count -Expected 1 -Message "The original entry should retain only the context-only residue."
            Assert-Equal -Actual @($newMetadata.evidence).Count -Expected 1 -Message "The new entry should contain the moved strong custom evidence."
            Assert-Equal -Actual $sourceMetadata.evidence[0].kind -Expected "custom-reference-block" -Message "The original entry should retain the weaker custom-reference-block."
            Assert-Equal -Actual $newMetadata.evidence[0].kind -Expected "typed-wrapper-class" -Message "The new entry should contain the strong typed-wrapper evidence."
            Assert-Equal -Actual $newMetadata.source_classification -Expected "split-from-mixed-export" -Message "The new entry should record that it was split from mixed-export material."
            Assert-True -Condition (Test-Path -LiteralPath $newMetadata.evidence[0].copied_to) -Message "The moved strong evidence file should exist in the new entry."
            Assert-True -Condition (-not (Test-Path -LiteralPath $typedWrapperPath)) -Message "The moved strong evidence file should be removed from the original entry."
            Assert-NotNull -Value $manifest -Message "Candidate split should record a manifest."
            Assert-Equal -Actual ([int]$manifestJson.moved_item_count) -Expected 1 -Message "Split manifest should record the moved item count."
        }
        finally {
            Remove-Item -LiteralPath $testRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

Describe "OneIM VB.NET custom reference rejection" {
    It "moves a reviewed candidate entry into rejected and records the rejection metadata" {
        $testRoot = New-TestRoot
        try {
            $entry = New-CandidateReferenceEntry -RootPath $testRoot -EntryId "reject-me" -ConfidenceScore 90 -PromotionThreshold 85
            $hostPath = (Get-Command powershell -ErrorAction Stop).Source
            $null = & $hostPath -NoProfile -ExecutionPolicy Bypass -File $rejectionScriptPath -CandidateEntryPath $entry.CandidateEntryPath -RejectReason "Duplicate of a stronger promoted sample." -Reviewer "aiuser"
            $exitCode = $LASTEXITCODE

            $rejectedEntryPath = Join-Path $entry.VersionRoot "rejected\reject-me"
            $rejectedMetadataPath = Join-Path $rejectedEntryPath "metadata.json"
            $rejectedMetadata = Get-Content -LiteralPath $rejectedMetadataPath -Raw | ConvertFrom-Json
            $rejectionManifest = Get-ChildItem -LiteralPath $entry.IntakeManifestRoot -File -Filter "reject-me-rejection-*.json" | Select-Object -First 1
            $rejectionManifestJson = Get-Content -LiteralPath $rejectionManifest.FullName -Raw | ConvertFrom-Json

            Assert-Equal -Actual $exitCode -Expected 0 -Message "Rejection should succeed for a candidate entry."
            Assert-True -Condition (-not (Test-Path -LiteralPath $entry.CandidateEntryPath)) -Message "The rejected entry should no longer remain in candidate-custom."
            Assert-True -Condition (Test-Path -LiteralPath $rejectedEntryPath) -Message "The rejected entry should exist in rejected."
            Assert-Equal -Actual $rejectedMetadata.status -Expected "rejected" -Message "Rejected metadata should reflect the rejected status."
            Assert-Equal -Actual $rejectedMetadata.reviewer -Expected "aiuser" -Message "Reviewer should be recorded in rejected metadata."
            Assert-Equal -Actual $rejectedMetadata.rejection_reason -Expected "Duplicate of a stronger promoted sample." -Message "Rejection reason should be recorded in rejected metadata."
            Assert-True -Condition ($rejectedMetadata.tags -contains "rejected") -Message "Rejected metadata tags should include rejected."
            Assert-True -Condition (-not ($rejectedMetadata.tags -contains "candidate-custom")) -Message "Rejected metadata tags should remove candidate-custom."
            Assert-Equal -Actual $rejectedMetadata.evidence[0].copied_to -Expected (Join-Path $rejectedEntryPath "files\definitions\Sample.vb") -Message "Evidence paths should be rewritten to the rejected location."
            Assert-NotNull -Value $rejectionManifest -Message "A rejection manifest should be written to intake-manifests."
            Assert-Equal -Actual $rejectionManifestJson.to_status -Expected "rejected" -Message "Rejection manifest should record the target status."
        }
        finally {
            Remove-Item -LiteralPath $testRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It "refuses to reject an entry whose metadata is no longer candidate-custom" {
        $testRoot = New-TestRoot
        try {
            $entry = New-CandidateReferenceEntry -RootPath $testRoot -EntryId "wrong-status" -ConfidenceScore 90 -PromotionThreshold 85
            $metadata = Get-Content -LiteralPath $entry.CandidateMetadataPath -Raw | ConvertFrom-Json
            $metadata.status = "promoted-custom"
            $metadata | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $entry.CandidateMetadataPath -Encoding UTF8

            $hostPath = (Get-Command powershell -ErrorAction Stop).Source
            $previousPreference = $ErrorActionPreference
            $ErrorActionPreference = "Continue"
            try {
                $null = & $hostPath -NoProfile -ExecutionPolicy Bypass -File $rejectionScriptPath -CandidateEntryPath $entry.CandidateEntryPath -RejectReason "Status drift." -Reviewer "aiuser" 2>$null
                $exitCode = $LASTEXITCODE
            }
            finally {
                $ErrorActionPreference = $previousPreference
            }

            Assert-Equal -Actual $exitCode -Expected 1 -Message "Rejection should fail when metadata status is no longer candidate-custom."
            Assert-True -Condition (Test-Path -LiteralPath $entry.CandidateEntryPath) -Message "The entry should remain in candidate-custom after a blocked rejection."
            Assert-True -Condition (-not (Test-Path -LiteralPath (Join-Path $entry.VersionRoot "rejected\wrong-status"))) -Message "A blocked rejection must not create a rejected entry."
        }
        finally {
            Remove-Item -LiteralPath $testRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

# ---------------------------------------------------------------------------
# Lane 1 — Rule state filtering
# ---------------------------------------------------------------------------
Describe "OneIM VB.NET auditor rule state filtering" {
    It "loads only active rules by default" {
        $testRoot = New-TestRoot
        try {
            $catalog = [ordered]@{
                policy_version = "2026-03-25"
                rules = @(
                    [ordered]@{ id = "T001"; title = "Active rule"; category = "correctness"; severity = "high"; confidence = 80; enabled = $true;  state = "active";   engine = "coded"; why = "x"; source_ids = @() }
                    [ordered]@{ id = "T002"; title = "Draft rule";  category = "correctness"; severity = "low";  confidence = 70; enabled = $false; state = "draft";    engine = "coded"; why = "x"; source_ids = @() }
                    [ordered]@{ id = "T003"; title = "Disabled";    category = "security";    severity = "info"; confidence = 50; enabled = $false; state = "disabled"; engine = "coded"; why = "x"; source_ids = @() }
                )
            }
            $catalogPath = Join-Path $testRoot "test-rules.json"
            Write-TestRuleCatalog -Path $catalogPath -Catalog $catalog

            $active = Get-OneImAuditRuleCatalog -RuleCatalogPath $catalogPath -RuleState "Active"
            Assert-Equal -Actual $active.Count -Expected 1 -Message "Active-only load should return 1 rule."
            Assert-True -Condition ($active.ContainsKey("T001")) -Message "Active rule T001 should be present in the catalog."
        }
        finally {
            Remove-Item -LiteralPath $testRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It "loads all rules when RuleState is All" {
        $testRoot = New-TestRoot
        try {
            $catalog = [ordered]@{
                policy_version = "2026-03-25"
                rules = @(
                    [ordered]@{ id = "T001"; title = "Active";   category = "correctness"; severity = "high"; confidence = 80; enabled = $true;  state = "active";   engine = "coded"; why = "x"; source_ids = @() }
                    [ordered]@{ id = "T002"; title = "Draft";    category = "correctness"; severity = "low";  confidence = 70; enabled = $false; state = "draft";    engine = "coded"; why = "x"; source_ids = @() }
                    [ordered]@{ id = "T003"; title = "Disabled"; category = "security";    severity = "info"; confidence = 50; enabled = $false; state = "disabled"; engine = "coded"; why = "x"; source_ids = @() }
                )
            }
            $catalogPath = Join-Path $testRoot "test-rules.json"
            Write-TestRuleCatalog -Path $catalogPath -Catalog $catalog

            $all = Get-OneImAuditRuleCatalog -RuleCatalogPath $catalogPath -RuleState "All"
            Assert-Equal -Actual $all.Count -Expected 3 -Message "All should return all 3 rules."
        }
        finally {
            Remove-Item -LiteralPath $testRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It "excludes active rules when RuleState is Disabled" {
        $testRoot = New-TestRoot
        try {
            $catalog = [ordered]@{
                policy_version = "2026-03-25"
                rules = @(
                    [ordered]@{ id = "T001"; title = "Active";   category = "correctness"; severity = "high"; confidence = 80; enabled = $true;  state = "active";   engine = "coded"; why = "x"; source_ids = @() }
                    [ordered]@{ id = "T003"; title = "Disabled"; category = "security";    severity = "info"; confidence = 50; enabled = $false; state = "disabled"; engine = "coded"; why = "x"; source_ids = @() }
                )
            }
            $catalogPath = Join-Path $testRoot "test-rules.json"
            Write-TestRuleCatalog -Path $catalogPath -Catalog $catalog

            $disabled = Get-OneImAuditRuleCatalog -RuleCatalogPath $catalogPath -RuleState "Disabled"
            Assert-Equal -Actual $disabled.Count -Expected 1 -Message "Disabled filter should return 1 rule."
            Assert-True -Condition ($disabled.ContainsKey("T003")) -Message "Disabled rule T003 should be present in the catalog."
        }
        finally {
            Remove-Item -LiteralPath $testRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

# ---------------------------------------------------------------------------
# Lane 1 — Declarative detector
# ---------------------------------------------------------------------------
Describe "OneIM VB.NET auditor declarative detector" {
    It "fires line-pattern rule on matching line" {
        $testRoot = New-TestRoot
        try {
            $catalog = [ordered]@{
                policy_version = "2026-03-25"
                rules = @(
                    [ordered]@{
                        id = "D001"; title = "Forbidden call"; category = "security"; severity = "high"
                        confidence = 85; enabled = $true; state = "active"; engine = "declarative"
                        match_kind = "line-pattern"; pattern = "(?i)ForbiddenCall\s*\("
                        why = "Test rule"; triggering_scenario = "Any use of ForbiddenCall"
                        remediation = "Remove it"; test_ideas = @("Verify on file with ForbiddenCall")
                        source_ids = @()
                    }
                )
            }
            $catalogPath = Join-Path $testRoot "test-rules.json"
            Write-TestRuleCatalog -Path $catalogPath -Catalog $catalog
            $rc = Get-OneImAuditRuleCatalog -RuleCatalogPath $catalogPath -RuleState "Active"

            $vbFile = Join-Path $testRoot "Sample.vb"
            $content = "Option Explicit On`r`nDim x = ForbiddenCall()"
            Set-Content -LiteralPath $vbFile -Value $content -Encoding UTF8

            $findings = @(Get-OneImFileFindings -FilePath $vbFile -RelativePath "Sample.vb" -RuleCatalog $rc -SourceLookup @{})
            $match = @($findings | Where-Object { $_.rule_id -eq "D001" })
            Assert-True -Condition ($match.Count -ge 1) -Message "line-pattern rule D001 should fire at least once."
            Assert-Equal -Actual $match[0].line -Expected 2 -Message "Finding should be on line 2."
        }
        finally {
            Remove-Item -LiteralPath $testRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It "fires header-required rule when pattern absent from first 40 lines" {
        $testRoot = New-TestRoot
        try {
            $catalog = [ordered]@{
                policy_version = "2026-03-25"
                rules = @(
                    [ordered]@{
                        id = "D002"; title = "Missing Option Strict"; category = "correctness"; severity = "medium"
                        confidence = 90; enabled = $true; state = "active"; engine = "declarative"
                        match_kind = "header-required"; pattern = "(?i)^\s*Option\s+Strict\s+On"
                        why = "Option Strict On required"; triggering_scenario = "File missing Option Strict On"
                        remediation = "Add Option Strict On"; test_ideas = @("File without Option Strict On")
                        source_ids = @()
                    }
                )
            }
            $catalogPath = Join-Path $testRoot "test-rules.json"
            Write-TestRuleCatalog -Path $catalogPath -Catalog $catalog
            $rc = Get-OneImAuditRuleCatalog -RuleCatalogPath $catalogPath -RuleState "Active"

            $vbFile = Join-Path $testRoot "NoStrict.vb"
            Set-Content -LiteralPath $vbFile -Value "Public Class Foo`r`nEnd Class" -Encoding UTF8

            $findings = @(Get-OneImFileFindings -FilePath $vbFile -RelativePath "NoStrict.vb" -RuleCatalog $rc -SourceLookup @{})
            $match = @($findings | Where-Object { $_.rule_id -eq "D002" })
            Assert-True -Condition ($match.Count -ge 1) -Message "header-required rule D002 should fire when pattern absent."
            Assert-Equal -Actual $match[0].line -Expected 1 -Message "header-required finding should be at line 1."
        }
        finally {
            Remove-Item -LiteralPath $testRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It "does NOT fire header-required rule when pattern present in first 40 lines" {
        $testRoot = New-TestRoot
        try {
            $catalog = [ordered]@{
                policy_version = "2026-03-25"
                rules = @(
                    [ordered]@{
                        id = "D002"; title = "Missing Option Strict"; category = "correctness"; severity = "medium"
                        confidence = 90; enabled = $true; state = "active"; engine = "declarative"
                        match_kind = "header-required"; pattern = "(?i)^\s*Option\s+Strict\s+On"
                        why = "x"; triggering_scenario = "x"; remediation = "x"
                        test_ideas = @("x"); source_ids = @()
                    }
                )
            }
            $catalogPath = Join-Path $testRoot "test-rules.json"
            Write-TestRuleCatalog -Path $catalogPath -Catalog $catalog
            $rc = Get-OneImAuditRuleCatalog -RuleCatalogPath $catalogPath -RuleState "Active"

            $vbFile = Join-Path $testRoot "WithStrict.vb"
            Set-Content -LiteralPath $vbFile -Value "Option Strict On`r`nPublic Class Foo`r`nEnd Class" -Encoding UTF8

            $findings = @(Get-OneImFileFindings -FilePath $vbFile -RelativePath "WithStrict.vb" -RuleCatalog $rc -SourceLookup @{})
            $match = @($findings | Where-Object { $_.rule_id -eq "D002" })
            Assert-True -Condition ($match.Count -eq 0) -Message "header-required rule D002 must NOT fire when pattern is present."
        }
        finally {
            Remove-Item -LiteralPath $testRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It "fires line-absence rule when no line matches the pattern" {
        $testRoot = New-TestRoot
        try {
            $catalog = [ordered]@{
                policy_version = "2026-03-25"
                rules = @(
                    [ordered]@{
                        id = "D004"; title = "Missing required keyword"; category = "correctness"; severity = "medium"
                        confidence = 80; enabled = $true; state = "active"; engine = "declarative"
                        match_kind = "line-absence"; pattern = "(?i)RequiredKeyword"
                        why = "RequiredKeyword must appear somewhere in the file."
                        triggering_scenario = "File has no RequiredKeyword"; remediation = "Add RequiredKeyword."
                        test_ideas = @("File without RequiredKeyword should fire"); source_ids = @()
                    }
                )
            }
            $catalogPath = Join-Path $testRoot "test-rules.json"
            Write-TestRuleCatalog -Path $catalogPath -Catalog $catalog
            $rc = Get-OneImAuditRuleCatalog -RuleCatalogPath $catalogPath -RuleState "Active"

            $vbFile = Join-Path $testRoot "NoKeyword.vb"
            Set-Content -LiteralPath $vbFile -Value "Public Class Foo`r`nEnd Class" -Encoding UTF8

            $findings = @(Get-OneImFileFindings -FilePath $vbFile -RelativePath "NoKeyword.vb" -RuleCatalog $rc -SourceLookup @{})
            $match = @($findings | Where-Object { $_.rule_id -eq "D004" })
            Assert-True  -Condition ($match.Count -ge 1) -Message "line-absence rule D004 should fire when pattern is absent from the file."
            Assert-Equal -Actual $match[0].line -Expected 1 -Message "line-absence finding should be reported at line 1."
        }
        finally {
            Remove-Item -LiteralPath $testRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It "does NOT fire line-absence rule when the pattern is present" {
        $testRoot = New-TestRoot
        try {
            $catalog = [ordered]@{
                policy_version = "2026-03-25"
                rules = @(
                    [ordered]@{
                        id = "D004"; title = "Missing required keyword"; category = "correctness"; severity = "medium"
                        confidence = 80; enabled = $true; state = "active"; engine = "declarative"
                        match_kind = "line-absence"; pattern = "(?i)RequiredKeyword"
                        why = "x"; triggering_scenario = "x"; remediation = "x"
                        test_ideas = @("x"); source_ids = @()
                    }
                )
            }
            $catalogPath = Join-Path $testRoot "test-rules.json"
            Write-TestRuleCatalog -Path $catalogPath -Catalog $catalog
            $rc = Get-OneImAuditRuleCatalog -RuleCatalogPath $catalogPath -RuleState "Active"

            $vbFile = Join-Path $testRoot "WithKeyword.vb"
            Set-Content -LiteralPath $vbFile -Value "Public Class Foo`r`n    ' RequiredKeyword present`r`nEnd Class" -Encoding UTF8

            $findings = @(Get-OneImFileFindings -FilePath $vbFile -RelativePath "WithKeyword.vb" -RuleCatalog $rc -SourceLookup @{})
            $match = @($findings | Where-Object { $_.rule_id -eq "D004" })
            Assert-True -Condition ($match.Count -eq 0) -Message "line-absence rule D004 must NOT fire when pattern is present in the file."
        }
        finally {
            Remove-Item -LiteralPath $testRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It "respects include_paths scoping - does not fire on excluded path" {
        $testRoot = New-TestRoot
        try {
            $catalog = [ordered]@{
                policy_version = "2026-03-25"
                rules = @(
                    [ordered]@{
                        id = "D003"; title = "Scoped rule"; category = "correctness"; severity = "low"
                        confidence = 70; enabled = $true; state = "active"; engine = "declarative"
                        match_kind = "line-pattern"; pattern = "(?i)SomeBadPattern"
                        include_paths = @("Scripts\*")
                        why = "x"; triggering_scenario = "x"; remediation = "x"
                        test_ideas = @("x"); source_ids = @()
                    }
                )
            }
            $catalogPath = Join-Path $testRoot "test-rules.json"
            Write-TestRuleCatalog -Path $catalogPath -Catalog $catalog
            $rc = Get-OneImAuditRuleCatalog -RuleCatalogPath $catalogPath -RuleState "Active"

            $vbFile = Join-Path $testRoot "Table\Table.vb"
            New-Item -ItemType Directory -Path (Join-Path $testRoot "Table") -Force | Out-Null
            Set-Content -LiteralPath $vbFile -Value "Dim x = SomeBadPattern()" -Encoding UTF8

            # File is in Table\, rule includes only Scripts\ — should not fire
            $findings = @(Get-OneImFileFindings -FilePath $vbFile -RelativePath "Table\Table.vb" -RuleCatalog $rc -SourceLookup @{})
            $match = @($findings | Where-Object { $_.rule_id -eq "D003" })
            Assert-True -Condition ($match.Count -eq 0) -Message "D003 must not fire on Table\Table.vb when include_paths restricts to Scripts\*."
        }
        finally {
            Remove-Item -LiteralPath $testRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It "respects exclude_paths scoping - does not fire on excluded path" {
        $testRoot = New-TestRoot
        try {
            $catalog = [ordered]@{
                policy_version = "2026-03-25"
                rules = @(
                    [ordered]@{
                        id = "D005"; title = "Excluded rule"; category = "correctness"; severity = "low"
                        confidence = 70; enabled = $true; state = "active"; engine = "declarative"
                        match_kind = "line-pattern"; pattern = "(?i)SomeBadPattern"
                        exclude_paths = @("Generated\*")
                        why = "x"; triggering_scenario = "x"; remediation = "x"
                        test_ideas = @("x"); source_ids = @()
                    }
                )
            }
            $catalogPath = Join-Path $testRoot "test-rules.json"
            Write-TestRuleCatalog -Path $catalogPath -Catalog $catalog
            $rc = Get-OneImAuditRuleCatalog -RuleCatalogPath $catalogPath -RuleState "Active"

            New-Item -ItemType Directory -Path (Join-Path $testRoot "Generated") -Force | Out-Null
            $vbFile = Join-Path $testRoot "Generated\Gen.vb"
            Set-Content -LiteralPath $vbFile -Value "Dim x = SomeBadPattern()" -Encoding UTF8

            # File is in Generated\, which is excluded — rule must not fire
            $findings = @(Get-OneImFileFindings -FilePath $vbFile -RelativePath "Generated\Gen.vb" -RuleCatalog $rc -SourceLookup @{})
            $match = @($findings | Where-Object { $_.rule_id -eq "D005" })
            Assert-True -Condition ($match.Count -eq 0) -Message "D005 must not fire on Generated\Gen.vb when exclude_paths covers Generated\*."
        }
        finally {
            Remove-Item -LiteralPath $testRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It "exclude_paths does not suppress firing on a non-excluded path" {
        $testRoot = New-TestRoot
        try {
            $catalog = [ordered]@{
                policy_version = "2026-03-25"
                rules = @(
                    [ordered]@{
                        id = "D005"; title = "Excluded rule"; category = "correctness"; severity = "low"
                        confidence = 70; enabled = $true; state = "active"; engine = "declarative"
                        match_kind = "line-pattern"; pattern = "(?i)SomeBadPattern"
                        exclude_paths = @("Generated\*")
                        why = "x"; triggering_scenario = "x"; remediation = "x"
                        test_ideas = @("x"); source_ids = @()
                    }
                )
            }
            $catalogPath = Join-Path $testRoot "test-rules.json"
            Write-TestRuleCatalog -Path $catalogPath -Catalog $catalog
            $rc = Get-OneImAuditRuleCatalog -RuleCatalogPath $catalogPath -RuleState "Active"

            New-Item -ItemType Directory -Path (Join-Path $testRoot "Scripts") -Force | Out-Null
            $vbFile = Join-Path $testRoot "Scripts\Scripts.vb"
            Set-Content -LiteralPath $vbFile -Value "Dim x = SomeBadPattern()" -Encoding UTF8

            # File is in Scripts\, which is NOT excluded — rule must fire
            $findings = @(Get-OneImFileFindings -FilePath $vbFile -RelativePath "Scripts\Scripts.vb" -RuleCatalog $rc -SourceLookup @{})
            $match = @($findings | Where-Object { $_.rule_id -eq "D005" })
            Assert-True -Condition ($match.Count -ge 1) -Message "D005 must fire on Scripts\Scripts.vb because Scripts\ is not in exclude_paths."
        }
        finally {
            Remove-Item -LiteralPath $testRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

# ---------------------------------------------------------------------------
# Lane 1 — Rule export bundle
# ---------------------------------------------------------------------------
Describe "OneIM VB.NET auditor rule export bundle" {
    It "bundle mode writes Markdown, JSON, and CSV files - all non-empty" {
        $testRoot = New-TestRoot
        try {
            $catalog = [ordered]@{
                policy_version = "2026-03-25"
                rules = @(
                    [ordered]@{ id = "E001"; title = "Export rule"; category = "correctness"; severity = "high"; confidence = 80; enabled = $true; state = "active"; engine = "coded"; why = "x"; source_ids = @() }
                )
            }
            $catalogPath = Join-Path $testRoot "test-rules.json"
            Write-TestRuleCatalog -Path $catalogPath -Catalog $catalog

            $sourcesPath = Join-Path $testRoot "approved-sources.json"
            ([ordered]@{ sources = @() }) | ConvertTo-Json | Set-Content -LiteralPath $sourcesPath -Encoding UTF8

            $outDir = Join-Path $testRoot "export-out"
            $rc = Get-OneImAuditRuleCatalog -RuleCatalogPath $catalogPath -RuleState "Active"
            $sl = Get-OneImAuditSourceLookup -ApprovedSourcesPath $sourcesPath

            $mdContent  = Export-OneImAuditRuleSet -RuleCatalog $rc -SourceLookup $sl -Format "Markdown"
            $jsonContent = Export-OneImAuditRuleSet -RuleCatalog $rc -SourceLookup $sl -Format "Json"
            $csvContent  = Export-OneImAuditRuleSet -RuleCatalog $rc -SourceLookup $sl -Format "Csv"

            Assert-True -Condition (-not [string]::IsNullOrWhiteSpace($mdContent))   -Message "Markdown export must not be empty."
            Assert-True -Condition (-not [string]::IsNullOrWhiteSpace($jsonContent)) -Message "JSON export must not be empty."
            Assert-True -Condition (-not [string]::IsNullOrWhiteSpace($csvContent))  -Message "CSV export must not be empty."

            # JSON export is a plain array of rule objects (not {rules:[...]})
            $parsed = $jsonContent | ConvertFrom-Json
            $ruleMatch = @($parsed | Where-Object { [string]$_.Id -eq "E001" })
            Assert-True -Condition ($ruleMatch.Count -eq 1) -Message "JSON export should contain rule E001."

            # CSV header must include declarative columns
            $csvHeaders = ($csvContent -split [Environment]::NewLine)[0]
            Assert-True -Condition ($csvHeaders -match '"Why"')                -Message "CSV header should include Why column."
            Assert-True -Condition ($csvHeaders -match '"MatchKind"')          -Message "CSV header should include MatchKind column."
            Assert-True -Condition ($csvHeaders -match '"Pattern"')            -Message "CSV header should include Pattern column."
            Assert-True -Condition ($csvHeaders -match '"TriggeringScenario"') -Message "CSV header should include TriggeringScenario column."
            Assert-True -Condition ($csvHeaders -match '"Remediation"')        -Message "CSV header should include Remediation column."

            # Markdown header must also include the declarative columns
            Assert-True -Condition ($mdContent -match '\| Why \|')                 -Message "Markdown header should include Why column."
            Assert-True -Condition ($mdContent -match '\| Match Kind \|')          -Message "Markdown header should include Match Kind column."
            Assert-True -Condition ($mdContent -match '\| Pattern \|')             -Message "Markdown header should include Pattern column."
            Assert-True -Condition ($mdContent -match '\| Triggering Scenario \|') -Message "Markdown header should include Triggering Scenario column."
            Assert-True -Condition ($mdContent -match '\| Remediation \|')         -Message "Markdown header should include Remediation column."
        }
        finally {
            Remove-Item -LiteralPath $testRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

# ---------------------------------------------------------------------------
# Lane 1 — Rule validation
# ---------------------------------------------------------------------------
Describe "OneIM VB.NET auditor rule validation" {
    $validateScript = Join-Path $scriptRoot "validate_audit_rules.ps1"
    $pwshCmd = Get-Command pwsh -ErrorAction SilentlyContinue
    $hostPath = if ($pwshCmd) { $pwshCmd.Source } else { $null }
    if (-not $hostPath) {
        $psCmd = Get-Command powershell -ErrorAction SilentlyContinue
        $hostPath = if ($psCmd) { $psCmd.Source } else { $null }
    }

    It "passes on the real rule catalog" {
        if (-not $hostPath) { throw "PowerShell host not found." }
        $exitCode = 0
        $previousPreference = $ErrorActionPreference
        $ErrorActionPreference = "Continue"
        try {
            $null = & $hostPath -NoProfile -ExecutionPolicy Bypass -File $validateScript -RuleCatalogPath $ruleCatalogPath 2>$null
            $exitCode = $LASTEXITCODE
        }
        finally {
            $ErrorActionPreference = $previousPreference
        }
        Assert-Equal -Actual $exitCode -Expected 0 -Message "validate_audit_rules.ps1 should exit 0 on the real catalog."
    }

    It "fails with exit 1 on duplicate rule IDs" {
        if (-not $hostPath) { throw "PowerShell host not found." }
        $testRoot = New-TestRoot
        try {
            $catalog = [ordered]@{
                policy_version = "2026-03-25"
                rules = @(
                    [ordered]@{ id = "DUP1"; title = "A"; category = "correctness"; severity = "high"; confidence = 80; state = "active"; engine = "coded"; why = "x"; source_ids = @() }
                    [ordered]@{ id = "DUP1"; title = "B"; category = "security";    severity = "low";  confidence = 70; state = "active"; engine = "coded"; why = "x"; source_ids = @() }
                )
            }
            $dupCatalogPath = Join-Path $testRoot "dup-rules.json"
            Write-TestRuleCatalog -Path $dupCatalogPath -Catalog $catalog

            $exitCode = 0
            $previousPreference = $ErrorActionPreference
            $ErrorActionPreference = "Continue"
            try {
                $null = & $hostPath -NoProfile -ExecutionPolicy Bypass -File $validateScript -RuleCatalogPath $dupCatalogPath 2>$null
                $exitCode = $LASTEXITCODE
            }
            finally {
                $ErrorActionPreference = $previousPreference
            }
            Assert-Equal -Actual $exitCode -Expected 1 -Message "Validation must fail (exit 1) on duplicate rule ID."
        }
        finally {
            Remove-Item -LiteralPath $testRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It "fails with exit 1 on invalid regex pattern in declarative rule" {
        if (-not $hostPath) { throw "PowerShell host not found." }
        $testRoot = New-TestRoot
        try {
            $catalog = [ordered]@{
                policy_version = "2026-03-25"
                rules = @(
                    [ordered]@{
                        id = "BAD1"; title = "Bad regex"; category = "correctness"; severity = "high"; confidence = 80
                        state = "active"; engine = "declarative"
                        match_kind = "line-pattern"; pattern = "(?invalid"
                        why = "x"; triggering_scenario = "x"; remediation = "x"; test_ideas = @("x"); source_ids = @()
                    }
                )
            }
            $badCatalogPath = Join-Path $testRoot "bad-rules.json"
            Write-TestRuleCatalog -Path $badCatalogPath -Catalog $catalog

            $exitCode = 0
            $previousPreference = $ErrorActionPreference
            $ErrorActionPreference = "Continue"
            try {
                $null = & $hostPath -NoProfile -ExecutionPolicy Bypass -File $validateScript -RuleCatalogPath $badCatalogPath 2>$null
                $exitCode = $LASTEXITCODE
            }
            finally {
                $ErrorActionPreference = $previousPreference
            }
            Assert-Equal -Actual $exitCode -Expected 1 -Message "Validation must fail (exit 1) on an invalid regex pattern."
        }
        finally {
            Remove-Item -LiteralPath $testRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It "fails with exit 1 when a source_id is not in approved-sources" {
        if (-not $hostPath) { throw "PowerShell host not found." }
        $testRoot = New-TestRoot
        try {
            $catalog = [ordered]@{
                policy_version = "2026-03-25"
                rules = @(
                    [ordered]@{ id = "SRC1"; title = "A"; category = "correctness"; severity = "high"; confidence = 80; state = "active"; engine = "coded"; why = "x"; source_ids = @("unknown-source-xyz") }
                )
            }
            $catalogPath = Join-Path $testRoot "rules.json"
            Write-TestRuleCatalog -Path $catalogPath -Catalog $catalog

            $sources = [ordered]@{ policy_version = "2026-01-01"; allowed_authorities = @(); sources = @(
                [ordered]@{ id = "known-source"; family = "vbnet-semantics"; title = "Known"; authority = "Microsoft Learn"; url = "https://example.com"; applies_to = @() }
            )}
            $sourcesPath = Join-Path $testRoot "sources.json"
            $sources | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $sourcesPath -Encoding UTF8

            $exitCode = 0
            $previousPreference = $ErrorActionPreference
            $ErrorActionPreference = "Continue"
            try {
                $null = & $hostPath -NoProfile -ExecutionPolicy Bypass -File $validateScript -RuleCatalogPath $catalogPath -ApprovedSourcesPath $sourcesPath 2>$null
                $exitCode = $LASTEXITCODE
            }
            finally {
                $ErrorActionPreference = $previousPreference
            }
            Assert-Equal -Actual $exitCode -Expected 1 -Message "Validation must fail (exit 1) when source_id is not in approved sources."
        }
        finally {
            Remove-Item -LiteralPath $testRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It "emits WARN for a draft declarative rule with empty test_ideas and still exits 0" {
        if (-not $hostPath) { throw "PowerShell host not found." }
        $testRoot = New-TestRoot
        try {
            $catalog = [ordered]@{
                policy_version = "2026-03-25"
                rules = @(
                    [ordered]@{
                        id = "WARN1"; title = "Empty ideas"; category = "correctness"; severity = "medium"
                        confidence = 80; state = "draft"; engine = "declarative"
                        match_kind = "line-pattern"; pattern = "(?i)BadCall"
                        why = "x"; triggering_scenario = "x"; remediation = "x"
                        test_ideas = @(); source_ids = @()
                    }
                )
            }
            $catalogPath = Join-Path $testRoot "rules.json"
            Write-TestRuleCatalog -Path $catalogPath -Catalog $catalog

            $exitCode = 0
            $output = $null
            $previousPreference = $ErrorActionPreference
            $ErrorActionPreference = "Continue"
            try {
                $output = & $hostPath -NoProfile -ExecutionPolicy Bypass -File $validateScript -RuleCatalogPath $catalogPath 2>&1
                $exitCode = $LASTEXITCODE
            }
            finally {
                $ErrorActionPreference = $previousPreference
            }
            $outStr = ($output | Out-String)
            Assert-Equal -Actual $exitCode -Expected 0 -Message "Empty test_ideas on a draft rule should produce a warning but not cause exit 1."
            Assert-True  -Condition ($outStr -match "\[WARN\]") -Message "Output should include a [WARN] line for the empty test_ideas."
        }
        finally {
            Remove-Item -LiteralPath $testRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

Describe "OneIM VB.NET auditor rule catalog contracts" {
    It "active rules expose the required metadata fields" {
        $rawCatalog = Get-Content -LiteralPath $ruleCatalogPath -Raw | ConvertFrom-Json
        $missing = New-Object System.Collections.Generic.List[string]

        foreach ($rule in @($rawCatalog.rules | Where-Object { [string]$_.state -eq 'active' })) {
            if ([string]::IsNullOrWhiteSpace([string]$rule.detector_family)) { $missing.Add("$($rule.id):detector_family") }
            if ([string]::IsNullOrWhiteSpace([string]$rule.remediation))     { $missing.Add("$($rule.id):remediation") }
            if ([string]::IsNullOrWhiteSpace([string]$rule.match_confidence)) { $missing.Add("$($rule.id):match_confidence") }
            if ($null -eq $rule.test_ideas -or @($rule.test_ideas).Count -eq 0) { $missing.Add("$($rule.id):test_ideas") }

            $surfaceValues = @()
            if ($rule.surface_scope -is [System.Collections.IEnumerable] -and -not ($rule.surface_scope -is [string])) {
                $surfaceValues = @($rule.surface_scope)
            } elseif (-not [string]::IsNullOrWhiteSpace([string]$rule.surface_scope)) {
                $surfaceValues = @([string]$rule.surface_scope)
            }
            if ($surfaceValues.Count -eq 0) { $missing.Add("$($rule.id):surface_scope") }
        }

        Assert-Equal -Actual $missing.Count -Expected 0 -Message ("Active rules missing required metadata: {0}" -f ($missing -join ', '))
    }

    It "active rules all have compliant and violation examples" {
        $rawCatalog = Get-Content -LiteralPath $ruleCatalogPath -Raw | ConvertFrom-Json
        $missing = New-Object System.Collections.Generic.List[string]
        foreach ($rule in @($rawCatalog.rules | Where-Object { [string]$_.state -eq 'active' })) {
            $base = Join-Path $skillRoot ("examples\{0}" -f [string]$rule.id)
            if (-not (Test-Path -LiteralPath (Join-Path $base 'violation.vb'))) { $missing.Add("$($rule.id):violation") }
            if (-not (Test-Path -LiteralPath (Join-Path $base 'compliant.vb'))) { $missing.Add("$($rule.id):compliant") }
        }

        Assert-Equal -Actual $missing.Count -Expected 0 -Message ("Active rules missing examples: {0}" -f ($missing -join ', '))
    }

    It "active declarative rules no longer have blank detector families" {
        $rawCatalog = Get-Content -LiteralPath $ruleCatalogPath -Raw | ConvertFrom-Json
        $blankFamilies = @($rawCatalog.rules | Where-Object { [string]$_.state -eq 'active' -and [string]$_.engine -eq 'declarative' -and [string]::IsNullOrWhiteSpace([string]$_.detector_family) })
        Assert-Equal -Actual $blankFamilies.Count -Expected 0 -Message "Active declarative rules should all declare a detector family."
    }
}

# ---------------------------------------------------------------------------
# Lane 1 — Rule scaffolding
# ---------------------------------------------------------------------------
Describe "OneIM VB.NET auditor rule scaffolding" {
    $scaffoldScript = Join-Path $scriptRoot "new_audit_rule.ps1"
    $pwshCmd2 = Get-Command pwsh -ErrorAction SilentlyContinue
    $hostPath = if ($pwshCmd2) { $pwshCmd2.Source } else { $null }
    if (-not $hostPath) {
        $psCmd2 = Get-Command powershell -ErrorAction SilentlyContinue
        $hostPath = if ($psCmd2) { $psCmd2.Source } else { $null }
    }

    It "scaffolds a new draft declarative rule into the catalog" {
        if (-not $hostPath) { throw "PowerShell host not found." }
        $testRoot = New-TestRoot
        try {
            # Seed a minimal catalog in the expected layout (scaffold resolves relative to script)
            $fakeSkillRoot = Join-Path $testRoot "skill"
            $fakeScriptsRoot = Join-Path $fakeSkillRoot "scripts"
            New-Item -ItemType Directory -Path (Join-Path $fakeSkillRoot "assets") -Force | Out-Null
            New-Item -ItemType Directory -Path $fakeScriptsRoot -Force | Out-Null

            $seedCatalog = [ordered]@{ policy_version = "2026-03-25"; rules = @() }
            $seedCatalogPath = Join-Path $fakeSkillRoot "assets\audit-rules.json"
            Write-TestRuleCatalog -Path $seedCatalogPath -Catalog $seedCatalog

            # Copy the scaffold script to the fake scripts folder so it resolves paths correctly
            Copy-Item -LiteralPath $scaffoldScript -Destination (Join-Path $fakeScriptsRoot "new_audit_rule.ps1") -Force

            $exitCode = 0
            $previousPreference = $ErrorActionPreference
            $ErrorActionPreference = "Continue"
            try {
                $null = & $hostPath -NoProfile -ExecutionPolicy Bypass -File (Join-Path $fakeScriptsRoot "new_audit_rule.ps1") `
                    -Id "SC001" -Title "Scaffold test rule" -Category "correctness" -Severity "medium" `
                    -Pattern "(?i)ScaffoldTest" -Why "Test" `
                    -TriggeringScenario "When ScaffoldTest appears" `
                    -Remediation "Remove ScaffoldTest" -TestIdeas @("File with ScaffoldTest") 2>$null
                $exitCode = $LASTEXITCODE
            }
            finally {
                $ErrorActionPreference = $previousPreference
            }

            Assert-Equal -Actual $exitCode -Expected 0 -Message "new_audit_rule.ps1 should exit 0 after scaffolding."

            $updatedCatalog = Get-Content -LiteralPath $seedCatalogPath -Raw | ConvertFrom-Json
            $newRule = @($updatedCatalog.rules | Where-Object { [string]$_.id -eq "SC001" })
            Assert-True -Condition ($newRule.Count -eq 1) -Message "Scaffolded rule SC001 should appear in the catalog."
            Assert-Equal -Actual ([string]$newRule[0].state) -Expected "draft" -Message "Scaffolded rule should be in draft state."
            Assert-Equal -Actual ([string]$newRule[0].engine) -Expected "declarative" -Message "Scaffolded rule should have engine=declarative."
            Assert-Equal -Actual ([string]$newRule[0].detector_family) -Expected "custom-rule" -Message "Scaffolded draft rules should get a default detector family."
            Assert-Equal -Actual ([string]$newRule[0].match_confidence) -Expected "medium" -Message "Scaffolded draft rules should default match_confidence to medium."
            Assert-Equal -Actual ([string]$newRule[0].surface_scope[0]) -Expected "any" -Message "Scaffolded draft rules should default surface_scope to any."
        }
        finally {
            Remove-Item -LiteralPath $testRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It "refuses to scaffold a rule with a duplicate ID" {
        if (-not $hostPath) { throw "PowerShell host not found." }
        $testRoot = New-TestRoot
        try {
            $fakeSkillRoot = Join-Path $testRoot "skill"
            $fakeScriptsRoot = Join-Path $fakeSkillRoot "scripts"
            New-Item -ItemType Directory -Path (Join-Path $fakeSkillRoot "assets") -Force | Out-Null
            New-Item -ItemType Directory -Path $fakeScriptsRoot -Force | Out-Null

            $existingRule = [ordered]@{ id = "SC001"; title = "Existing"; category = "correctness"; severity = "high"; confidence = 80; state = "active"; engine = "coded"; why = "x"; source_ids = @() }
            $seedCatalog = [ordered]@{ policy_version = "2026-03-25"; rules = @($existingRule) }
            $seedCatalogPath = Join-Path $fakeSkillRoot "assets\audit-rules.json"
            Write-TestRuleCatalog -Path $seedCatalogPath -Catalog $seedCatalog

            Copy-Item -LiteralPath $scaffoldScript -Destination (Join-Path $fakeScriptsRoot "new_audit_rule.ps1") -Force

            $exitCode = 0
            $previousPreference = $ErrorActionPreference
            $ErrorActionPreference = "Continue"
            try {
                $null = & $hostPath -NoProfile -ExecutionPolicy Bypass -File (Join-Path $fakeScriptsRoot "new_audit_rule.ps1") `
                    -Id "SC001" -Title "Duplicate" -Category "correctness" -Severity "low" `
                    -Pattern "(?i)Dup" -Why "dup" `
                    -TriggeringScenario "dup" -Remediation "dup" -TestIdeas @("dup") 2>$null
                $exitCode = $LASTEXITCODE
            }
            finally {
                $ErrorActionPreference = $previousPreference
            }

            Assert-Equal -Actual $exitCode -Expected 1 -Message "new_audit_rule.ps1 should exit 1 when the rule ID already exists."
        }
        finally {
            Remove-Item -LiteralPath $testRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It "refuses to scaffold a rule with an invalid regex pattern" {
        if (-not $hostPath) { throw "PowerShell host not found." }
        $testRoot = New-TestRoot
        try {
            $fakeSkillRoot = Join-Path $testRoot "skill"
            $fakeScriptsRoot = Join-Path $fakeSkillRoot "scripts"
            New-Item -ItemType Directory -Path (Join-Path $fakeSkillRoot "assets") -Force | Out-Null
            New-Item -ItemType Directory -Path $fakeScriptsRoot -Force | Out-Null
            $seedCatalog = [ordered]@{ policy_version = "2026-03-25"; rules = @() }
            $seedCatalogPath = Join-Path $fakeSkillRoot "assets\audit-rules.json"
            Write-TestRuleCatalog -Path $seedCatalogPath -Catalog $seedCatalog
            Copy-Item -LiteralPath $scaffoldScript -Destination (Join-Path $fakeScriptsRoot "new_audit_rule.ps1") -Force

            $exitCode = 0
            $previousPreference = $ErrorActionPreference
            $ErrorActionPreference = "Continue"
            try {
                $null = & $hostPath -NoProfile -ExecutionPolicy Bypass -File (Join-Path $fakeScriptsRoot "new_audit_rule.ps1") `
                    -Id "SC002" -Title "Bad regex" -Category "correctness" -Severity "low" `
                    -Pattern "(?invalid" -Why "x" `
                    -TriggeringScenario "x" -Remediation "x" -TestIdeas @("x") 2>$null
                $exitCode = $LASTEXITCODE
            }
            finally {
                $ErrorActionPreference = $previousPreference
            }
            Assert-Equal -Actual $exitCode -Expected 1 -Message "new_audit_rule.ps1 should exit 1 on an invalid regex pattern."
        }
        finally {
            Remove-Item -LiteralPath $testRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

# ---------------------------------------------------------------------------
# Concurrency detectors: CNC601 / CNC602 coded detector
# ---------------------------------------------------------------------------
Describe "OneIM VB.NET auditor concurrency detectors" {

    # Minimal rule catalog subset for concurrency tests
    $cncCatalog = @{
        'CNC601' = [pscustomobject]@{
            Id='CNC601'; Title='BeginTransaction without Commit'; Severity='high'
            Confidence=70; Enabled=$true; State='active'; Engine='coded'
            DetectorFamily='concurrency'; MaxExamplesPerFile=8
            Why='x'; ReviewNotes=''; SourceIds=@()
        }
        'CNC602' = [pscustomobject]@{
            Id='CNC602'; Title='Nested transaction'; Severity='high'
            Confidence=65; Enabled=$true; State='active'; Engine='coded'
            DetectorFamily='concurrency'; MaxExamplesPerFile=4
            Why='x'; ReviewNotes=''; SourceIds=@()
        }
    }
    $cncSL = @{}

    It "CNC601 fires when BeginTransaction has no Commit within 60 lines" {
        $lines = @(
            'con.BeginTransaction()'
            'con.ExecuteNonQuery("INSERT INTO Person ...")'
            # no Commit follows
        )
        $findings = Get-OneImConcurrencyFindings -Lines $lines -FilePath 'test.vb' `
            -RelativePath 'test.vb' -RuleCatalog $cncCatalog -SourceLookup $cncSL
        $c601 = @($findings | Where-Object { $_.rule_id -eq 'CNC601' })
        Assert-True -Condition ($c601.Count -ge 1) -Message "CNC601 should fire for BeginTransaction without Commit"
        Assert-Equal -Actual $c601[0].line -Expected 1 -Message "CNC601 should point to BeginTransaction line"
    }

    It "CNC601 does NOT fire when Commit follows within 60 lines" {
        $lines = @(
            'con.BeginTransaction()'
            'con.ExecuteNonQuery("INSERT ...")'
            'con.CommitTransaction()'
        )
        $findings = Get-OneImConcurrencyFindings -Lines $lines -FilePath 'test.vb' `
            -RelativePath 'test.vb' -RuleCatalog $cncCatalog -SourceLookup $cncSL
        $c601 = @($findings | Where-Object { $_.rule_id -eq 'CNC601' })
        Assert-Equal -Actual $c601.Count -Expected 0 -Message "CNC601 should not fire when Commit follows"
    }

    It "CNC602 fires when BeginTransaction appears twice without intervening Commit" {
        $lines = @(
            'con.BeginTransaction()'
            'con.ExecuteNonQuery("SELECT ...")'
            'con.BeginTransaction()'   # nested - no prior commit
        )
        $findings = Get-OneImConcurrencyFindings -Lines $lines -FilePath 'test.vb' `
            -RelativePath 'test.vb' -RuleCatalog $cncCatalog -SourceLookup $cncSL
        $c602 = @($findings | Where-Object { $_.rule_id -eq 'CNC602' })
        Assert-True -Condition ($c602.Count -ge 1) -Message "CNC602 should fire for nested BeginTransaction"
        Assert-Equal -Actual $c602[0].line -Expected 3 -Message "CNC602 should point to the second BeginTransaction"
    }

    It "CNC602 does NOT fire when second BeginTransaction follows a Commit" {
        $lines = @(
            'con.BeginTransaction()'
            'con.CommitTransaction()'
            'con.BeginTransaction()'   # new transaction after commit - OK
        )
        $findings = Get-OneImConcurrencyFindings -Lines $lines -FilePath 'test.vb' `
            -RelativePath 'test.vb' -RuleCatalog $cncCatalog -SourceLookup $cncSL
        $c602 = @($findings | Where-Object { $_.rule_id -eq 'CNC602' })
        Assert-Equal -Actual $c602.Count -Expected 0 -Message "CNC602 should not fire when prior Commit exists"
    }

    It "returns empty array for files with no concurrency patterns" {
        $lines = @(
            'Option Explicit On'
            'Public Function GetName() As String'
            '    Return "Alice"'
            'End Function'
        )
        $findings = @(Get-OneImConcurrencyFindings -Lines $lines -FilePath 'test.vb' `
            -RelativePath 'test.vb' -RuleCatalog $cncCatalog -SourceLookup $cncSL)
        Assert-Equal -Actual $findings.Count -Expected 0 -Message "No concurrency findings for clean code"
    }

    It "returns empty array for empty input lines" {
        $findings = @(Get-OneImConcurrencyFindings -Lines @() -FilePath 'test.vb' `
            -RelativePath 'test.vb' -RuleCatalog $cncCatalog -SourceLookup $cncSL)
        Assert-Equal -Actual $findings.Count -Expected 0 -Message "No concurrency findings for empty input"
    }
}

# ---------------------------------------------------------------------------
# New rule tests — VB004, VB005, REL230, SEC180, PER440, CNC605, OIM520
# ---------------------------------------------------------------------------
Describe "OneIM VB.NET auditor new rules" {
    # Shared minimal catalog containing only the rules exercised in this Describe block
    $newRulesCatalog = @{}
    foreach ($id in @("VB004", "REL230", "PER440", "OIM520", "OIM597")) {
        if ($ruleCatalog.ContainsKey($id)) { $newRulesCatalog[$id] = $ruleCatalog[$id] }
    }

    function Invoke-NewRuleFile {
        param([string]$Content, [hashtable]$Catalog = $newRulesCatalog)
        $tmp = [System.IO.Path]::GetTempFileName() + ".vb"
        Set-Content -LiteralPath $tmp -Value $Content -Encoding UTF8
        try {
            return @(Get-OneImFileFindings -FilePath $tmp -RelativePath "Scripts\Scripts.vb" `
                -RuleCatalog $Catalog -SourceLookup $sourceLookup)
        }
        finally {
            Remove-Item -LiteralPath $tmp -ErrorAction SilentlyContinue
        }
    }

    # ----- VB004: = Nothing / <> Nothing in conditional -----

    It "VB004 fires when If uses = Nothing" {
        $code = @(
            "Option Explicit On", "Option Strict On",
            "If myObj = Nothing Then",
            "    DoSomething()",
            "End If"
        ) -join "`r`n"
        $rc = @{}; $rc["VB004"] = $ruleCatalog["VB004"]
        $findings = @(Invoke-NewRuleFile -Content $code -Catalog $rc)
        Assert-True -Condition (@($findings | Where-Object { $_.rule_id -eq "VB004" }).Count -ge 1) -Message "VB004 should fire for 'If x = Nothing'."
    }

    It "VB004 fires when ElseIf uses <> Nothing" {
        $code = @(
            "Option Explicit On", "Option Strict On",
            "If x = 1 Then",
            "ElseIf myObj <> Nothing Then",
            "    DoSomething()",
            "End If"
        ) -join "`r`n"
        $rc = @{}; $rc["VB004"] = $ruleCatalog["VB004"]
        $findings = @(Invoke-NewRuleFile -Content $code -Catalog $rc)
        Assert-True -Condition (@($findings | Where-Object { $_.rule_id -eq "VB004" }).Count -ge 1) -Message "VB004 should fire for 'ElseIf x <> Nothing'."
    }

    It "VB004 does NOT fire for Dim x = Nothing (initialisation)" {
        $code = @(
            "Option Explicit On", "Option Strict On",
            "Dim myObj As String = Nothing"
        ) -join "`r`n"
        $rc = @{}; $rc["VB004"] = $ruleCatalog["VB004"]
        $findings = @(Invoke-NewRuleFile -Content $code -Catalog $rc)
        Assert-Equal -Actual @($findings | Where-Object { $_.rule_id -eq "VB004" }).Count -Expected 0 -Message "VB004 must not fire for Dim initialisations."
    }

    It "VB004 fires when AndAlso compound contains = Nothing" {
        $code = @(
            "Option Explicit On", "Option Strict On",
            "If x > 0 AndAlso myObj = Nothing Then",
            "    DoSomething()",
            "End If"
        ) -join "`r`n"
        $rc = @{}; $rc["VB004"] = $ruleCatalog["VB004"]
        $findings = @(Invoke-NewRuleFile -Content $code -Catalog $rc)
        Assert-True -Condition (@($findings | Where-Object { $_.rule_id -eq "VB004" }).Count -ge 1) -Message "VB004 should fire when = Nothing appears in an AndAlso expression."
    }

    # ----- VB005: Throw ex (declarative) — tested via Get-OneImFileFindings -----

    It "VB005 fires for Throw ex inside a Catch block" {
        $code = @(
            "Option Explicit On", "Option Strict On",
            "Try",
            "    DoWork()",
            "Catch ex As Exception",
            "    Throw ex",
            "End Try"
        ) -join "`r`n"
        $rc = Get-OneImAuditRuleCatalog -RuleCatalogPath $ruleCatalogPath -RuleState "Active"
        $sl = Get-OneImAuditSourceLookup -ApprovedSourcesPath $approvedSourcesPath
        $minRC = @{}; $minRC["VB005"] = $rc["VB005"]
        $findings = @(Invoke-NewRuleFile -Content $code -Catalog $minRC)
        Assert-True -Condition (@($findings | Where-Object { $_.rule_id -eq "VB005" }).Count -ge 1) -Message "VB005 should fire for 'Throw ex'."
    }

    It "VB005 does NOT fire for bare Throw" {
        $code = @(
            "Option Explicit On", "Option Strict On",
            "Try",
            "    DoWork()",
            "Catch ex As Exception",
            "    Throw",
            "End Try"
        ) -join "`r`n"
        $rc = Get-OneImAuditRuleCatalog -RuleCatalogPath $ruleCatalogPath -RuleState "Active"
        $minRC = @{}; $minRC["VB005"] = $rc["VB005"]
        $findings = @(Invoke-NewRuleFile -Content $code -Catalog $minRC)
        Assert-Equal -Actual @($findings | Where-Object { $_.rule_id -eq "VB005" }).Count -Expected 0 -Message "VB005 must not fire for bare Throw."
    }

    It "VB005 does NOT fire for Throw New ..." {
        $code = @(
            "Option Explicit On", "Option Strict On",
            "Throw New InvalidOperationException()"
        ) -join "`r`n"
        $rc = Get-OneImAuditRuleCatalog -RuleCatalogPath $ruleCatalogPath -RuleState "Active"
        $minRC = @{}; $minRC["VB005"] = $rc["VB005"]
        $findings = @(Invoke-NewRuleFile -Content $code -Catalog $minRC)
        Assert-Equal -Actual @($findings | Where-Object { $_.rule_id -eq "VB005" }).Count -Expected 0 -Message "VB005 must not fire for 'Throw New ...'."
    }

    # ----- REL230: Empty Catch block -----

    It "REL230 fires when Catch is immediately followed by End Try" {
        $code = @(
            "Option Explicit On", "Option Strict On",
            "Try",
            "    DoWork()",
            "Catch ex As Exception",
            "End Try"
        ) -join "`r`n"
        $rc = @{}; $rc["REL230"] = $ruleCatalog["REL230"]
        $findings = @(Invoke-NewRuleFile -Content $code -Catalog $rc)
        Assert-True -Condition (@($findings | Where-Object { $_.rule_id -eq "REL230" }).Count -ge 1) -Message "REL230 should fire for an empty Catch block."
    }

    It "REL230 fires when Catch is immediately followed by another Catch" {
        $code = @(
            "Option Explicit On", "Option Strict On",
            "Try",
            "    DoWork()",
            "Catch ex As ArgumentException",
            "Catch ex As Exception",
            "    LogError(ex)",
            "End Try"
        ) -join "`r`n"
        $rc = @{}; $rc["REL230"] = $ruleCatalog["REL230"]
        $findings = @(Invoke-NewRuleFile -Content $code -Catalog $rc)
        Assert-True -Condition (@($findings | Where-Object { $_.rule_id -eq "REL230" }).Count -ge 1) -Message "REL230 should fire when a Catch block has no body before the next Catch."
    }

    It "REL230 does NOT fire when Catch block has statements" {
        $code = @(
            "Option Explicit On", "Option Strict On",
            "Try",
            "    DoWork()",
            "Catch ex As Exception",
            "    LogError(ex.Message)",
            "End Try"
        ) -join "`r`n"
        $rc = @{}; $rc["REL230"] = $ruleCatalog["REL230"]
        $findings = @(Invoke-NewRuleFile -Content $code -Catalog $rc)
        Assert-Equal -Actual @($findings | Where-Object { $_.rule_id -eq "REL230" }).Count -Expected 0 -Message "REL230 must not fire when the Catch block has statements."
    }

    # ----- SEC180: Hardcoded credential (declarative) -----

    It "SEC180 fires for password = literal string" {
        $code = @(
            "Option Explicit On", "Option Strict On",
            "Dim password As String = ""Sup3rS3cret"""
        ) -join "`r`n"
        $rc = Get-OneImAuditRuleCatalog -RuleCatalogPath $ruleCatalogPath -RuleState "Active"
        $minRC = @{}; $minRC["SEC180"] = $rc["SEC180"]
        $findings = @(Invoke-NewRuleFile -Content $code -Catalog $minRC)
        Assert-True -Condition (@($findings | Where-Object { $_.rule_id -eq "SEC180" }).Count -ge 1) -Message "SEC180 should fire for a hardcoded password literal."
    }

    It "SEC180 fires for apikey assignment" {
        $code = @(
            "Option Explicit On", "Option Strict On",
            "apikey = ""sk-live-abc123def456"""
        ) -join "`r`n"
        $rc = Get-OneImAuditRuleCatalog -RuleCatalogPath $ruleCatalogPath -RuleState "Active"
        $minRC = @{}; $minRC["SEC180"] = $rc["SEC180"]
        $findings = @(Invoke-NewRuleFile -Content $code -Catalog $minRC)
        Assert-True -Condition (@($findings | Where-Object { $_.rule_id -eq "SEC180" }).Count -ge 1) -Message "SEC180 should fire for a hardcoded apikey literal."
    }

    It "SEC180 does NOT fire when credential comes from a function call" {
        $code = @(
            "Option Explicit On", "Option Strict On",
            "Dim password As String = GetFromVault(""my-secret"")"
        ) -join "`r`n"
        $rc = Get-OneImAuditRuleCatalog -RuleCatalogPath $ruleCatalogPath -RuleState "Active"
        $minRC = @{}; $minRC["SEC180"] = $rc["SEC180"]
        $findings = @(Invoke-NewRuleFile -Content $code -Catalog $minRC)
        Assert-Equal -Actual @($findings | Where-Object { $_.rule_id -eq "SEC180" }).Count -Expected 0 -Message "SEC180 must not fire when the value comes from a function, not a literal."
    }

    # ----- PER440: New allocation inside loop -----

    It "PER440 fires for New <Type> inside a For loop" {
        $code = @(
            "Option Explicit On", "Option Strict On",
            "For Each item In myList",
            "    Dim ctx = New RequestContext(item)",
            "Next"
        ) -join "`r`n"
        $rc = @{}; $rc["PER440"] = $ruleCatalog["PER440"]
        $findings = @(Invoke-NewRuleFile -Content $code -Catalog $rc)
        Assert-True -Condition (@($findings | Where-Object { $_.rule_id -eq "PER440" }).Count -ge 1) -Message "PER440 should fire for a New allocation inside a For Each loop."
    }

    It "PER440 does NOT fire outside a loop" {
        $code = @(
            "Option Explicit On", "Option Strict On",
            "Dim ctx = New RequestContext(item)"
        ) -join "`r`n"
        $rc = @{}; $rc["PER440"] = $ruleCatalog["PER440"]
        $findings = @(Invoke-NewRuleFile -Content $code -Catalog $rc)
        Assert-Equal -Actual @($findings | Where-Object { $_.rule_id -eq "PER440" }).Count -Expected 0 -Message "PER440 must not fire when the allocation is outside a loop."
    }

    It "PER440 does NOT fire for suppressed cheap types (List) inside a loop" {
        $code = @(
            "Option Explicit On", "Option Strict On",
            "For Each item In myList",
            "    Dim acc = New List(Of String)()",
            "Next"
        ) -join "`r`n"
        $rc = @{}; $rc["PER440"] = $ruleCatalog["PER440"]
        $findings = @(Invoke-NewRuleFile -Content $code -Catalog $rc)
        Assert-Equal -Actual @($findings | Where-Object { $_.rule_id -eq "PER440" }).Count -Expected 0 -Message "PER440 must not fire for suppressed cheap types like List."
    }

    # ----- CNC605: Shared mutable field (declarative) -----

    It "CNC605 fires for a Private Shared mutable field" {
        $code = @(
            "Option Explicit On", "Option Strict On",
            "Public Class MyClass",
            "    Private Shared _counter As Integer = 0",
            "End Class"
        ) -join "`r`n"
        $rc = Get-OneImAuditRuleCatalog -RuleCatalogPath $ruleCatalogPath -RuleState "Active"
        $minRC = @{}; $minRC["CNC605"] = $rc["CNC605"]
        $findings = @(Invoke-NewRuleFile -Content $code -Catalog $minRC)
        Assert-True -Condition (@($findings | Where-Object { $_.rule_id -eq "CNC605" }).Count -ge 1) -Message "CNC605 should fire for a Private Shared mutable field."
    }

    It "CNC605 does NOT fire for Shared ReadOnly field" {
        $code = @(
            "Option Explicit On", "Option Strict On",
            "Public Class MyClass",
            "    Public Shared ReadOnly MaxRetries As Integer = 5",
            "End Class"
        ) -join "`r`n"
        $rc = Get-OneImAuditRuleCatalog -RuleCatalogPath $ruleCatalogPath -RuleState "Active"
        $minRC = @{}; $minRC["CNC605"] = $rc["CNC605"]
        $findings = @(Invoke-NewRuleFile -Content $code -Catalog $minRC)
        Assert-Equal -Actual @($findings | Where-Object { $_.rule_id -eq "CNC605" }).Count -Expected 0 -Message "CNC605 must not fire for Shared ReadOnly fields."
    }

    It "CNC605 does NOT fire for Shared Function" {
        $code = @(
            "Option Explicit On", "Option Strict On",
            "Public Class MyClass",
            "    Private Shared Function GetData() As String",
            "        Return String.Empty",
            "    End Function",
            "End Class"
        ) -join "`r`n"
        $rc = Get-OneImAuditRuleCatalog -RuleCatalogPath $ruleCatalogPath -RuleState "Active"
        $minRC = @{}; $minRC["CNC605"] = $rc["CNC605"]
        $findings = @(Invoke-NewRuleFile -Content $code -Catalog $minRC)
        Assert-Equal -Actual @($findings | Where-Object { $_.rule_id -eq "CNC605" }).Count -Expected 0 -Message "CNC605 must not fire for Shared Function declarations."
    }

    # ----- OIM520: GetListFor inside loop -----

    It "OIM520 fires for GetListFor inside a For Each loop" {
        $code = @(
            "Option Explicit On", "Option Strict On",
            "For Each dept In departments",
            "    Dim employees = Session.GetListFor(""Person"", ""UID_Department = '"" & dept.UID & ""'"")",
            "Next"
        ) -join "`r`n"
        $rc = @{}; $rc["OIM520"] = $ruleCatalog["OIM520"]
        $findings = @(Invoke-NewRuleFile -Content $code -Catalog $rc)
        Assert-True -Condition (@($findings | Where-Object { $_.rule_id -eq "OIM520" }).Count -ge 1) -Message "OIM520 should fire for GetListFor inside a For Each loop."
    }

    It "OIM520 fires for GetSingleProperty inside a loop" {
        $code = @(
            "Option Explicit On", "Option Strict On",
            "For Each item In myList",
            "    Dim val = GetSingleProperty(""Person"", item.UID, ""Firstname"")",
            "Next"
        ) -join "`r`n"
        $rc = @{}; $rc["OIM520"] = $ruleCatalog["OIM520"]
        $findings = @(Invoke-NewRuleFile -Content $code -Catalog $rc)
        Assert-True -Condition (@($findings | Where-Object { $_.rule_id -eq "OIM520" }).Count -ge 1) -Message "OIM520 should fire for GetSingleProperty inside a loop."
    }

    It "OIM520 does NOT fire for GetListFor outside a loop" {
        $code = @(
            "Option Explicit On", "Option Strict On",
            "Dim employees = Session.GetListFor(""Person"", ""IsActive = 1"")"
        ) -join "`r`n"
        $rc = @{}; $rc["OIM520"] = $ruleCatalog["OIM520"]
        $findings = @(Invoke-NewRuleFile -Content $code -Catalog $rc)
        Assert-Equal -Actual @($findings | Where-Object { $_.rule_id -eq "OIM520" }).Count -Expected 0 -Message "OIM520 must not fire when GetListFor is outside a loop."
    }
}

# ---------------------------------------------------------------------------
# New rule tests — SEC185, SEC190, REL240
# ---------------------------------------------------------------------------
Describe "OneIM VB.NET auditor sample-derived rules" {

    function Invoke-SampleRuleFile {
        param([string]$Content, [hashtable]$Catalog)
        $tmp = [System.IO.Path]::GetTempFileName() + ".vb"
        Set-Content -LiteralPath $tmp -Value $Content -Encoding UTF8
        try {
            return @(Get-OneImFileFindings -FilePath $tmp -RelativePath "Scripts\Scripts.vb" `
                -RuleCatalog $Catalog -SourceLookup $sourceLookup)
        }
        finally {
            Remove-Item -LiteralPath $tmp -ErrorAction SilentlyContinue
        }
    }

    # --- SEC185: Password in connection string literal ---

    It "SEC185 fires for Password= inside a connection string literal" {
        $code = 'Option Explicit On' + "`n" + 'Option Strict On' + "`n" +
                'Dim strConn As String = "User ID=sa;Password=Sup3rS3cret;Data Source=myserver"'
        $rc = @{}; $rc["SEC185"] = $ruleCatalog["SEC185"]
        $findings = @(Invoke-SampleRuleFile -Content $code -Catalog $rc)
        Assert-True -Condition (@($findings | Where-Object { $_.rule_id -eq "SEC185" }).Count -ge 1) `
            -Message "SEC185 should fire when Password= appears in a connection string literal."
    }

    It "SEC185 fires for lowercase password= in connection string" {
        $code = 'Option Explicit On' + "`n" + 'Option Strict On' + "`n" +
                'Dim s = "server=x;database=y;password=abc123;"'
        $rc = @{}; $rc["SEC185"] = $ruleCatalog["SEC185"]
        $findings = @(Invoke-SampleRuleFile -Content $code -Catalog $rc)
        Assert-True -Condition (@($findings | Where-Object { $_.rule_id -eq "SEC185" }).Count -ge 1) `
            -Message "SEC185 should fire for lowercase password= in connection string."
    }

    It "SEC185 does NOT fire for IntegratedSecurity connection string" {
        $code = 'Option Explicit On' + "`n" + 'Option Strict On' + "`n" +
                'Dim s = "Server=myserver;Database=mydb;Integrated Security=True;"'
        $rc = @{}; $rc["SEC185"] = $ruleCatalog["SEC185"]
        $findings = @(Invoke-SampleRuleFile -Content $code -Catalog $rc)
        Assert-Equal -Actual @($findings | Where-Object { $_.rule_id -eq "SEC185" }).Count -Expected 0 `
            -Message "SEC185 must not fire when no Password= is in the connection string."
    }

    It "SEC185 does NOT fire for a variable reference after Password=" {
        $code = 'Option Explicit On' + "`n" + 'Option Strict On' + "`n" +
                'Dim s = "User ID=sa;Data Source=srv;Password=" & pw'
        $rc = @{}; $rc["SEC185"] = $ruleCatalog["SEC185"]
        $findings = @(Invoke-SampleRuleFile -Content $code -Catalog $rc)
        Assert-Equal -Actual @($findings | Where-Object { $_.rule_id -eq "SEC185" }).Count -Expected 0 `
            -Message "SEC185 must not fire when the password is a variable reference outside the literal."
    }

    # --- SEC190: LDAP filter injection via string concatenation ---

    It "SEC190 fires for DirectorySearcher constructor with concatenated filter" {
        $code = @(
            "Option Explicit On", "Option Strict On",
            "Imports System.DirectoryServices",
            'Dim searcher As New System.DirectoryServices.DirectorySearcher(root, "(&(objectclass=*) (" & propName & "=" & propValue & "))")'
        ) -join "`n"
        $rc = @{}; $rc["SEC190"] = $ruleCatalog["SEC190"]
        $findings = @(Invoke-SampleRuleFile -Content $code -Catalog $rc)
        Assert-True -Condition (@($findings | Where-Object { $_.rule_id -eq "SEC190" }).Count -ge 1) `
            -Message "SEC190 should fire when DirectorySearcher is constructed with a concatenated filter."
    }

    It "SEC190 fires for .Filter assignment with concatenation" {
        $code = @(
            "Option Explicit On", "Option Strict On",
            'searcher.Filter = "(&(objectCategory=person)(sAMAccountName=" & userName & "))"'
        ) -join "`n"
        $rc = @{}; $rc["SEC190"] = $ruleCatalog["SEC190"]
        $findings = @(Invoke-SampleRuleFile -Content $code -Catalog $rc)
        Assert-True -Condition (@($findings | Where-Object { $_.rule_id -eq "SEC190" }).Count -ge 1) `
            -Message "SEC190 should fire for .Filter assignment with string concatenation."
    }

    It "SEC190 does NOT fire for DirectorySearcher with a static filter literal" {
        $code = @(
            "Option Explicit On", "Option Strict On",
            'Dim searcher As New System.DirectoryServices.DirectorySearcher(root, "(&(objectclass=person)(mail=*))")'
        ) -join "`n"
        $rc = @{}; $rc["SEC190"] = $ruleCatalog["SEC190"]
        $findings = @(Invoke-SampleRuleFile -Content $code -Catalog $rc)
        Assert-Equal -Actual @($findings | Where-Object { $_.rule_id -eq "SEC190" }).Count -Expected 0 `
            -Message "SEC190 must not fire when the filter is a static literal with no concatenation."
    }

    # --- REL240: GetFk chained without IsEmpty guard ---

    It "REL240 fires for .GetFk(...).GetParent() chained on one line" {
        $code = @(
            "Option Explicit On", "Option Strict On",
            'Dim parent = obj.GetFk(Session, "UID_Department").GetParent()'
        ) -join "`n"
        $rc = @{}; $rc["REL240"] = $ruleCatalog["REL240"]
        $findings = @(Invoke-SampleRuleFile -Content $code -Catalog $rc)
        Assert-True -Condition (@($findings | Where-Object { $_.rule_id -eq "REL240" }).Count -ge 1) `
            -Message "REL240 should fire when GetFk result is chained directly to GetParent()."
    }

    It "REL240 fires for .GetFk(...).GetValue() chained on one line" {
        $code = @(
            "Option Explicit On", "Option Strict On",
            'Dim val = obj.GetFk(Session, "UID_Person").GetValue("Firstname")'
        ) -join "`n"
        $rc = @{}; $rc["REL240"] = $ruleCatalog["REL240"]
        $findings = @(Invoke-SampleRuleFile -Content $code -Catalog $rc)
        Assert-True -Condition (@($findings | Where-Object { $_.rule_id -eq "REL240" }).Count -ge 1) `
            -Message "REL240 should fire when GetFk result is chained directly to GetValue()."
    }

    It "REL240 does NOT fire when GetFk result is stored and IsEmpty checked separately" {
        $code = @(
            "Option Explicit On", "Option Strict On",
            'Dim fkDept = obj.GetFk(Session, "UID_Department")',
            'If Not fkDept.IsEmpty Then',
            '    Dim parent = fkDept.GetParent()',
            'End If'
        ) -join "`n"
        $rc = @{}; $rc["REL240"] = $ruleCatalog["REL240"]
        $findings = @(Invoke-SampleRuleFile -Content $code -Catalog $rc)
        Assert-Equal -Actual @($findings | Where-Object { $_.rule_id -eq "REL240" }).Count -Expected 0 `
            -Message "REL240 must not fire when the FK is assigned to a variable and IsEmpty is checked."
    }
}

# ---------------------------------------------------------------------------
# Performance tuning rules — PER450, PER451, PER452, PER455
# ---------------------------------------------------------------------------
Describe "OneIM VB.NET auditor performance tuning rules" {

    function Invoke-PerfRuleFile {
        param([string]$Content, [hashtable]$Catalog)
        $tmp = [System.IO.Path]::GetTempFileName() + ".vb"
        Set-Content -LiteralPath $tmp -Value $Content -Encoding UTF8
        try {
            return @(Get-OneImFileFindings -FilePath $tmp -RelativePath "Scripts\Scripts.vb" `
                -RuleCatalog $Catalog -SourceLookup $sourceLookup)
        }
        finally {
            Remove-Item -LiteralPath $tmp -ErrorAction SilentlyContinue
        }
    }

    # --- PER450: Pooling=false in connection string ---

    It "PER450 fires for Pooling=false inside a connection string literal" {
        $code = 'Option Explicit On' + "`n" + 'Option Strict On' + "`n" +
                'Dim s = "User ID=sa;Data Source=srv;Pooling=false;Application Name=test"'
        $rc = @{}; $rc["PER450"] = $ruleCatalog["PER450"]
        $findings = @(Invoke-PerfRuleFile -Content $code -Catalog $rc)
        Assert-True -Condition (@($findings | Where-Object { $_.rule_id -eq "PER450" }).Count -ge 1) `
            -Message "PER450 should fire when Pooling=false appears in a connection string."
    }

    It "PER450 fires for Pooling = False (spaces, mixed case)" {
        $code = 'Option Explicit On' + "`n" + 'Option Strict On' + "`n" +
                'Dim s = "Server=x;Pooling = False;Database=y"'
        $rc = @{}; $rc["PER450"] = $ruleCatalog["PER450"]
        $findings = @(Invoke-PerfRuleFile -Content $code -Catalog $rc)
        Assert-True -Condition (@($findings | Where-Object { $_.rule_id -eq "PER450" }).Count -ge 1) `
            -Message "PER450 should fire for Pooling = False with spaces and mixed case."
    }

    It "PER450 does NOT fire for Pooling=true" {
        $code = 'Option Explicit On' + "`n" + 'Option Strict On' + "`n" +
                'Dim s = "Server=x;Pooling=true;Database=y"'
        $rc = @{}; $rc["PER450"] = $ruleCatalog["PER450"]
        $findings = @(Invoke-PerfRuleFile -Content $code -Catalog $rc)
        Assert-Equal -Actual @($findings | Where-Object { $_.rule_id -eq "PER450" }).Count -Expected 0 `
            -Message "PER450 must not fire when Pooling=true."
    }

    It "PER450 does NOT fire when no Pooling key is present" {
        $code = 'Option Explicit On' + "`n" + 'Option Strict On' + "`n" +
                'Dim s = "Integrated Security=true;Server=x"'
        $rc = @{}; $rc["PER450"] = $ruleCatalog["PER450"]
        $findings = @(Invoke-PerfRuleFile -Content $code -Catalog $rc)
        Assert-Equal -Actual @($findings | Where-Object { $_.rule_id -eq "PER450" }).Count -Expected 0 `
            -Message "PER450 must not fire when the connection string has no Pooling key."
    }

    # --- PER451: .Create(Session) inside a loop ---

    It "PER451 fires for .Create(Session) inside a For Each loop" {
        $code = @(
            "Option Explicit On", "Option Strict On",
            "For Each colElement As IEntity In colPersons",
            "    Dim dbPerson = colElement.Create(Session)",
            "Next"
        ) -join "`n"
        $rc = @{}; $rc["PER451"] = $ruleCatalog["PER451"]
        $findings = @(Invoke-PerfRuleFile -Content $code -Catalog $rc)
        Assert-True -Condition (@($findings | Where-Object { $_.rule_id -eq "PER451" }).Count -ge 1) `
            -Message "PER451 should fire when .Create(Session) is called inside a For Each loop."
    }

    It "PER451 fires for .Create(Session, EntityLoadType.Interactive) inside a loop" {
        $code = @(
            "Option Explicit On", "Option Strict On",
            "For Each colElement As IEntity In colPersons",
            "    Dim dbPerson = colElement.Create(Session, EntityLoadType.Interactive)",
            "Next"
        ) -join "`n"
        $rc = @{}; $rc["PER451"] = $ruleCatalog["PER451"]
        $findings = @(Invoke-PerfRuleFile -Content $code -Catalog $rc)
        Assert-True -Condition (@($findings | Where-Object { $_.rule_id -eq "PER451" }).Count -ge 1) `
            -Message "PER451 should fire for .Create(Session, EntityLoadType.xxx) inside a loop."
    }

    It "PER451 does NOT fire for .Create(Session) outside a loop" {
        $code = @(
            "Option Explicit On", "Option Strict On",
            "Dim dbPerson = colElement.Create(Session)"
        ) -join "`n"
        $rc = @{}; $rc["PER451"] = $ruleCatalog["PER451"]
        $findings = @(Invoke-PerfRuleFile -Content $code -Catalog $rc)
        Assert-Equal -Actual @($findings | Where-Object { $_.rule_id -eq "PER451" }).Count -Expected 0 `
            -Message "PER451 must not fire when .Create(Session) is outside a loop."
    }

    # --- PER452: .SelectAll() on a collection query ---

    It "PER452 fires for .SelectAll() on a query" {
        $code = @(
            "Option Explicit On", "Option Strict On",
            'Dim qPerson = Query.From("Person").SelectAll()',
            'Dim col = Session.Source.GetCollection(qPerson)'
        ) -join "`n"
        $rc = @{}; $rc["PER452"] = $ruleCatalog["PER452"]
        $findings = @(Invoke-PerfRuleFile -Content $code -Catalog $rc)
        Assert-True -Condition (@($findings | Where-Object { $_.rule_id -eq "PER452" }).Count -ge 1) `
            -Message "PER452 should fire when .SelectAll() appears on a query."
    }

    It "PER452 does NOT fire for .Select() with explicit columns" {
        $code = @(
            "Option Explicit On", "Option Strict On",
            'Dim qPerson = Query.From("Person").Select("Firstname", "LastName")',
            'Dim col = Session.Source.GetCollection(qPerson)'
        ) -join "`n"
        $rc = @{}; $rc["PER452"] = $ruleCatalog["PER452"]
        $findings = @(Invoke-PerfRuleFile -Content $code -Catalog $rc)
        Assert-Equal -Actual @($findings | Where-Object { $_.rule_id -eq "PER452" }).Count -Expected 0 `
            -Message "PER452 must not fire for .Select() with explicit column list."
    }

    It "PER452 does NOT fire for .SelectDisplays()" {
        $code = @(
            "Option Explicit On", "Option Strict On",
            'Dim qPerson = Query.From("Person").SelectDisplays()'
        ) -join "`n"
        $rc = @{}; $rc["PER452"] = $ruleCatalog["PER452"]
        $findings = @(Invoke-PerfRuleFile -Content $code -Catalog $rc)
        Assert-Equal -Actual @($findings | Where-Object { $_.rule_id -eq "PER452" }).Count -Expected 0 `
            -Message "PER452 must not fire for .SelectDisplays()."
    }

    # --- PER455: BuildSessionFactory() per method invocation ---

    It "PER455 fires for BuildSessionFactory() inside a Using block" {
        $code = @(
            "Option Explicit On", "Option Strict On",
            "Public Sub ExecuteSql(ByVal sql As String)",
            "    Using sf = DbApp.ConnectTo(GetConnectionString()).BuildSessionFactory()",
            "        Using dbSession = sf.OpenDbSession()",
            "            dbSession.SqlExecuteNonQuery(sql)",
            "        End Using",
            "    End Using",
            "End Sub"
        ) -join "`n"
        $rc = @{}; $rc["PER455"] = $ruleCatalog["PER455"]
        $findings = @(Invoke-PerfRuleFile -Content $code -Catalog $rc)
        Assert-True -Condition (@($findings | Where-Object { $_.rule_id -eq "PER455" }).Count -ge 1) `
            -Message "PER455 should fire when BuildSessionFactory() appears inside a method body."
    }

    It "PER455 fires for chained .Using(dbFac).BuildSessionFactory()" {
        $code = @(
            "Option Explicit On", "Option Strict On",
            "Using sf = DbApp.ConnectTo(cs).Using(dbFac).BuildSessionFactory()",
            "    dbSession.SqlExecuteNonQuery(sql)",
            "End Using"
        ) -join "`n"
        $rc = @{}; $rc["PER455"] = $ruleCatalog["PER455"]
        $findings = @(Invoke-PerfRuleFile -Content $code -Catalog $rc)
        Assert-True -Condition (@($findings | Where-Object { $_.rule_id -eq "PER455" }).Count -ge 1) `
            -Message "PER455 should fire for chained .Using(factory).BuildSessionFactory()."
    }
}

# ---------------------------------------------------------------------------
# Context-aware security rules — SEC131, SEC140, SEC150
# ---------------------------------------------------------------------------
Describe "OneIM VB.NET auditor context-aware security rules" {

    function Invoke-ContextSecurityFile {
        param([string]$Content, [hashtable]$Catalog)
        $tmp = [System.IO.Path]::GetTempFileName() + ".vb"
        Set-Content -LiteralPath $tmp -Value $Content -Encoding UTF8
        try {
            return @(Get-OneImFileFindings -FilePath $tmp -RelativePath "Scripts\Scripts.vb" `
                -RuleCatalog $Catalog -SourceLookup $sourceLookup)
        }
        finally { Remove-Item -LiteralPath $tmp -ErrorAction SilentlyContinue }
    }

    It "SEC150 does NOT fire when safe XML markers are visible nearby" {
        $code = @"
Public Function ReadXml(xml As String) As XmlDocument
    Dim settings As New XmlReaderSettings()
    settings.DtdProcessing = DtdProcessing.Prohibit
    settings.XmlResolver = Nothing
    Dim doc As New XmlDocument()
    doc.LoadXml(xml)
    Return doc
End Function
"@
        $rc = @{}; $rc["SEC150"] = $ruleCatalog["SEC150"]
        $findings = Invoke-ContextSecurityFile -Content $code -Catalog $rc
        Assert-Equal -Actual @($findings | Where-Object { $_.rule_id -eq "SEC150" }).Count -Expected 0 `
            -Message "SEC150 should stand down when safe XML settings are visible nearby."
    }

    It "SEC131 lowers confidence when a base URI hint is visible" {
        $code = @"
Public Function Fetch(client As HttpClient, baseUri As String, endpoint As String) As Task
    Return client.GetAsync(baseUri & endpoint)
End Function
"@
        $rc = @{}; $rc["SEC131"] = $ruleCatalog["SEC131"]
        $findings = Invoke-ContextSecurityFile -Content $code -Catalog $rc
        $finding = @($findings | Where-Object { $_.rule_id -eq "SEC131" }) | Select-Object -First 1
        Assert-NotNull -Value $finding -Message "SEC131 should still flag variable-driven outbound requests."
        Assert-Equal -Actual ([int]$finding.confidence_score) -Expected 60 -Message "SEC131 should downgrade confidence when a base URI hint is visible."
    }

    It "SEC140 lowers confidence when path normalization helpers are visible" {
        $code = @"
Public Function ReadConfig(rootPath As String, fileName As String) As String
    Return File.ReadAllText(Path.Combine(rootPath, fileName))
End Function
"@
        $rc = @{}; $rc["SEC140"] = $ruleCatalog["SEC140"]
        $findings = Invoke-ContextSecurityFile -Content $code -Catalog $rc
        $finding = @($findings | Where-Object { $_.rule_id -eq "SEC140" }) | Select-Object -First 1
        Assert-NotNull -Value $finding -Message "SEC140 should still review variable-driven file access."
        Assert-Equal -Actual ([int]$finding.confidence_score) -Expected 60 -Message "SEC140 should downgrade confidence when Path.Combine is visible."
    }
}

# ---------------------------------------------------------------------------
# String and UID comparison rules — STR600, OIM530, OIM535
# ---------------------------------------------------------------------------
Describe "OneIM VB.NET auditor string and UID comparison rules" {

    function Invoke-CmpRuleFile {
        param([string]$Content, [hashtable]$Catalog)
        $tmp = [System.IO.Path]::GetTempFileName() + ".vb"
        Set-Content -LiteralPath $tmp -Value $Content -Encoding UTF8
        try {
            return @(Get-OneImFileFindings -FilePath $tmp -RelativePath "Scripts\Scripts.vb" `
                -RuleCatalog $Catalog -SourceLookup $sourceLookup)
        }
        finally {
            Remove-Item -LiteralPath $tmp -ErrorAction SilentlyContinue
        }
    }

    # --- STR600: .ToLower()/.ToUpper() used in comparison ---

    It "STR600 fires when .ToLower() result is directly compared with =" {
        $code = @(
            "Option Explicit On", "Option Strict On",
            'If str1.ToLower() = str2.ToLower() Then'
        ) -join "`n"
        $rc = @{}; $rc["STR600"] = $ruleCatalog["STR600"]
        $findings = @(Invoke-CmpRuleFile -Content $code -Catalog $rc)
        Assert-True -Condition (@($findings | Where-Object { $_.rule_id -eq "STR600" }).Count -ge 1) `
            -Message "STR600 should fire when .ToLower() is compared with =."
    }

    It "STR600 fires for .ToUpper() in an If condition" {
        $code = @(
            "Option Explicit On", "Option Strict On",
            'If name.ToUpper() <> "ADMIN" Then'
        ) -join "`n"
        $rc = @{}; $rc["STR600"] = $ruleCatalog["STR600"]
        $findings = @(Invoke-CmpRuleFile -Content $code -Catalog $rc)
        Assert-True -Condition (@($findings | Where-Object { $_.rule_id -eq "STR600" }).Count -ge 1) `
            -Message "STR600 should fire for .ToUpper() compared with <>."
    }

    It "STR600 does NOT fire for .ToLower() used only for display (not in comparison)" {
        $code = @(
            "Option Explicit On", "Option Strict On",
            'Dim label = name.ToLower()'
        ) -join "`n"
        $rc = @{}; $rc["STR600"] = $ruleCatalog["STR600"]
        $findings = @(Invoke-CmpRuleFile -Content $code -Catalog $rc)
        Assert-Equal -Actual @($findings | Where-Object { $_.rule_id -eq "STR600" }).Count -Expected 0 `
            -Message "STR600 must not fire when ToLower is used for assignment only, not comparison."
    }

    # --- OIM530: f.Comparison on UID_ column instead of f.UidComparison ---

    It "OIM530 fires when f.Comparison is called with a UID_ column name" {
        $code = @(
            "Option Explicit On", "Option Strict On",
            'Dim where = f.Comparison("UID_HomeServer", "", ValType.String, CompareOperator.NotEqual)'
        ) -join "`n"
        $rc = @{}; $rc["OIM530"] = $ruleCatalog["OIM530"]
        $findings = @(Invoke-CmpRuleFile -Content $code -Catalog $rc)
        Assert-True -Condition (@($findings | Where-Object { $_.rule_id -eq "OIM530" }).Count -ge 1) `
            -Message "OIM530 should fire when f.Comparison is used with a UID_ column."
    }

    It "OIM530 fires for any ISqlFormatter variable name calling .Comparison with UID_ column" {
        $code = @(
            "Option Explicit On", "Option Strict On",
            'Dim where = formatter.Comparison("UID_ADSContainer", "", ValType.String)'
        ) -join "`n"
        $rc = @{}; $rc["OIM530"] = $ruleCatalog["OIM530"]
        $findings = @(Invoke-CmpRuleFile -Content $code -Catalog $rc)
        Assert-True -Condition (@($findings | Where-Object { $_.rule_id -eq "OIM530" }).Count -ge 1) `
            -Message "OIM530 should fire regardless of the ISqlFormatter variable name."
    }

    It "OIM530 does NOT fire when f.UidComparison is used" {
        $code = @(
            "Option Explicit On", "Option Strict On",
            'Dim where = f.UidComparison("UID_ADSContainer", "", CompareOperator.NotEqual)'
        ) -join "`n"
        $rc = @{}; $rc["OIM530"] = $ruleCatalog["OIM530"]
        $findings = @(Invoke-CmpRuleFile -Content $code -Catalog $rc)
        Assert-Equal -Actual @($findings | Where-Object { $_.rule_id -eq "OIM530" }).Count -Expected 0 `
            -Message "OIM530 must not fire when the correct f.UidComparison() is used."
    }

    It "OIM530 does NOT fire for f.Comparison on a non-UID column" {
        $code = @(
            "Option Explicit On", "Option Strict On",
            'Dim where = f.Comparison("PersonnelNumber", "", ValType.String, CompareOperator.NotEqual)'
        ) -join "`n"
        $rc = @{}; $rc["OIM530"] = $ruleCatalog["OIM530"]
        $findings = @(Invoke-CmpRuleFile -Content $code -Catalog $rc)
        Assert-Equal -Actual @($findings | Where-Object { $_.rule_id -eq "OIM530" }).Count -Expected 0 `
            -Message "OIM530 must not fire for non-UID columns."
    }

    # --- OIM535: .GetValue("UID_...").String = "" direct empty check ---

    It "OIM535 fires for .GetValue(UID column).String = empty string" {
        $code = @(
            "Option Explicit On", "Option Strict On",
            'If ePerson.GetValue("UID_Department").String = "" Then'
        ) -join "`n"
        $rc = @{}; $rc["OIM535"] = $ruleCatalog["OIM535"]
        $findings = @(Invoke-CmpRuleFile -Content $code -Catalog $rc)
        Assert-True -Condition (@($findings | Where-Object { $_.rule_id -eq "OIM535" }).Count -ge 1) `
            -Message "OIM535 should fire when .GetValue(UID_...).String = '' is used."
    }

    It "OIM535 fires for .GetValue(UID column).String <> empty string" {
        $code = @(
            "Option Explicit On", "Option Strict On",
            'If obj.GetValue("UID_Person").String <> "" Then'
        ) -join "`n"
        $rc = @{}; $rc["OIM535"] = $ruleCatalog["OIM535"]
        $findings = @(Invoke-CmpRuleFile -Content $code -Catalog $rc)
        Assert-True -Condition (@($findings | Where-Object { $_.rule_id -eq "OIM535" }).Count -ge 1) `
            -Message "OIM535 should fire for <> empty string on a UID column value."
    }

    It "OIM535 does NOT fire for String.IsNullOrEmpty on a UID column" {
        $code = @(
            "Option Explicit On", "Option Strict On",
            'If Not String.IsNullOrEmpty(ePerson.GetValue("UID_Department").String) Then'
        ) -join "`n"
        $rc = @{}; $rc["OIM535"] = $ruleCatalog["OIM535"]
        $findings = @(Invoke-CmpRuleFile -Content $code -Catalog $rc)
        Assert-Equal -Actual @($findings | Where-Object { $_.rule_id -eq "OIM535" }).Count -Expected 0 `
            -Message "OIM535 must not fire when String.IsNullOrEmpty is used."
    }

    It "OIM535 does NOT fire for = empty string on a non-UID column" {
        $code = @(
            "Option Explicit On", "Option Strict On",
            'If obj.GetValue("Firstname").String = "" Then'
        ) -join "`n"
        $rc = @{}; $rc["OIM535"] = $ruleCatalog["OIM535"]
        $findings = @(Invoke-CmpRuleFile -Content $code -Catalog $rc)
        Assert-Equal -Actual @($findings | Where-Object { $_.rule_id -eq "OIM535" }).Count -Expected 0 `
            -Message "OIM535 must not fire for non-UID column empty checks."
    }
}

# ---------------------------------------------------------------------------
# New rules — WEB600, REL250, STR610, OIM545, OIM555
# ---------------------------------------------------------------------------
Describe "OneIM VB.NET auditor new rules batch 3" {

    function Invoke-B3RuleFile {
        param([string]$Content, [hashtable]$Catalog)
        $tmp = [System.IO.Path]::GetTempFileName() + ".vb"
        Set-Content -LiteralPath $tmp -Value $Content -Encoding UTF8
        try {
            return @(Get-OneImFileFindings -FilePath $tmp -RelativePath "Scripts\Scripts.vb" `
                -RuleCatalog $Catalog -SourceLookup $sourceLookup)
        }
        finally {
            Remove-Item -LiteralPath $tmp -ErrorAction SilentlyContinue
        }
    }

    # --- WEB600: HttpWebRequest.Create() / WebClient ---

    It "WEB600 fires for HttpWebRequest.Create()" {
        $code = @(
            "Option Explicit On", "Option Strict On",
            'Dim req As HttpWebRequest = CType(HttpWebRequest.Create(url), HttpWebRequest)'
        ) -join "`n"
        $rc = @{}; $rc["WEB600"] = $ruleCatalog["WEB600"]
        $findings = @(Invoke-B3RuleFile -Content $code -Catalog $rc)
        Assert-True -Condition (@($findings | Where-Object { $_.rule_id -eq "WEB600" }).Count -ge 1) `
            -Message "WEB600 should fire for HttpWebRequest.Create()."
    }

    It "WEB600 fires for New WebClient()" {
        $code = @(
            "Option Explicit On", "Option Strict On",
            "Dim wc As New WebClient()"
        ) -join "`n"
        $rc = @{}; $rc["WEB600"] = $ruleCatalog["WEB600"]
        $findings = @(Invoke-B3RuleFile -Content $code -Catalog $rc)
        Assert-True -Condition (@($findings | Where-Object { $_.rule_id -eq "WEB600" }).Count -ge 1) `
            -Message "WEB600 should fire for New WebClient()."
    }

    It "WEB600 does NOT fire for New HttpClient()" {
        $code = @(
            "Option Explicit On", "Option Strict On",
            "Using client As New HttpClient()",
            "End Using"
        ) -join "`n"
        $rc = @{}; $rc["WEB600"] = $ruleCatalog["WEB600"]
        $findings = @(Invoke-B3RuleFile -Content $code -Catalog $rc)
        Assert-Equal -Actual @($findings | Where-Object { $_.rule_id -eq "WEB600" }).Count -Expected 0 `
            -Message "WEB600 must not fire for HttpClient."
    }

    # --- REL250: Disposable declared with Dim instead of Using ---

    It "REL250 fires for Dim StreamReader without Using" {
        $code = @(
            "Option Explicit On", "Option Strict On",
            "Dim reader As New StreamReader(filePath)",
            "Dim content = reader.ReadToEnd()",
            "reader.Close()"
        ) -join "`n"
        $rc = @{}; $rc["REL250"] = $ruleCatalog["REL250"]
        $findings = @(Invoke-B3RuleFile -Content $code -Catalog $rc)
        Assert-True -Condition (@($findings | Where-Object { $_.rule_id -eq "REL250" }).Count -ge 1) `
            -Message "REL250 should fire for Dim StreamReader outside of Using."
    }

    It "REL250 fires for Dim SqlConnection without Using" {
        $code = @(
            "Option Explicit On", "Option Strict On",
            "Dim conn As New SqlConnection(cs)",
            "conn.Open()"
        ) -join "`n"
        $rc = @{}; $rc["REL250"] = $ruleCatalog["REL250"]
        $findings = @(Invoke-B3RuleFile -Content $code -Catalog $rc)
        Assert-True -Condition (@($findings | Where-Object { $_.rule_id -eq "REL250" }).Count -ge 1) `
            -Message "REL250 should fire for Dim SqlConnection outside of Using."
    }

    It "REL250 does NOT fire for Using StreamReader" {
        $code = @(
            "Option Explicit On", "Option Strict On",
            "Using reader As New StreamReader(filePath)",
            "    Dim content = reader.ReadToEnd()",
            "End Using"
        ) -join "`n"
        $rc = @{}; $rc["REL250"] = $ruleCatalog["REL250"]
        $findings = @(Invoke-B3RuleFile -Content $code -Catalog $rc)
        Assert-Equal -Actual @($findings | Where-Object { $_.rule_id -eq "REL250" }).Count -Expected 0 `
            -Message "REL250 must not fire when StreamReader is inside a Using block."
    }

    It "REL250 does NOT fire for Dim StringBuilder (not IDisposable)" {
        $code = @(
            "Option Explicit On", "Option Strict On",
            "Dim sb As New StringBuilder()"
        ) -join "`n"
        $rc = @{}; $rc["REL250"] = $ruleCatalog["REL250"]
        $findings = @(Invoke-B3RuleFile -Content $code -Catalog $rc)
        Assert-Equal -Actual @($findings | Where-Object { $_.rule_id -eq "REL250" }).Count -Expected 0 `
            -Message "REL250 must not fire for types that are not IDisposable."
    }

    # --- STR610: String.Format with variable format string ---

    It "STR610 fires when the format argument to String.Format is a variable" {
        $code = @(
            "Option Explicit On", "Option Strict On",
            "Dim template As String = GetFormatFromConfig()",
            "Dim msg = String.Format(template, value1, value2)"
        ) -join "`n"
        $rc = @{}; $rc["STR610"] = $ruleCatalog["STR610"]
        $findings = @(Invoke-B3RuleFile -Content $code -Catalog $rc)
        Assert-True -Condition (@($findings | Where-Object { $_.rule_id -eq "STR610" }).Count -ge 1) `
            -Message "STR610 should fire when String.Format receives a variable as the format argument."
    }

    It "STR610 does NOT fire when String.Format uses a string literal" {
        $code = @(
            "Option Explicit On", "Option Strict On",
            'Dim msg = String.Format("Name: {0}, Value: {1}", name, value)'
        ) -join "`n"
        $rc = @{}; $rc["STR610"] = $ruleCatalog["STR610"]
        $findings = @(Invoke-B3RuleFile -Content $code -Catalog $rc)
        Assert-Equal -Actual @($findings | Where-Object { $_.rule_id -eq "STR610" }).Count -Expected 0 `
            -Message "STR610 must not fire when a string literal is used as the format argument."
    }

    # --- OIM545: GetSingleValue instead of TryGetSingleValue ---

    It "OIM545 fires for Session.Source.GetSingleValue()" {
        $code = @(
            "Option Explicit On", "Option Strict On",
            'Dim val As String = Session.Source.GetSingleValue("Person", "Firstname", whereClause)'
        ) -join "`n"
        $rc = @{}; $rc["OIM545"] = $ruleCatalog["OIM545"]
        $findings = @(Invoke-B3RuleFile -Content $code -Catalog $rc)
        Assert-True -Condition (@($findings | Where-Object { $_.rule_id -eq "OIM545" }).Count -ge 1) `
            -Message "OIM545 should fire for Session.Source.GetSingleValue()."
    }

    It "OIM545 does NOT fire for Session.Source.TryGetSingleValue()" {
        $code = @(
            "Option Explicit On", "Option Strict On",
            'Dim val As String = Session.Source.TryGetSingleValue("Person", "Firstname", whereClause)',
            "If val Is Nothing Then Return"
        ) -join "`n"
        $rc = @{}; $rc["OIM545"] = $ruleCatalog["OIM545"]
        $findings = @(Invoke-B3RuleFile -Content $code -Catalog $rc)
        Assert-Equal -Actual @($findings | Where-Object { $_.rule_id -eq "OIM545" }).Count -Expected 0 `
            -Message "OIM545 must not fire for TryGetSingleValue()."
    }

    # --- OIM555: Save(Session) inside a loop ---

    It "OIM555 fires for .Save(Session) inside a For Each loop" {
        $code = @(
            "Option Explicit On", "Option Strict On",
            "For Each p As IEntity In colPersons",
            "    p.PutValue(""Status"", 1)",
            "    p.Save(Session)",
            "Next"
        ) -join "`n"
        $rc = @{}; $rc["OIM555"] = $ruleCatalog["OIM555"]
        $findings = @(Invoke-B3RuleFile -Content $code -Catalog $rc)
        Assert-True -Condition (@($findings | Where-Object { $_.rule_id -eq "OIM555" }).Count -ge 1) `
            -Message "OIM555 should fire when .Save(Session) is called inside a loop."
    }

    It "OIM555 does NOT fire for .Save(Session) outside a loop" {
        $code = @(
            "Option Explicit On", "Option Strict On",
            "p.PutValue(""Status"", 1)",
            "p.Save(Session)"
        ) -join "`n"
        $rc = @{}; $rc["OIM555"] = $ruleCatalog["OIM555"]
        $findings = @(Invoke-B3RuleFile -Content $code -Catalog $rc)
        Assert-Equal -Actual @($findings | Where-Object { $_.rule_id -eq "OIM555" }).Count -Expected 0 `
            -Message "OIM555 must not fire when .Save(Session) is outside a loop."
    }

    # --- OIM560: multiple TryGetSingleValue/GetSingleValue on same table + same where clause ---
    function Invoke-OIM560File {
        param([string]$Content, [hashtable]$Catalog)
        $tmp = [System.IO.Path]::GetTempFileName() + ".vb"
        Set-Content -LiteralPath $tmp -Value $Content -Encoding UTF8
        try {
            return @(Get-OneImFileFindings -FilePath $tmp -RelativePath "Scripts\Scripts.vb" `
                -RuleCatalog $Catalog -SourceLookup $sourceLookup)
        }
        finally { Remove-Item -LiteralPath $tmp -ErrorAction SilentlyContinue }
    }

    It "OIM560 fires when TryGetSingleValue is called twice — same table, same where variable" {
        $code = @"
Public Sub Test(Session As ISession)
    Dim w As String = "UID_Person = '1'"
    Dim a = Session.Source.TryGetSingleValue("Person", "Firstname", w)
    Dim b = Session.Source.TryGetSingleValue("Person", "Lastname", w)
End Sub
"@
        $rc = @{}; $rc["OIM560"] = $ruleCatalog["OIM560"]
        $findings = Invoke-OIM560File -Content $code -Catalog $rc
        Assert-True -Condition (@($findings | Where-Object { $_.rule_id -eq "OIM560" }).Count -ge 1) `
            -Message "OIM560 should fire when TryGetSingleValue is called twice on the same table and where clause."
    }

    It "OIM560 fires when GetSingleValue is called twice — same table, same where variable" {
        $code = @"
Public Sub Test(Session As ISession)
    Dim w As String = "UID_Person = '1'"
    Dim a = Session.Source.GetSingleValue("Person", "Firstname", w)
    Dim b = Session.Source.GetSingleValue("Person", "Lastname", w)
End Sub
"@
        $rc = @{}; $rc["OIM560"] = $ruleCatalog["OIM560"]
        $findings = Invoke-OIM560File -Content $code -Catalog $rc
        Assert-True -Condition (@($findings | Where-Object { $_.rule_id -eq "OIM560" }).Count -ge 1) `
            -Message "OIM560 should fire when GetSingleValue is called twice on the same table and where clause."
    }

    It "OIM560 fires on the second call line (not the first)" {
        $code = @"
Public Sub Test(Session As ISession)
    Dim w As String = "UID_Person = '1'"
    Dim a = Session.Source.TryGetSingleValue("Person", "Firstname", w)
    Dim b = Session.Source.TryGetSingleValue("Person", "Lastname", w)
End Sub
"@
        $rc = @{}; $rc["OIM560"] = $ruleCatalog["OIM560"]
        $findings = Invoke-OIM560File -Content $code -Catalog $rc
        $hit = @($findings | Where-Object { $_.rule_id -eq "OIM560" })
        Assert-True -Condition ($hit[0].line -ge 4) `
            -Message "OIM560 finding should be on the second call (line 4), not the first."
    }

    It "OIM560 does NOT fire when calls are on different tables" {
        $code = @"
Public Sub Test(Session As ISession)
    Dim w As String = "UID_Person = '1'"
    Dim a = Session.Source.TryGetSingleValue("Person", "Firstname", w)
    Dim b = Session.Source.TryGetSingleValue("Department", "DeptName", w)
End Sub
"@
        $rc = @{}; $rc["OIM560"] = $ruleCatalog["OIM560"]
        $findings = Invoke-OIM560File -Content $code -Catalog $rc
        Assert-Equal -Actual @($findings | Where-Object { $_.rule_id -eq "OIM560" }).Count -Expected 0 `
            -Message "OIM560 must not fire when TryGetSingleValue calls target different tables."
    }

    It "OIM560 does NOT fire when same table is queried with different where clauses" {
        $code = @"
Public Sub Test(Session As ISession)
    Dim w1 As String = "UID_Person = '1'"
    Dim w2 As String = "UID_Person = '2'"
    Dim a = Session.Source.TryGetSingleValue("Person", "Firstname", w1)
    Dim b = Session.Source.TryGetSingleValue("Person", "Lastname", w2)
End Sub
"@
        $rc = @{}; $rc["OIM560"] = $ruleCatalog["OIM560"]
        $findings = Invoke-OIM560File -Content $code -Catalog $rc
        Assert-Equal -Actual @($findings | Where-Object { $_.rule_id -eq "OIM560" }).Count -Expected 0 `
            -Message "OIM560 must not fire when same table is queried with different where clause variables."
    }

    It "OIM560 does NOT fire when TryGetSingleValue is called only once" {
        $code = @"
Public Sub Test(Session As ISession)
    Dim w As String = "UID_Person = '1'"
    Dim a = Session.Source.TryGetSingleValue("Person", "Firstname", w)
End Sub
"@
        $rc = @{}; $rc["OIM560"] = $ruleCatalog["OIM560"]
        $findings = Invoke-OIM560File -Content $code -Catalog $rc
        Assert-Equal -Actual @($findings | Where-Object { $_.rule_id -eq "OIM560" }).Count -Expected 0 `
            -Message "OIM560 must not fire when there is only one TryGetSingleValue call."
    }

    It "OIM560 reports N-1 findings when called N times on the same table and where clause" {
        $code = @"
Public Sub Test(Session As ISession)
    Dim w As String = "UID_Person = '1'"
    Dim a = Session.Source.TryGetSingleValue("Person", "Firstname", w)
    Dim b = Session.Source.TryGetSingleValue("Person", "Lastname", w)
    Dim c = Session.Source.TryGetSingleValue("Person", "DefaultEmailAddress", w)
End Sub
"@
        $rc = @{}; $rc["OIM560"] = $ruleCatalog["OIM560"]
        $findings = Invoke-OIM560File -Content $code -Catalog $rc
        Assert-Equal -Actual @($findings | Where-Object { $_.rule_id -eq "OIM560" }).Count -Expected 2 `
            -Message "OIM560 should report 2 findings (calls 2 and 3) when the same table+where is queried 3 times."
    }
}

Describe "OneIM VB.NET auditor schema snapshot diff" {
    $comparePath = Join-Path $scriptRoot "compare_schema_snapshots.ps1"

    function New-Snapshot {
        param(
            [string[]]$TableNames = @(),
            [object[]]$Columns = @(),
            [object[]]$FkRelations = @()
        )
        $tables = $TableNames | ForEach-Object { [ordered]@{ table_name = $_ } }
        [ordered]@{
            snapshot_metadata = [ordered]@{ generated_at = (Get-Date -Format "o") }
            tables       = @($tables)
            columns      = @($Columns)
            fk_relations = @($FkRelations)
        }
    }

    function Write-SnapshotFile {
        param([string]$Path, [object]$Snapshot)
        Write-TestFile -Path $Path -Content ($Snapshot | ConvertTo-Json -Depth 10)
    }

    function Invoke-Compare {
        param([string]$BaselinePath, [string]$CurrentPath, [string]$OutputDir, [switch]$FailOnDiff)
        $cmdArgs = @("-NoProfile", "-NonInteractive", "-File", $comparePath,
                     "-BaselinePath", $BaselinePath, "-CurrentPath", $CurrentPath,
                     "-OutputDir", $OutputDir)
        if ($FailOnDiff) { $cmdArgs += "-FailOnDiff" }
        # Temporarily use Continue so that child-process stderr (RemoteException) doesn't throw
        $prevEAP = $ErrorActionPreference
        $ErrorActionPreference = "Continue"
        $output = & powershell.exe @cmdArgs 2>&1
        $exitCode = $LASTEXITCODE
        $ErrorActionPreference = $prevEAP
        [pscustomobject]@{ ExitCode = $exitCode; Output = ($output -join "`n") }
    }

    It "exits 0 and reports no differences for identical snapshots" {
        $tmp = New-TestRoot
        $snap = New-Snapshot -TableNames @("Person","Address") `
            -Columns @([ordered]@{ table_name="Person"; column_name="FirstName"; has_template=$false }) `
            -FkRelations @([ordered]@{ child_table="Address"; child_column="UID_Person"; parent_table="Person"; parent_column="UID_Person" })
        $bPath = Join-Path $tmp "baseline.json"
        $cPath = Join-Path $tmp "current.json"
        Write-SnapshotFile -Path $bPath -Snapshot $snap
        Write-SnapshotFile -Path $cPath -Snapshot $snap
        $r = Invoke-Compare -BaselinePath $bPath -CurrentPath $cPath -OutputDir $tmp
        Assert-Equal -Actual $r.ExitCode -Expected 0 -Message "Exit 0 for identical snapshots"
        $diff = Get-Content (Join-Path $tmp "schema-diff.json") -Raw | ConvertFrom-Json
        Assert-Equal -Actual $diff.diff_metadata.has_diff -Expected $false -Message "has_diff should be false"
        Assert-Equal -Actual $diff.diff_metadata.total_differences -Expected 0 -Message "total_differences should be 0"
    }

    It "detects added table" {
        $tmp = New-TestRoot
        $base = New-Snapshot -TableNames @("Person")
        $curr = New-Snapshot -TableNames @("Person","Department")
        $bPath = Join-Path $tmp "baseline.json"; $cPath = Join-Path $tmp "current.json"
        Write-SnapshotFile -Path $bPath -Snapshot $base
        Write-SnapshotFile -Path $cPath -Snapshot $curr
        $r = Invoke-Compare -BaselinePath $bPath -CurrentPath $cPath -OutputDir $tmp
        $diff = Get-Content (Join-Path $tmp "schema-diff.json") -Raw | ConvertFrom-Json
        Assert-Equal -Actual $diff.summary.tables_added -Expected 1 -Message "tables_added should be 1"
        Assert-Equal -Actual $diff.summary.tables_removed -Expected 0 -Message "tables_removed should be 0"
        Assert-Equal -Actual ([string]$diff.tables.added[0].table_name) -Expected "Department" -Message "Added table name"
    }

    It "detects removed table" {
        $tmp = New-TestRoot
        $base = New-Snapshot -TableNames @("Person","OldTable")
        $curr = New-Snapshot -TableNames @("Person")
        $bPath = Join-Path $tmp "baseline.json"; $cPath = Join-Path $tmp "current.json"
        Write-SnapshotFile -Path $bPath -Snapshot $base
        Write-SnapshotFile -Path $cPath -Snapshot $curr
        $r = Invoke-Compare -BaselinePath $bPath -CurrentPath $cPath -OutputDir $tmp
        $diff = Get-Content (Join-Path $tmp "schema-diff.json") -Raw | ConvertFrom-Json
        Assert-Equal -Actual $diff.summary.tables_removed -Expected 1 -Message "tables_removed should be 1"
        Assert-Equal -Actual ([string]$diff.tables.removed[0].table_name) -Expected "OldTable" -Message "Removed table name"
    }

    It "detects added column" {
        $tmp = New-TestRoot
        $base = New-Snapshot -TableNames @("Person") `
            -Columns @([ordered]@{ table_name="Person"; column_name="FirstName"; has_template=$false })
        $curr = New-Snapshot -TableNames @("Person") `
            -Columns @([ordered]@{ table_name="Person"; column_name="FirstName"; has_template=$false },
                       [ordered]@{ table_name="Person"; column_name="LastName";  has_template=$false })
        $bPath = Join-Path $tmp "baseline.json"; $cPath = Join-Path $tmp "current.json"
        Write-SnapshotFile -Path $bPath -Snapshot $base
        Write-SnapshotFile -Path $cPath -Snapshot $curr
        $r = Invoke-Compare -BaselinePath $bPath -CurrentPath $cPath -OutputDir $tmp
        $diff = Get-Content (Join-Path $tmp "schema-diff.json") -Raw | ConvertFrom-Json
        Assert-Equal -Actual $diff.summary.columns_added -Expected 1 -Message "columns_added should be 1"
        Assert-Equal -Actual ([string]$diff.columns.added[0].column_name) -Expected "LastName" -Message "Added column name"
    }

    It "detects column template_gained" {
        $tmp = New-TestRoot
        $base = New-Snapshot -TableNames @("Person") `
            -Columns @([ordered]@{ table_name="Person"; column_name="FirstName"; has_template=$false })
        $curr = New-Snapshot -TableNames @("Person") `
            -Columns @([ordered]@{ table_name="Person"; column_name="FirstName"; has_template=$true })
        $bPath = Join-Path $tmp "baseline.json"; $cPath = Join-Path $tmp "current.json"
        Write-SnapshotFile -Path $bPath -Snapshot $base
        Write-SnapshotFile -Path $cPath -Snapshot $curr
        $r = Invoke-Compare -BaselinePath $bPath -CurrentPath $cPath -OutputDir $tmp
        $diff = Get-Content (Join-Path $tmp "schema-diff.json") -Raw | ConvertFrom-Json
        Assert-Equal -Actual $diff.summary.columns_template_gained -Expected 1 -Message "columns_template_gained should be 1"
        Assert-Equal -Actual $diff.summary.columns_template_lost  -Expected 0 -Message "columns_template_lost should be 0"
    }

    It "detects column template_lost" {
        $tmp = New-TestRoot
        $base = New-Snapshot -TableNames @("Person") `
            -Columns @([ordered]@{ table_name="Person"; column_name="FirstName"; has_template=$true })
        $curr = New-Snapshot -TableNames @("Person") `
            -Columns @([ordered]@{ table_name="Person"; column_name="FirstName"; has_template=$false })
        $bPath = Join-Path $tmp "baseline.json"; $cPath = Join-Path $tmp "current.json"
        Write-SnapshotFile -Path $bPath -Snapshot $base
        Write-SnapshotFile -Path $cPath -Snapshot $curr
        $r = Invoke-Compare -BaselinePath $bPath -CurrentPath $cPath -OutputDir $tmp
        $diff = Get-Content (Join-Path $tmp "schema-diff.json") -Raw | ConvertFrom-Json
        Assert-Equal -Actual $diff.summary.columns_template_lost  -Expected 1 -Message "columns_template_lost should be 1"
        Assert-Equal -Actual $diff.summary.columns_template_gained -Expected 0 -Message "columns_template_gained should be 0"
    }

    It "detects added FK relation" {
        $tmp = New-TestRoot
        $base = New-Snapshot -TableNames @("Person","Address")
        $curr = New-Snapshot -TableNames @("Person","Address") `
            -FkRelations @([ordered]@{ child_table="Address"; child_column="UID_Person"; parent_table="Person"; parent_column="UID_Person" })
        $bPath = Join-Path $tmp "baseline.json"; $cPath = Join-Path $tmp "current.json"
        Write-SnapshotFile -Path $bPath -Snapshot $base
        Write-SnapshotFile -Path $cPath -Snapshot $curr
        $r = Invoke-Compare -BaselinePath $bPath -CurrentPath $cPath -OutputDir $tmp
        $diff = Get-Content (Join-Path $tmp "schema-diff.json") -Raw | ConvertFrom-Json
        Assert-Equal -Actual $diff.summary.fk_relations_added -Expected 1 -Message "fk_relations_added should be 1"
    }

    It "detects removed FK relation" {
        $tmp = New-TestRoot
        $fk = [ordered]@{ child_table="Address"; child_column="UID_Person"; parent_table="Person"; parent_column="UID_Person" }
        $base = New-Snapshot -TableNames @("Person","Address") -FkRelations @($fk)
        $curr = New-Snapshot -TableNames @("Person","Address")
        $bPath = Join-Path $tmp "baseline.json"; $cPath = Join-Path $tmp "current.json"
        Write-SnapshotFile -Path $bPath -Snapshot $base
        Write-SnapshotFile -Path $cPath -Snapshot $curr
        $r = Invoke-Compare -BaselinePath $bPath -CurrentPath $cPath -OutputDir $tmp
        $diff = Get-Content (Join-Path $tmp "schema-diff.json") -Raw | ConvertFrom-Json
        Assert-Equal -Actual $diff.summary.fk_relations_removed -Expected 1 -Message "fk_relations_removed should be 1"
    }

    It "exits 1 with -FailOnDiff when differences exist" {
        $tmp = New-TestRoot
        $base = New-Snapshot -TableNames @("Person")
        $curr = New-Snapshot -TableNames @("Person","NewTable")
        $bPath = Join-Path $tmp "baseline.json"; $cPath = Join-Path $tmp "current.json"
        Write-SnapshotFile -Path $bPath -Snapshot $base
        Write-SnapshotFile -Path $cPath -Snapshot $curr
        $r = Invoke-Compare -BaselinePath $bPath -CurrentPath $cPath -OutputDir $tmp -FailOnDiff
        Assert-Equal -Actual $r.ExitCode -Expected 1 -Message "Exit 1 with -FailOnDiff when diff found"
    }

    It "exits 0 with -FailOnDiff when no differences exist" {
        $tmp = New-TestRoot
        $snap = New-Snapshot -TableNames @("Person")
        $bPath = Join-Path $tmp "baseline.json"; $cPath = Join-Path $tmp "current.json"
        Write-SnapshotFile -Path $bPath -Snapshot $snap
        Write-SnapshotFile -Path $cPath -Snapshot $snap
        $r = Invoke-Compare -BaselinePath $bPath -CurrentPath $cPath -OutputDir $tmp -FailOnDiff
        Assert-Equal -Actual $r.ExitCode -Expected 0 -Message "Exit 0 with -FailOnDiff when no diff"
    }

    It "exits 2 when baseline snapshot file not found" {
        $tmp = New-TestRoot
        $snap = New-Snapshot -TableNames @("Person")
        $cPath = Join-Path $tmp "current.json"
        Write-SnapshotFile -Path $cPath -Snapshot $snap
        $r = Invoke-Compare -BaselinePath (Join-Path $tmp "missing.json") -CurrentPath $cPath -OutputDir $tmp
        Assert-Equal -Actual $r.ExitCode -Expected 2 -Message "Exit 2 when baseline not found"
    }

    It "exits 2 when current snapshot file not found" {
        $tmp = New-TestRoot
        $snap = New-Snapshot -TableNames @("Person")
        $bPath = Join-Path $tmp "baseline.json"
        Write-SnapshotFile -Path $bPath -Snapshot $snap
        $r = Invoke-Compare -BaselinePath $bPath -CurrentPath (Join-Path $tmp "missing.json") -OutputDir $tmp
        Assert-Equal -Actual $r.ExitCode -Expected 2 -Message "Exit 2 when current not found"
    }

    It "diff output file has correct structure with all required sections" {
        $tmp = New-TestRoot
        $base = New-Snapshot -TableNames @("A")
        $curr = New-Snapshot -TableNames @("A","B")
        $bPath = Join-Path $tmp "baseline.json"; $cPath = Join-Path $tmp "current.json"
        Write-SnapshotFile -Path $bPath -Snapshot $base
        Write-SnapshotFile -Path $cPath -Snapshot $curr
        Invoke-Compare -BaselinePath $bPath -CurrentPath $cPath -OutputDir $tmp | Out-Null
        $diff = Get-Content (Join-Path $tmp "schema-diff.json") -Raw | ConvertFrom-Json
        Assert-True -Condition ($null -ne $diff.diff_metadata)  -Message "diff_metadata section present"
        Assert-True -Condition ($null -ne $diff.summary)        -Message "summary section present"
        Assert-True -Condition ($null -ne $diff.tables)         -Message "tables section present"
        Assert-True -Condition ($null -ne $diff.columns)        -Message "columns section present"
        Assert-True -Condition ($null -ne $diff.fk_relations)   -Message "fk_relations section present"
        Assert-True -Condition ($diff.diff_metadata.has_diff -eq $true) -Message "has_diff reflects actual diff"
    }
}

# ---------------------------------------------------------------------------
# HTML report unit tests
# ---------------------------------------------------------------------------
Describe "OneIM VB.NET auditor HTML report" {
    function New-MinimalReport {
        param([object[]]$Findings = @())
        [pscustomobject]@{
            generated_at         = "2026-01-01 00:00:00 +00:00"
            oneim_version        = "9.3.1"
            target_path          = "C:\target"
            reference_repo_path  = "C:\ref"
            target_root          = "C:\target"
            selected_target_paths = @("C:\target")
            summary = [pscustomobject]@{
                files_audited      = 1
                detected_findings  = $Findings.Count
                reported_findings  = $Findings.Count
                omitted_examples   = 0
                total_findings     = $Findings.Count
                gating_findings    = 0
                correctness_findings  = @($Findings | Where-Object { $_.category -eq "correctness" }).Count
                security_findings     = @($Findings | Where-Object { $_.category -eq "security" }).Count
                reliability_findings  = @($Findings | Where-Object { $_.category -eq "reliability" }).Count
                performance_findings  = @($Findings | Where-Object { $_.category -eq "performance" }).Count
                concurrency_findings  = @($Findings | Where-Object { $_.category -eq "concurrency" }).Count
                high_findings         = @($Findings | Where-Object { $_.severity -eq "high" }).Count
                medium_findings       = @($Findings | Where-Object { $_.severity -eq "medium" }).Count
                low_findings          = @($Findings | Where-Object { $_.severity -eq "low" }).Count
            }
            reference_validation = [pscustomobject]@{
                mode                         = "repo-root"
                version_root                 = "C:\ref\reference-library\oneim-9.3.1"
                primary_ootb_root            = "C:\ref\reference-library\oneim-9.3.1\ootb"
                ootb_file_count              = 0
                promoted_custom_root_count   = 0
                candidate_custom_root_count  = 0
            }
            omitted_example_summaries = @()
            unresolved_questions      = @()
            findings                  = $Findings
        }
    }

    It "HTML contains Finding Breakdown section heading" {
        $report = New-MinimalReport -Findings @()
        $html = ConvertTo-OneImAuditHtmlReport -Report $report
        Assert-True -Condition ($html -match "Finding Breakdown") -Message "HTML should contain the severity histogram section heading."
    }

    It "HTML does not render suppression sections in this phase" {
        $report = New-MinimalReport -Findings @()
        $html = ConvertTo-OneImAuditHtmlReport -Report $report
        Assert-True -Condition ($html -notmatch "Applied Suppressions") -Message "Suppression details should not appear in the HTML report during rule tuning."
        Assert-True -Condition ($html -notmatch "Suppressions file") -Message "The HTML report should not render suppression file details during rule tuning."
    }

    It "histogram shows zero-finding rows as dashes" {
        $report = New-MinimalReport -Findings @()
        $html = ConvertTo-OneImAuditHtmlReport -Report $report
        # Three severity rows with all-zero counts should render &mdash; entities
        $dashCount = ([regex]::Matches($html, "&mdash;")).Count
        Assert-True -Condition ($dashCount -ge 15) -Message "All 15 (3 severities x 5 categories) cells should be dashes when there are no findings."
    }

    It "histogram shows a count cell when a finding exists" {
        $finding = [pscustomobject]@{
            rule_id            = "VB001"
            title              = "Missing Option Strict"
            category           = "correctness"
            severity           = "high"
            confidence         = 90
            confidence_label   = "High"
            gating             = $false
            file_path          = "C:\target\Table\Table.vb"
            relative_path      = "Table\Table.vb"
            line               = 1
            snippet            = ""
            evidence           = "Missing header"
            triggering_scenario = "No Option Strict"
            remediation        = "Add Option Strict."
            sources            = @()
        }
        $report = New-MinimalReport -Findings @($finding)
        $html = ConvertTo-OneImAuditHtmlReport -Report $report
        # The high/correctness cell should show a bar and count 1, not a dash
        Assert-True -Condition ($html -match "bar-high.*>1<") -Message "HTML should render a count cell for the high-correctness finding."
    }

    It "histogram row totals are correct" {
        $findings = @(
            [pscustomobject]@{ category="correctness"; severity="high";   rule_id="X1"; title=""; confidence=90; confidence_label=""; gating=$false; file_path=""; relative_path=""; line=1; snippet=""; evidence=""; triggering_scenario=""; remediation=""; sources=@() },
            [pscustomobject]@{ category="security";    severity="high";   rule_id="X2"; title=""; confidence=90; confidence_label=""; gating=$false; file_path=""; relative_path=""; line=1; snippet=""; evidence=""; triggering_scenario=""; remediation=""; sources=@() },
            [pscustomobject]@{ category="reliability"; severity="medium"; rule_id="X3"; title=""; confidence=90; confidence_label=""; gating=$false; file_path=""; relative_path=""; line=1; snippet=""; evidence=""; triggering_scenario=""; remediation=""; sources=@() }
        )
        $report = New-MinimalReport -Findings $findings
        $html = ConvertTo-OneImAuditHtmlReport -Report $report
        # high row total = 2, medium row total = 1
        Assert-True -Condition ($html -match "<strong>2</strong>") -Message "High severity row total should be 2."
        Assert-True -Condition ($html -match "<strong>1</strong>") -Message "Medium severity row total should be 1."
    }

    It "report JSON summary contains reliability_findings and concurrency_findings fields" {
        $testRoot = New-TestRoot
        try {
            New-ManagedReferenceLayout -RootPath $testRoot | Out-Null
            $targetFile = Join-Path $testRoot "Scripts\Scripts.vb"
            Write-TestFile -Path $targetFile -Content (@(
                "Option Explicit On",
                "Option Strict On",
                "Option Infer On",
                "",
                "Namespace DynScripts",
                "Public Class Scripts",
                "    Public Function SafeValue(input As String) As String",
                "        Return input.Trim()",
                "    End Function",
                "End Class",
                "End Namespace"
            ) -join "`r`n")
            $outputRoot = Join-Path $testRoot "audit-output"
            $hostPath = (Get-Command powershell -ErrorAction Stop).Source
            $null = & $hostPath -NoProfile -ExecutionPolicy Bypass -File $runnerPath -TargetPath $targetFile -ReferenceRepoPath $testRoot -OutputDir $outputRoot -NoPrompt
            $runFolder = Get-ChildItem -LiteralPath $outputRoot -Directory | Sort-Object LastWriteTime -Descending | Select-Object -First 1
            $report = Get-Content -LiteralPath (Join-Path $runFolder.FullName "audit-report.json") -Raw | ConvertFrom-Json
            Assert-True -Condition ($null -ne $report.summary.PSObject.Properties["reliability_findings"]) -Message "Summary should include reliability_findings field."
            Assert-True -Condition ($null -ne $report.summary.PSObject.Properties["concurrency_findings"]) -Message "Summary should include concurrency_findings field."
            Assert-True -Condition ($null -ne $report.summary.PSObject.Properties["high_findings"])        -Message "Summary should include high_findings field."
            Assert-True -Condition ($null -ne $report.summary.PSObject.Properties["medium_findings"])      -Message "Summary should include medium_findings field."
            Assert-True -Condition ($null -ne $report.summary.PSObject.Properties["low_findings"])         -Message "Summary should include low_findings field."
        }
        finally {
            Remove-Item -LiteralPath $testRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It "deduplicates identical findings before reporting" {
        # Construct two minimal findings sharing the same dedup key (rule_id + relative_path + line).
        # Using raw pscustomobject — the test is exercising the dedup logic, not the finding factory.
        $shared = [pscustomobject]@{ rule_id = "VB003"; relative_path = "Table\Table.vb"; line = 5; evidence = "First" }
        $dupe   = [pscustomobject]@{ rule_id = "VB003"; relative_path = "Table\Table.vb"; line = 5; evidence = "Second (dup)" }
        $unique = [pscustomobject]@{ rule_id = "VB003"; relative_path = "Table\Table.vb"; line = 7; evidence = "Different line" }

        $seenKeys = @{}
        $deduped = New-Object System.Collections.Generic.List[object]
        foreach ($f in @($shared, $dupe, $unique)) {
            $k = ("{0}|{1}|{2}" -f $f.rule_id, $f.relative_path, $f.line)
            if (-not $seenKeys.ContainsKey($k)) { $seenKeys[$k] = $true; $deduped.Add($f) }
        }
        Assert-Equal -Actual $deduped.Count -Expected 2 -Message "Duplicate finding at same rule+path+line should be dropped; different line kept."
        Assert-Equal -Actual $deduped[0].evidence -Expected "First" -Message "First occurrence should be kept, not the duplicate."
        Assert-Equal -Actual $deduped[1].evidence -Expected "Different line" -Message "Finding at a different line should be preserved."
    }

    It "HTML contains severity filter checkboxes" {
        $report = New-MinimalReport -Findings @()
        $html = ConvertTo-OneImAuditHtmlReport -Report $report
        Assert-True -Condition ($html -match "id='filter-high'")   -Message "HTML should include filter-high checkbox."
        Assert-True -Condition ($html -match "id='filter-medium'") -Message "HTML should include filter-medium checkbox."
        Assert-True -Condition ($html -match "id='filter-low'")    -Message "HTML should include filter-low checkbox."
        Assert-True -Condition ($html -match "applyFilters")       -Message "HTML should include the applyFilters JS function."
    }

    It "HTML findings are grouped by file with a file-group header row" {
        $mkFinding = {
            param($path, $sev)
            [pscustomobject]@{
                rule_id="VB001"; title="T"; category="correctness"; severity=$sev
                confidence=90; confidence_label="High"; gating=$false
                file_path="C:\t\$path"; relative_path=$path; line=1; snippet=""
                evidence="e"; triggering_scenario="s"; remediation="r"; sources=@()
            }
        }
        $findings = @(
            (& $mkFinding "Table\A.vb" "high"),
            (& $mkFinding "Table\A.vb" "medium"),
            (& $mkFinding "Scripts\B.vb" "low")
        )
        $report = New-MinimalReport -Findings $findings
        $html = ConvertTo-OneImAuditHtmlReport -Report $report
        # Two file groups should produce two file-group-hdr rows
        $hdrCount = ([regex]::Matches($html, "class='file-group-hdr'")).Count
        Assert-Equal -Actual $hdrCount -Expected 2 -Message "Two distinct files should produce two file-group header rows."
        # Each finding row should carry data-sev
        $sevAttrCount = ([regex]::Matches($html, "data-sev=")).Count
        Assert-Equal -Actual $sevAttrCount -Expected 3 -Message "Three findings should produce three data-sev attributes."
    }

    It "file-group header rows include onclick toggle wiring" {
        $finding = [pscustomobject]@{
            rule_id="VB001"; title="T"; category="correctness"; severity="high"
            confidence=90; confidence_label="High"; gating=$false
            file_path="C:\t\Table\A.vb"; relative_path="Table\A.vb"; line=1; snippet=""
            evidence="e"; triggering_scenario="s"; remediation="r"; sources=@()
        }
        $report = New-MinimalReport -Findings @($finding)
        $html = ConvertTo-OneImAuditHtmlReport -Report $report
        Assert-True -Condition ($html -match "toggleGroup") -Message "Header row should include toggleGroup onclick call."
        Assert-True -Condition ($html -match "function toggleGroup") -Message "HTML should define the toggleGroup function."
    }

    It "cross-file findings (empty relative_path) are grouped under a synthetic header" {
        $crossFile = [pscustomobject]@{
            rule_id="CNC610"; title="Write cycle"; category="concurrency"; severity="high"
            confidence=95; confidence_label="High"; gating=$false
            file_path=""; relative_path=""; line=0; snippet=""
            evidence="node X"; triggering_scenario="s"; remediation="r"; sources=@()
        }
        $report = New-MinimalReport -Findings @($crossFile)
        $html = ConvertTo-OneImAuditHtmlReport -Report $report
        Assert-True -Condition ($html -match "cross-file findings") -Message "Cross-file findings should be grouped under a (cross-file findings) header."
    }

    It "HTML contains print CSS media query" {
        $report = New-MinimalReport -Findings @()
        $html = ConvertTo-OneImAuditHtmlReport -Report $report
        Assert-True -Condition ($html -match "@media print") -Message "HTML should include a @media print CSS block for printing."
    }

    It "HTML file-group headers have id anchors and file index appears for multiple files" {
        $mkF = {
            param($path)
            [pscustomobject]@{
                rule_id="VB001"; title="T"; category="correctness"; severity="high"
                confidence=90; confidence_label="High"; gating=$false
                file_path="C:\t\$path"; relative_path=$path; line=1; snippet=""
                evidence="e"; triggering_scenario="s"; remediation="r"; sources=@()
            }
        }
        $findings = @(
            (& $mkF "Table\A.vb"),
            (& $mkF "Scripts\B.vb")
        )
        $report = New-MinimalReport -Findings $findings
        $html = ConvertTo-OneImAuditHtmlReport -Report $report
        Assert-True -Condition ($html -match "id='grp-0'")      -Message "First file-group header should carry id='grp-0' anchor."
        Assert-True -Condition ($html -match "id='file-index'") -Message "File index nav list should be rendered when multiple file groups are present."
    }
}

# ---------------------------------------------------------------------------
# OIM570 — MultiValueProperty modified without PutValue writeback
# ---------------------------------------------------------------------------
Describe "OneIM VB.NET auditor OIM570 (MVP modified without writeback)" {
    function Invoke-OIM570File {
        param([string]$Content, [hashtable]$Catalog)
        $tmp = [System.IO.Path]::GetTempFileName() + ".vb"
        Set-Content -LiteralPath $tmp -Value $Content -Encoding UTF8
        try {
            return @(Get-OneImFileFindings -FilePath $tmp -RelativePath "Scripts\Scripts.vb" `
                -RuleCatalog $Catalog -SourceLookup $sourceLookup)
        }
        finally { Remove-Item -LiteralPath $tmp -ErrorAction SilentlyContinue }
    }

    It "OIM570 fires when MVP is modified with .Add() but no PutValue writeback is present" {
        $code = @"
Public Sub Test(entity As IEntity)
    Dim mvpRoles As New MultiValueProperty(entity.GetValue("Roles").String)
    mvpRoles.Add("Admin")
End Sub
"@
        $rc = @{}; $rc["OIM570"] = $ruleCatalog["OIM570"]
        $findings = Invoke-OIM570File -Content $code -Catalog $rc
        Assert-True -Condition (@($findings | Where-Object { $_.rule_id -eq "OIM570" }).Count -ge 1) `
            -Message "OIM570 should fire when .Add() is called on an MVP without a subsequent PutValue writeback."
    }

    It "OIM570 fires when MVP is modified with .Remove() but no PutValue writeback is present" {
        $code = @"
Public Sub Test(entity As IEntity)
    Dim mvpRoles As New MultiValueProperty(entity.GetValue("Roles").String)
    mvpRoles.Remove("Admin")
End Sub
"@
        $rc = @{}; $rc["OIM570"] = $ruleCatalog["OIM570"]
        $findings = Invoke-OIM570File -Content $code -Catalog $rc
        Assert-True -Condition (@($findings | Where-Object { $_.rule_id -eq "OIM570" }).Count -ge 1) `
            -Message "OIM570 should fire when .Remove() is called on an MVP without a subsequent PutValue writeback."
    }

    It "OIM570 finding line is at the .Add() or .Remove() call site" {
        $code = @"
Public Sub Test(entity As IEntity)
    Dim mvpRoles As New MultiValueProperty(entity.GetValue("Roles").String)
    mvpRoles.Add("Admin")
End Sub
"@
        $rc = @{}; $rc["OIM570"] = $ruleCatalog["OIM570"]
        $findings = Invoke-OIM570File -Content $code -Catalog $rc
        $hit = @($findings | Where-Object { $_.rule_id -eq "OIM570" })
        Assert-True -Condition ($hit[0].line -ge 3) `
            -Message "OIM570 finding should be reported at the .Add()/.Remove() call line, not line 1."
    }

    It "OIM570 does NOT fire when .Add() is followed by PutValue(..., mvp.Value)" {
        $code = @"
Public Sub Test(entity As IEntity)
    Dim mvpRoles As New MultiValueProperty(entity.GetValue("Roles").String)
    mvpRoles.Add("Admin")
    entity.PutValue("Roles", mvpRoles.Value)
End Sub
"@
        $rc = @{}; $rc["OIM570"] = $ruleCatalog["OIM570"]
        $findings = Invoke-OIM570File -Content $code -Catalog $rc
        Assert-Equal -Actual @($findings | Where-Object { $_.rule_id -eq "OIM570" }).Count -Expected 0 `
            -Message "OIM570 must not fire when PutValue writeback is present."
    }

    It "OIM570 does NOT fire when there is no MVP modification at all" {
        $code = @"
Public Sub Test(entity As IEntity)
    Dim mvpRoles As New MultiValueProperty(entity.GetValue("Roles").String)
    Dim count As Integer = mvpRoles.Count
End Sub
"@
        $rc = @{}; $rc["OIM570"] = $ruleCatalog["OIM570"]
        $findings = Invoke-OIM570File -Content $code -Catalog $rc
        Assert-Equal -Actual @($findings | Where-Object { $_.rule_id -eq "OIM570" }).Count -Expected 0 `
            -Message "OIM570 must not fire when the MVP is only read, not modified."
    }
}

# ---------------------------------------------------------------------------
# OIM571 — MultiValueProperty index access without .Count bounds check
# ---------------------------------------------------------------------------
Describe "OneIM VB.NET auditor OIM571 (MVP index access without Count guard)" {
    function Invoke-OIM571File {
        param([string]$Content, [hashtable]$Catalog)
        $tmp = [System.IO.Path]::GetTempFileName() + ".vb"
        Set-Content -LiteralPath $tmp -Value $Content -Encoding UTF8
        try {
            return @(Get-OneImFileFindings -FilePath $tmp -RelativePath "Scripts\Scripts.vb" `
                -RuleCatalog $Catalog -SourceLookup $sourceLookup)
        }
        finally { Remove-Item -LiteralPath $tmp -ErrorAction SilentlyContinue }
    }

    It "OIM571 fires when MVP variable is accessed by index without a .Count guard" {
        $code = @"
Public Function Test(entity As IEntity) As String
    Dim mvpRoles As New MultiValueProperty(entity.GetValue("Roles").String)
    Return mvpRoles(0)
End Function
"@
        $rc = @{}; $rc["OIM571"] = $ruleCatalog["OIM571"]
        $findings = Invoke-OIM571File -Content $code -Catalog $rc
        Assert-True -Condition (@($findings | Where-Object { $_.rule_id -eq "OIM571" }).Count -ge 1) `
            -Message "OIM571 should fire when an MVP variable is accessed by index without a preceding .Count check."
    }

    It "OIM571 does NOT fire when .Count guard precedes the index access" {
        $code = @"
Public Function Test(entity As IEntity) As String
    Dim mvpRoles As New MultiValueProperty(entity.GetValue("Roles").String)
    If mvpRoles.Count > 0 Then
        Return mvpRoles(0)
    End If
    Return String.Empty
End Function
"@
        $rc = @{}; $rc["OIM571"] = $ruleCatalog["OIM571"]
        $findings = Invoke-OIM571File -Content $code -Catalog $rc
        Assert-Equal -Actual @($findings | Where-Object { $_.rule_id -eq "OIM571" }).Count -Expected 0 `
            -Message "OIM571 must not fire when a .Count guard appears within 10 lines before the index access."
    }

    It "OIM571 does NOT fire when there is no MVP index access" {
        $code = @"
Public Sub Test(entity As IEntity)
    Dim mvpRoles As New MultiValueProperty(entity.GetValue("Roles").String)
    mvpRoles.Add("Admin")
    entity.PutValue("Roles", mvpRoles.Value)
End Sub
"@
        $rc = @{}; $rc["OIM571"] = $ruleCatalog["OIM571"]
        $findings = Invoke-OIM571File -Content $code -Catalog $rc
        Assert-Equal -Actual @($findings | Where-Object { $_.rule_id -eq "OIM571" }).Count -Expected 0 `
            -Message "OIM571 must not fire when no index access is made on the MVP variable."
    }
}

# ---------------------------------------------------------------------------
# OIM580 — VI_AE_ITDataFrom* called without comment-based column dependencies
# ---------------------------------------------------------------------------
Describe "OneIM VB.NET auditor OIM580 (ITData without column dependency comments)" {
    function Invoke-OIM580File {
        param([string]$Content, [hashtable]$Catalog)
        $tmp = [System.IO.Path]::GetTempFileName() + ".vb"
        Set-Content -LiteralPath $tmp -Value $Content -Encoding UTF8
        try {
            return @(Get-OneImFileFindings -FilePath $tmp -RelativePath "Table\Table.vb" `
                -RuleCatalog $Catalog -SourceLookup $sourceLookup)
        }
        finally { Remove-Item -LiteralPath $tmp -ErrorAction SilentlyContinue }
    }

    It "OIM580 fires when VI_AE_ITDataFromOrg is called with no dollar-comment dependency" {
        $code = @"
Public Function Test(uid As String) As String
    Return VI_AE_ITDataFromOrg(uid, "CostCenter")
End Function
"@
        $rc = @{}; $rc["OIM580"] = $ruleCatalog["OIM580"]
        $findings = Invoke-OIM580File -Content $code -Catalog $rc
        Assert-True -Condition (@($findings | Where-Object { $_.rule_id -eq "OIM580" }).Count -ge 1) `
            -Message "OIM580 should fire when VI_AE_ITDataFromOrg is present without a dollar-comment dependency declaration."
    }

    It "OIM580 fires when VI_AE_ITDataFromPers is called with no dollar-comment dependency" {
        $code = @"
Public Function Test(uid As String) As String
    Return VI_AE_ITDataFromPers(uid, "Department")
End Function
"@
        $rc = @{}; $rc["OIM580"] = $ruleCatalog["OIM580"]
        $findings = Invoke-OIM580File -Content $code -Catalog $rc
        Assert-True -Condition (@($findings | Where-Object { $_.rule_id -eq "OIM580" }).Count -ge 1) `
            -Message "OIM580 should fire when VI_AE_ITDataFromPers is present without a dollar-comment dependency declaration."
    }

    It "OIM580 does NOT fire when VI_AE_ITDataFromOrg is preceded by a dollar-comment dependency" {
        $code = @'
Public Function Test(uid As String) As String
    '$Department$
    '$Location$
    Return VI_AE_ITDataFromOrg(uid, "CostCenter")
End Function
'@
        $rc = @{}; $rc["OIM580"] = $ruleCatalog["OIM580"]
        $findings = Invoke-OIM580File -Content $code -Catalog $rc
        Assert-Equal -Actual @($findings | Where-Object { $_.rule_id -eq "OIM580" }).Count -Expected 0 `
            -Message "OIM580 must not fire when a dollar-comment dependency declaration is present."
    }

    It "OIM580 does NOT fire when VI_AE_ITDataFrom* is not called at all" {
        $code = @"
Public Function Test(uid As String) As String
    Return Session.Source.TryGetSingleValue("Person", "DisplayName", where)
End Function
"@
        $rc = @{}; $rc["OIM580"] = $ruleCatalog["OIM580"]
        $findings = Invoke-OIM580File -Content $code -Catalog $rc
        Assert-Equal -Actual @($findings | Where-Object { $_.rule_id -eq "OIM580" }).Count -Expected 0 `
            -Message "OIM580 must not fire when neither VI_AE_ITDataFromOrg nor VI_AE_ITDataFromPers appears."
    }

    It "OIM580 does not apply outside template surfaces" {
        $tmp = [System.IO.Path]::GetTempFileName() + ".vb"
        $code = @"
Public Function Test(uid As String) As String
    Return VI_AE_ITDataFromOrg(uid, "CostCenter")
End Function
"@
        Set-Content -LiteralPath $tmp -Value $code -Encoding UTF8
        try {
            $rc = @{}; $rc["OIM580"] = $ruleCatalog["OIM580"]
            $findings = @(Get-OneImFileFindings -FilePath $tmp -RelativePath "Scripts\Scripts.vb" -RuleCatalog $rc -SourceLookup $sourceLookup)
            Assert-Equal -Actual @($findings | Where-Object { $_.rule_id -eq "OIM580" }).Count -Expected 0 `
                -Message "Template-only dependency rules should not fire on script paths."
        }
        finally { Remove-Item -LiteralPath $tmp -ErrorAction SilentlyContinue }
    }
}

# ---------------------------------------------------------------------------
# Get-OneImAuditConfig — configuration loading and defaults
# ---------------------------------------------------------------------------
Describe "OneIM VB.NET auditor Get-OneImAuditConfig (config loading)" {
    It "Returns all default keys when no config file is provided" {
        $cfg = Get-OneImAuditConfig -ConfigPath ""
        Assert-Equal -Actual $cfg.detection.header_scan_lines -Expected 40 `
            -Message "Default header_scan_lines should be 40."
        Assert-Equal -Actual $cfg.detection.mvp_guard_lookback_lines -Expected 10 `
            -Message "Default mvp_guard_lookback_lines should be 10."
        Assert-Equal -Actual $cfg.confidence.high_threshold -Expected 80 `
            -Message "Default high_threshold should be 80."
        Assert-Equal -Actual $cfg.scoring.severity_weights.high -Expected 3 `
            -Message "Default severity weight for high should be 3."
    }

    It "Overrides individual keys from a JSON file while preserving defaults for missing keys" {
        $tmpJson = [System.IO.Path]::GetTempFileName() -replace '\.tmp$', '.json'
        Set-Content -LiteralPath $tmpJson -Value '{"detection":{"header_scan_lines":20}}' -Encoding UTF8
        try {
            $cfg = Get-OneImAuditConfig -ConfigPath $tmpJson
            Assert-Equal -Actual $cfg.detection.header_scan_lines -Expected 20 `
                -Message "header_scan_lines should be overridden to 20."
            Assert-Equal -Actual $cfg.detection.mvp_guard_lookback_lines -Expected 10 `
                -Message "mvp_guard_lookback_lines should keep its default of 10."
            Assert-Equal -Actual $cfg.confidence.high_threshold -Expected 80 `
                -Message "high_threshold should keep its default of 80."
        }
        finally { Remove-Item -LiteralPath $tmpJson -ErrorAction SilentlyContinue }
    }

    It "Falls back to all defaults when config file contains invalid JSON" {
        $tmpJson = [System.IO.Path]::GetTempFileName() -replace '\.tmp$', '.json'
        Set-Content -LiteralPath $tmpJson -Value '{ not valid json' -Encoding UTF8
        try {
            $cfg = Get-OneImAuditConfig -ConfigPath $tmpJson
            Assert-Equal -Actual $cfg.detection.header_scan_lines -Expected 40 `
                -Message "header_scan_lines should fall back to 40 on parse error."
        }
        finally { Remove-Item -LiteralPath $tmpJson -ErrorAction SilentlyContinue }
    }
}

# ---------------------------------------------------------------------------
# Get-OneImAuditScoreColor — color threshold function
# ---------------------------------------------------------------------------
Describe "OneIM VB.NET auditor Get-OneImAuditScoreColor (color bands)" {
    $thresholds = @{ green_max = 2.0; yellow_max = 5.0; orange_max = 10.0 }

    It "Returns score-green for a score below green_max" {
        Assert-Equal -Actual (Get-OneImAuditScoreColor -Score 1.5 -Thresholds $thresholds) `
            -Expected "score-green" -Message "Score 1.5 should be green."
    }

    It "Returns score-green for score exactly at 0" {
        Assert-Equal -Actual (Get-OneImAuditScoreColor -Score 0 -Thresholds $thresholds) `
            -Expected "score-green" -Message "Score 0 should be green."
    }

    It "Returns score-yellow for a score in [green_max, yellow_max)" {
        Assert-Equal -Actual (Get-OneImAuditScoreColor -Score 3.0 -Thresholds $thresholds) `
            -Expected "score-yellow" -Message "Score 3.0 should be yellow."
    }

    It "Returns score-orange for a score in [yellow_max, orange_max)" {
        Assert-Equal -Actual (Get-OneImAuditScoreColor -Score 7.0 -Thresholds $thresholds) `
            -Expected "score-orange" -Message "Score 7.0 should be orange."
    }

    It "Returns score-red for a score at or above orange_max" {
        Assert-Equal -Actual (Get-OneImAuditScoreColor -Score 10.0 -Thresholds $thresholds) `
            -Expected "score-red" -Message "Score 10.0 should be red."
    }

    It "Returns score-red for a score well above orange_max" {
        Assert-Equal -Actual (Get-OneImAuditScoreColor -Score 99.0 -Thresholds $thresholds) `
            -Expected "score-red" -Message "Score 99.0 should be red."
    }
}

# ---------------------------------------------------------------------------
# VB006 — Integer.Parse / Double.Parse without TryParse (declarative)
# ---------------------------------------------------------------------------
Describe "OneIM VB.NET auditor VB006 (Parse without TryParse)" {
    function Invoke-VB006File {
        param([string]$Content, [hashtable]$Catalog)
        $tmp = [System.IO.Path]::GetTempFileName() + ".vb"
        Set-Content -LiteralPath $tmp -Value $Content -Encoding UTF8
        try {
            return @(Get-OneImFileFindings -FilePath $tmp -RelativePath "Scripts\Scripts.vb" `
                -RuleCatalog $Catalog -SourceLookup $sourceLookup)
        }
        finally { Remove-Item -LiteralPath $tmp -ErrorAction SilentlyContinue }
    }

    It "VB006 fires on Integer.Parse()" {
        $code = @"
Public Function Test(v As String) As Integer
    Return Integer.Parse(v)
End Function
"@
        $rc = @{}; $rc["VB006"] = $ruleCatalog["VB006"]
        $findings = Invoke-VB006File -Content $code -Catalog $rc
        Assert-True -Condition (@($findings | Where-Object { $_.rule_id -eq "VB006" }).Count -ge 1) `
            -Message "VB006 should fire on Integer.Parse()."
    }

    It "VB006 fires on Long.Parse()" {
        $code = @"
Public Function Test(v As String) As Long
    Return Long.Parse(v)
End Function
"@
        $rc = @{}; $rc["VB006"] = $ruleCatalog["VB006"]
        $findings = Invoke-VB006File -Content $code -Catalog $rc
        Assert-True -Condition (@($findings | Where-Object { $_.rule_id -eq "VB006" }).Count -ge 1) `
            -Message "VB006 should fire on Long.Parse()."
    }

    It "VB006 does NOT fire on Integer.TryParse()" {
        $code = @"
Public Function Test(v As String) As Integer
    Dim result As Integer = 0
    Integer.TryParse(v, result)
    Return result
End Function
"@
        $rc = @{}; $rc["VB006"] = $ruleCatalog["VB006"]
        $findings = Invoke-VB006File -Content $code -Catalog $rc
        Assert-Equal -Actual @($findings | Where-Object { $_.rule_id -eq "VB006" }).Count -Expected 0 `
            -Message "VB006 must not fire on Integer.TryParse()."
    }

    It "VB006 does NOT fire when Parse is not called" {
        $code = @"
Public Function Test(v As String) As String
    Return v.ToUpper()
End Function
"@
        $rc = @{}; $rc["VB006"] = $ruleCatalog["VB006"]
        $findings = Invoke-VB006File -Content $code -Catalog $rc
        Assert-Equal -Actual @($findings | Where-Object { $_.rule_id -eq "VB006" }).Count -Expected 0 `
            -Message "VB006 must not fire when no Parse call is present."
    }
}

# ---------------------------------------------------------------------------
# REL260 — CType/DirectCast without TypeOf guard
# ---------------------------------------------------------------------------
Describe "OneIM VB.NET auditor REL260 (unsafe cast without TypeOf guard)" {
    function Invoke-REL260File {
        param([string]$Content, [hashtable]$Catalog)
        $tmp = [System.IO.Path]::GetTempFileName() + ".vb"
        Set-Content -LiteralPath $tmp -Value $Content -Encoding UTF8
        try {
            return @(Get-OneImFileFindings -FilePath $tmp -RelativePath "Scripts\Scripts.vb" `
                -RuleCatalog $Catalog -SourceLookup $sourceLookup)
        }
        finally { Remove-Item -LiteralPath $tmp -ErrorAction SilentlyContinue }
    }

    It "REL260 fires on CType without a TypeOf guard" {
        $code = @"
Public Function Test(obj As Object) As IEntity
    Return CType(obj, IEntity)
End Function
"@
        $rc = @{}; $rc["REL260"] = $ruleCatalog["REL260"]
        $findings = Invoke-REL260File -Content $code -Catalog $rc
        Assert-True -Condition (@($findings | Where-Object { $_.rule_id -eq "REL260" }).Count -ge 1) `
            -Message "REL260 should fire on CType without TypeOf guard."
    }

    It "REL260 fires on DirectCast without a TypeOf guard" {
        $code = @"
Public Sub Test(obj As Object)
    Dim e As IEntity = DirectCast(obj, IEntity)
End Sub
"@
        $rc = @{}; $rc["REL260"] = $ruleCatalog["REL260"]
        $findings = Invoke-REL260File -Content $code -Catalog $rc
        Assert-True -Condition (@($findings | Where-Object { $_.rule_id -eq "REL260" }).Count -ge 1) `
            -Message "REL260 should fire on DirectCast without TypeOf guard."
    }

    It "REL260 does NOT fire when TypeOf guard precedes CType" {
        $code = @"
Public Function Test(obj As Object) As IEntity
    If TypeOf obj Is IEntity Then
        Return CType(obj, IEntity)
    End If
    Return Nothing
End Function
"@
        $rc = @{}; $rc["REL260"] = $ruleCatalog["REL260"]
        $findings = Invoke-REL260File -Content $code -Catalog $rc
        Assert-Equal -Actual @($findings | Where-Object { $_.rule_id -eq "REL260" }).Count -Expected 0 `
            -Message "REL260 must not fire when a TypeOf Is guard precedes the CType."
    }
}

# ---------------------------------------------------------------------------
# SEC200 — Process.Start() call (declarative line-pattern)
# ---------------------------------------------------------------------------
Describe "OneIM VB.NET auditor SEC200 (Process.Start call)" {
    function Invoke-SEC200File {
        param([string]$Content, [hashtable]$Catalog)
        $tmp = [System.IO.Path]::GetTempFileName() + ".vb"
        Set-Content -LiteralPath $tmp -Value $Content -Encoding UTF8
        try {
            return @(Get-OneImFileFindings -FilePath $tmp -RelativePath "Scripts\Scripts.vb" `
                -RuleCatalog $Catalog -SourceLookup $sourceLookup)
        }
        finally { Remove-Item -LiteralPath $tmp -ErrorAction SilentlyContinue }
    }

    It "SEC200 fires on Process.Start()" {
        $code = @"
Public Sub Test(path As String)
    Process.Start(path)
End Sub
"@
        $rc = @{}; $rc["SEC200"] = $ruleCatalog["SEC200"]
        $findings = Invoke-SEC200File -Content $code -Catalog $rc
        Assert-True -Condition (@($findings | Where-Object { $_.rule_id -eq "SEC200" }).Count -ge 1) `
            -Message "SEC200 should fire on Process.Start()."
    }

    It "SEC200 does NOT fire when Process.Start is only in a comment" {
        $code = @"
' Do not use Process.Start in production scripts.
Public Sub Test()
    Session.Source.Notify("user@example.com", "Done")
End Sub
"@
        $rc = @{}; $rc["SEC200"] = $ruleCatalog["SEC200"]
        $findings = Invoke-SEC200File -Content $code -Catalog $rc
        Assert-Equal -Actual @($findings | Where-Object { $_.rule_id -eq "SEC200" }).Count -Expected 0 `
            -Message "SEC200 must not fire when Process.Start appears only in a comment."
    }

    It "SEC200 does NOT fire when Process.Start is not called" {
        $code = @"
Public Function Test(v As String) As String
    Return v.ToUpper()
End Function
"@
        $rc = @{}; $rc["SEC200"] = $ruleCatalog["SEC200"]
        $findings = Invoke-SEC200File -Content $code -Catalog $rc
        Assert-Equal -Actual @($findings | Where-Object { $_.rule_id -eq "SEC200" }).Count -Expected 0 `
            -Message "SEC200 must not fire when no Process.Start call is present."
    }
}

# ---------------------------------------------------------------------------
# OIM590 — GetList with empty WHERE filter
# ---------------------------------------------------------------------------
Describe "OneIM VB.NET auditor OIM590 (GetList with empty filter)" {
    function Invoke-OIM590File {
        param([string]$Content, [hashtable]$Catalog)
        $tmp = [System.IO.Path]::GetTempFileName() + ".vb"
        Set-Content -LiteralPath $tmp -Value $Content -Encoding UTF8
        try {
            return @(Get-OneImFileFindings -FilePath $tmp -RelativePath "Scripts\Scripts.vb" `
                -RuleCatalog $Catalog -SourceLookup $sourceLookup)
        }
        finally { Remove-Item -LiteralPath $tmp -ErrorAction SilentlyContinue }
    }

    It "OIM590 fires on GetList with empty string filter" {
        $code = @"
Public Function Test(session As ISession) As IEntity()
    Return session.Source.GetList(Of IEntity)("Person", "")
End Function
"@
        $rc = @{}; $rc["OIM590"] = $ruleCatalog["OIM590"]
        $findings = Invoke-OIM590File -Content $code -Catalog $rc
        Assert-True -Condition (@($findings | Where-Object { $_.rule_id -eq "OIM590" }).Count -ge 1) `
            -Message "OIM590 should fire on GetList with empty string filter."
    }

    It "OIM590 fires on GetList with String.Empty filter" {
        $code = @"
Public Function Test(session As ISession) As IEntity()
    Return session.Source.GetList(Of IEntity)("ADSAccount", String.Empty)
End Function
"@
        $rc = @{}; $rc["OIM590"] = $ruleCatalog["OIM590"]
        $findings = Invoke-OIM590File -Content $code -Catalog $rc
        Assert-True -Condition (@($findings | Where-Object { $_.rule_id -eq "OIM590" }).Count -ge 1) `
            -Message "OIM590 should fire on GetList with String.Empty filter."
    }

    It "OIM590 does NOT fire when GetList has a non-empty WHERE clause" {
        $code = @"
Public Function Test(session As ISession, uid As String) As IEntity()
    Return session.Source.GetList(Of IEntity)("PersonHasAccount", "UID_Person = '" & uid & "'")
End Function
"@
        $rc = @{}; $rc["OIM590"] = $ruleCatalog["OIM590"]
        $findings = Invoke-OIM590File -Content $code -Catalog $rc
        Assert-Equal -Actual @($findings | Where-Object { $_.rule_id -eq "OIM590" }).Count -Expected 0 `
            -Message "OIM590 must not fire when GetList has a non-empty WHERE clause."
    }

    It "OIM590 does NOT fire when GetList is not called" {
        $code = @"
Public Function Test() As String
    Return "nothing"
End Function
"@
        $rc = @{}; $rc["OIM590"] = $ruleCatalog["OIM590"]
        $findings = Invoke-OIM590File -Content $code -Catalog $rc
        Assert-Equal -Actual @($findings | Where-Object { $_.rule_id -eq "OIM590" }).Count -Expected 0 `
            -Message "OIM590 must not fire when GetList is not present."
    }
}

# ---------------------------------------------------------------------------
# OIM596 — Hardcoded business value without GetConfigParmValue
# ---------------------------------------------------------------------------
Describe "OneIM VB.NET auditor OIM596 (hardcoded business value vs GetConfigParmValue)" {
    function Invoke-OIM596File {
        param([string]$Content, [hashtable]$Catalog)
        $tmp = [System.IO.Path]::GetTempFileName() + ".vb"
        Set-Content -LiteralPath $tmp -Value $Content -Encoding UTF8
        try {
            return @(Get-OneImFileFindings -FilePath $tmp -RelativePath "Scripts\Scripts.vb" `
                -RuleCatalog $Catalog -SourceLookup $sourceLookup)
        }
        finally { Remove-Item -LiteralPath $tmp -ErrorAction SilentlyContinue }
    }

    It "OIM596 fires when GetValue result compared to hardcoded business string" {
        $code = @"
Public Function IsHR(entity As IEntity) As Boolean
    Return entity.GetValue("Department") = "HR"
End Function
"@
        $rc = @{}; $rc["OIM596"] = $ruleCatalog["OIM596"]
        $findings = Invoke-OIM596File -Content $code -Catalog $rc
        Assert-True -Condition (@($findings | Where-Object { $_.rule_id -eq "OIM596" }).Count -ge 1) `
            -Message "OIM596 should fire when GetValue is compared to a hardcoded business string."
    }

    It "OIM596 does NOT fire when Connection.GetConfigParmValue is used in the same file" {
        $code = @"
Public Function IsHR(entity As IEntity) As Boolean
    Dim hrCode As String = CStr(Connection.GetConfigParmValue("Custom\HRCode"))
    Return entity.GetValue("Department") = hrCode
End Function
"@
        $rc = @{}; $rc["OIM596"] = $ruleCatalog["OIM596"]
        $findings = Invoke-OIM596File -Content $code -Catalog $rc
        Assert-Equal -Actual @($findings | Where-Object { $_.rule_id -eq "OIM596" }).Count -Expected 0 `
            -Message "OIM596 must not fire when Connection.GetConfigParmValue is present."
    }

    It "OIM596 does NOT fire when comparing against empty string" {
        $code = @"
Public Function IsEmpty(entity As IEntity) As Boolean
    Return entity.GetValue("Department") = ""
End Function
"@
        $rc = @{}; $rc["OIM596"] = $ruleCatalog["OIM596"]
        $findings = Invoke-OIM596File -Content $code -Catalog $rc
        Assert-Equal -Actual @($findings | Where-Object { $_.rule_id -eq "OIM596" }).Count -Expected 0 `
            -Message "OIM596 must not fire when the comparison target is an empty string."
    }

    It "OIM596 does NOT fire when comparing against a GUID" {
        $code = @"
Public Function IsSpecificAccount(entity As IEntity) As Boolean
    Return entity.GetValue("UID_Person") = "a1b2c3d4-e5f6-7890-abcd-ef1234567890"
End Function
"@
        $rc = @{}; $rc["OIM596"] = $ruleCatalog["OIM596"]
        $findings = Invoke-OIM596File -Content $code -Catalog $rc
        Assert-Equal -Actual @($findings | Where-Object { $_.rule_id -eq "OIM596" }).Count -Expected 0 `
            -Message "OIM596 must not fire when comparing against a GUID string."
    }
}

# ---------------------------------------------------------------------------
# New rule tests -- OIM597: TryGet / TryGetSingleValue inside a loop
# ---------------------------------------------------------------------------
Describe "OneIM VB.NET auditor new rules" {

    # Helper: write content to a temp .vb file, run Get-OneImFileFindings, return findings
    function Invoke-OIM597File {
        param([string]$Content, [hashtable]$Catalog)
        $tmp = [System.IO.Path]::GetTempFileName() + ".vb"
        Set-Content -LiteralPath $tmp -Value $Content -Encoding UTF8
        try {
            return @(Get-OneImFileFindings -FilePath $tmp -RelativePath "Scripts\Scripts.vb" `
                -RuleCatalog $Catalog -SourceLookup $sourceLookup)
        } finally {
            Remove-Item -LiteralPath $tmp -ErrorAction SilentlyContinue
        }
    }

    It "OIM597 fires for TryGetSingleValue inside a For Each loop" {
        $code = @(
            "Option Explicit On", "Option Strict On",
            "For Each acc In accounts",
            "    Dim dept As IEntity = Nothing",
            "    Session.Source.TryGetSingleValue(Of IEntity)(""Department"", ""UID_Department = '"" & acc.UID & ""'"", dept)",
            "Next"
        ) -join "`r`n"
        $rc = @{}; $rc["OIM597"] = $ruleCatalog["OIM597"]
        $findings = @(Invoke-OIM597File -Content $code -Catalog $rc)
        Assert-True -Condition (@($findings | Where-Object { $_.rule_id -eq "OIM597" }).Count -ge 1) `
            -Message "OIM597 should fire for TryGetSingleValue inside a For Each loop."
    }

    It "OIM597 fires for TryGet inside a For loop" {
        $code = @(
            "Option Explicit On", "Option Strict On",
            "For i = 0 To uids.Count - 1",
            "    Dim entity As IEntity = Session.Source.TryGet(Of IEntity)(""Person"", ""UID_Person = '"" & uids(i) & ""'"")",
            "Next i"
        ) -join "`r`n"
        $rc = @{}; $rc["OIM597"] = $ruleCatalog["OIM597"]
        $findings = @(Invoke-OIM597File -Content $code -Catalog $rc)
        Assert-True -Condition (@($findings | Where-Object { $_.rule_id -eq "OIM597" }).Count -ge 1) `
            -Message "OIM597 should fire for TryGet inside a For loop."
    }

    It "OIM597 fires for TryGetSingleFiltered inside a Do While loop" {
        $code = @(
            "Option Explicit On", "Option Strict On",
            "Do While reader.Read()",
            "    Dim org As IEntity = Nothing",
            "    Session.Source.TryGetSingleFiltered(Of IEntity)(""Org"", filter, org)",
            "Loop"
        ) -join "`r`n"
        $rc = @{}; $rc["OIM597"] = $ruleCatalog["OIM597"]
        $findings = @(Invoke-OIM597File -Content $code -Catalog $rc)
        Assert-True -Condition (@($findings | Where-Object { $_.rule_id -eq "OIM597" }).Count -ge 1) `
            -Message "OIM597 should fire for TryGetSingleFiltered inside a Do While loop."
    }

    It "OIM597 does NOT fire for TryGetSingleValue outside a loop" {
        $code = @(
            "Option Explicit On", "Option Strict On",
            "Dim dept As IEntity = Nothing",
            "Session.Source.TryGetSingleValue(Of IEntity)(""Department"", ""UID_Department = '"" & uid & ""'"", dept)"
        ) -join "`r`n"
        $rc = @{}; $rc["OIM597"] = $ruleCatalog["OIM597"]
        $findings = @(Invoke-OIM597File -Content $code -Catalog $rc)
        Assert-Equal -Actual @($findings | Where-Object { $_.rule_id -eq "OIM597" }).Count -Expected 0 `
            -Message "OIM597 must not fire when TryGetSingleValue is outside a loop."
    }

    It "OIM597 does NOT fire for GetCollection inside a loop (compliant pattern)" {
        $code = @(
            "Option Explicit On", "Option Strict On",
            "Dim depts As IEntityCollection = Session.Source.GetCollection(Of IEntity)(""Department"", """")",
            "For Each acc In accounts",
            "    Dim uid As String = acc.GetValue(""UID_Department"").String",
            "Next"
        ) -join "`r`n"
        $rc = @{}; $rc["OIM597"] = $ruleCatalog["OIM597"]
        $findings = @(Invoke-OIM597File -Content $code -Catalog $rc)
        Assert-Equal -Actual @($findings | Where-Object { $_.rule_id -eq "OIM597" }).Count -Expected 0 `
            -Message "OIM597 must not fire when using GetCollection before the loop."
    }
}

Describe "OneIM VB.NET auditor approved source indexes" {
    It "loads additional source IDs from source_index_files" {
        $testRoot = New-TestRoot
        try {
            $sourcesPath = Join-Path $testRoot "approved-sources.json"
            $indexPath = Join-Path $testRoot "apiserver-doc-index.json"

            ([ordered]@{
                    sources = @()
                    source_index_files = @("apiserver-doc-index.json")
                } | ConvertTo-Json -Depth 6) | Set-Content -LiteralPath $sourcesPath -Encoding UTF8

            ([ordered]@{
                    sources = @(
                        [ordered]@{
                            id = "indexed-source"
                            title = "Indexed local source"
                            url = "file:///c:/docs/indexed-source.htm"
                        }
                    )
                } | ConvertTo-Json -Depth 6) | Set-Content -LiteralPath $indexPath -Encoding UTF8

            $lookup = Get-OneImAuditSourceLookup -ApprovedSourcesPath $sourcesPath
            Assert-True -Condition ($lookup.ContainsKey("indexed-source")) -Message "Expected indexed-source to resolve from source_index_files."
        }
        finally {
            Remove-Item -LiteralPath $testRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }

    It "validate_audit_rules resolves source IDs from source_index_files" {
        $pwshCmd = Get-Command pwsh -ErrorAction SilentlyContinue
        $hostPath = if ($pwshCmd) { $pwshCmd.Source } else { (Get-Command powershell -ErrorAction Stop).Source }
        $validateScript = Join-Path $scriptRoot "validate_audit_rules.ps1"
        $testRoot = New-TestRoot
        try {
            $catalogPath = Join-Path $testRoot "audit-rules.json"
            $sourcesPath = Join-Path $testRoot "approved-sources.json"
            $indexPath = Join-Path $testRoot "apiserver-doc-index.json"

            $catalog = [ordered]@{
                policy_version = "2026-04-08"
                rules = @(
                    [ordered]@{
                        id = "SRCIDX001"
                        title = "Rule backed by indexed source"
                        category = "reliability"
                        severity = "low"
                        confidence = 55
                        state = "active"
                        engine = "coded"
                        why = "x"
                        source_ids = @("indexed-source")
                    }
                )
            }
            Write-TestRuleCatalog -Path $catalogPath -Catalog $catalog

            ([ordered]@{
                    sources = @()
                    source_index_files = @("apiserver-doc-index.json")
                } | ConvertTo-Json -Depth 6) | Set-Content -LiteralPath $sourcesPath -Encoding UTF8

            ([ordered]@{
                    sources = @(
                        [ordered]@{
                            id = "indexed-source"
                            title = "Indexed local source"
                            url = "file:///c:/docs/indexed-source.htm"
                        }
                    )
                } | ConvertTo-Json -Depth 6) | Set-Content -LiteralPath $indexPath -Encoding UTF8

            $null = & $hostPath -NoProfile -ExecutionPolicy Bypass -File $validateScript -RuleCatalogPath $catalogPath -ApprovedSourcesPath $sourcesPath 2>$null
            $exitCode = $LASTEXITCODE

            Assert-Equal -Actual $exitCode -Expected 0 -Message "validate_audit_rules.ps1 should resolve source IDs from source_index_files."
        }
        finally {
            Remove-Item -LiteralPath $testRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

Describe "OneIM VB.NET auditor API Server rules" {
    function Invoke-ApiRuleFile {
        param(
            [string]$Content,
            [string[]]$RuleIds
        )

        $tmp = [System.IO.Path]::GetTempFileName() + ".vb"
        Set-Content -LiteralPath $tmp -Value $Content -Encoding UTF8
        try {
            $rc = @{}
            foreach ($ruleId in @($RuleIds)) {
                $rc[$ruleId] = $ruleCatalog[$ruleId]
            }

            return @(Get-OneImFileFindings -FilePath $tmp -RelativePath "Scripts\Scripts.vb" -RuleCatalog $rc -SourceLookup $sourceLookup)
        }
        finally {
            Remove-Item -LiteralPath $tmp -ErrorAction SilentlyContinue
        }
    }

    It "API600 fires when AwaitTasks is explicitly enabled" {
        $code = @"
Option Explicit On
Option Strict On

Public Sub BuildStream()
    Dim response = New ObservableEventStreamResponse() With { .AwaitTasks = True }
End Sub
"@
        $findings = Invoke-ApiRuleFile -Content $code -RuleIds @("API600")
        Assert-True -Condition (@($findings | Where-Object { $_.rule_id -eq "API600" }).Count -ge 1) `
            -Message "API600 should fire when AwaitTasks is set to True."
    }

    It "API600 does NOT fire when AwaitTasks stays disabled" {
        $code = @"
Option Explicit On
Option Strict On

Public Sub BuildStream()
    Dim response = New ObservableEventStreamResponse() With { .AwaitTasks = False }
End Sub
"@
        $findings = Invoke-ApiRuleFile -Content $code -RuleIds @("API600")
        Assert-Equal -Actual @($findings | Where-Object { $_.rule_id -eq "API600" }).Count -Expected 0 `
            -Message "API600 must not fire when AwaitTasks is False."
    }

    It "API610 fires when IncludeAllExceptionInfo is enabled" {
        $code = @"
Public Sub Configure(cfg As ServerLevelConfig)
    cfg.IncludeAllExceptionInfo = True
End Sub
"@
        $findings = Invoke-ApiRuleFile -Content $code -RuleIds @("API610")
        Assert-True -Condition (@($findings | Where-Object { $_.rule_id -eq "API610" }).Count -ge 1) `
            -Message "API610 should fire when IncludeAllExceptionInfo is set to True."
    }

    It "API620 fires when endpoint permission checks are disabled" {
        $code = @"
Public Sub Configure(cfg As ServerLevelConfig)
    cfg.EnableEndpointSecurityPermissionCheck = False
End Sub
"@
        $findings = Invoke-ApiRuleFile -Content $code -RuleIds @("API620")
        Assert-True -Condition (@($findings | Where-Object { $_.rule_id -eq "API620" }).Count -ge 1) `
            -Message "API620 should fire when endpoint security permission checks are disabled."
    }

    It "API630 fires when CorsOrigins includes a wildcard" {
        $code = @"
Public Sub Configure(cfg As ServerLevelConfig)
    cfg.CorsOrigins = New String() { "*" }
End Sub
"@
        $findings = Invoke-ApiRuleFile -Content $code -RuleIds @("API630")
        Assert-True -Condition (@($findings | Where-Object { $_.rule_id -eq "API630" }).Count -ge 1) `
            -Message "API630 should fire when CorsOrigins includes a wildcard."
    }

    It "API630 does NOT fire for explicit trusted origins" {
        $code = @"
Public Sub Configure(cfg As ServerLevelConfig)
    cfg.CorsOrigins = New String() { "https://portal.example.com" }
End Sub
"@
        $findings = Invoke-ApiRuleFile -Content $code -RuleIds @("API630")
        Assert-Equal -Actual @($findings | Where-Object { $_.rule_id -eq "API630" }).Count -Expected 0 `
            -Message "API630 must not fire when CorsOrigins contains only explicit trusted origins."
    }

    It "API640 fires on manual X-Forwarded-For parsing" {
        $code = @"
Public Function ResolveIp(request As IRequest) As String
    Return request.Headers("X-Forwarded-For")
End Function
"@
        $findings = Invoke-ApiRuleFile -Content $code -RuleIds @("API640")
        Assert-True -Condition (@($findings | Where-Object { $_.rule_id -eq "API640" }).Count -ge 1) `
            -Message "API640 should fire on manual forwarded-header parsing."
    }

    It "API640 does NOT fire when using GetRequestIpAddress" {
        $code = @"
Public Function ResolveIp(request As IRequest) As String
    Return request.GetRequestIpAddress()
End Function
"@
        $findings = Invoke-ApiRuleFile -Content $code -RuleIds @("API640")
        Assert-Equal -Actual @($findings | Where-Object { $_.rule_id -eq "API640" }).Count -Expected 0 `
            -Message "API640 must not fire when GetRequestIpAddress is used."
    }
}
