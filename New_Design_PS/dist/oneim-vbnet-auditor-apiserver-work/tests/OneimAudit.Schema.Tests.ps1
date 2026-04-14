#Requires -Version 7
$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

$skillRoot      = Split-Path -Parent $PSScriptRoot
$scriptRoot     = Join-Path $skillRoot "scripts"
$snapshotScript = Join-Path $scriptRoot "export_oneim_schema_snapshot.ps1"

# ---------------------------------------------------------------------------
# Load Build-SchemaIndexes from the production script using the PS AST.
# No live DB connection is required.
# ---------------------------------------------------------------------------
$ast = [System.Management.Automation.Language.Parser]::ParseFile(
    $snapshotScript, [ref]$null, [ref]$null)

$funcDefs = $ast.FindAll(
    { $args[0] -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)

foreach ($func in $funcDefs) {
    if ($func.Name -eq 'Build-SchemaIndexes') {
        . ([scriptblock]::Create($func.Extent.Text))
        break
    }
}

if (-not (Get-Command Build-SchemaIndexes -ErrorAction SilentlyContinue)) {
    throw "Build-SchemaIndexes was not found in '$snapshotScript'. " +
          "Ensure the function is defined at script scope."
}

# ---------------------------------------------------------------------------
# Synthetic FK fixture helpers
# ---------------------------------------------------------------------------
function New-Fk {
    param(
        [string]$ChildTable, [string]$ChildColumn,
        [string]$ParentTable, [string]$ParentColumn
    )
    [pscustomobject]@{
        child_table   = $ChildTable
        child_column  = $ChildColumn
        parent_table  = $ParentTable
        parent_column = $ParentColumn
    }
}

# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------
Describe "OneimAudit.Schema - Build-SchemaIndexes" {

    Context "empty FK list" {
        It "returns empty indexes when there are no FK relations" {
            $result = Build-SchemaIndexes -FkRelations @()
            $result.ColumnToFkTarget.Count  | Should -Be 0
            $result.ParentToChildren.Count  | Should -Be 0
        }
    }

    Context "column_to_fk_target index" {
        $fks = @(
            New-Fk "Person"   "UID_Org"    "Org"     "UID_Org"
            New-Fk "Person"   "UID_Dept"   "Dept"    "UID_Dept"
            New-Fk "Contract" "UID_Person" "Person"  "UID_Person"
        )
        $result = Build-SchemaIndexes -FkRelations $fks

        It "key format is ChildTable.ChildColumn" {
            $result.ColumnToFkTarget.Keys | Should -Contain "Person.UID_Org"
            $result.ColumnToFkTarget.Keys | Should -Contain "Person.UID_Dept"
            $result.ColumnToFkTarget.Keys | Should -Contain "Contract.UID_Person"
        }

        It "value carries correct parent_table" {
            $result.ColumnToFkTarget["Person.UID_Org"].parent_table | Should -Be "Org"
        }

        It "value carries correct parent_column" {
            $result.ColumnToFkTarget["Person.UID_Org"].parent_column | Should -Be "UID_Org"
        }

        It "has one entry per unique child column" {
            $result.ColumnToFkTarget.Count | Should -Be 3
        }

        It "tables with no FK edges are absent from the index" {
            $result.ColumnToFkTarget.Keys | Should -Not -Contain "Org.UID_Org"
        }
    }

    Context "parent_to_children index" {
        $fks = @(
            New-Fk "Person"    "UID_Org"       "Org"    "UID_Org"
            New-Fk "Contract"  "UID_Org"       "Org"    "UID_Org"
            New-Fk "AADGroup"  "UID_Org"       "Org"    "UID_Org"
            New-Fk "Person"    "UID_Dept"      "Dept"   "UID_Dept"
        )
        $result = Build-SchemaIndexes -FkRelations $fks

        It "key format is ParentTable.ParentColumn" {
            $result.ParentToChildren.Keys | Should -Contain "Org.UID_Org"
            $result.ParentToChildren.Keys | Should -Contain "Dept.UID_Dept"
        }

        It "multiple children for the same parent are all recorded" {
            $children = $result.ParentToChildren["Org.UID_Org"]
            $children.Count | Should -Be 3
        }

        It "child entry carries correct child_table" {
            $childTables = @($result.ParentToChildren["Org.UID_Org"] |
                ForEach-Object { $_.child_table })
            $childTables | Should -Contain "Person"
            $childTables | Should -Contain "Contract"
            $childTables | Should -Contain "AADGroup"
        }

        It "child entry carries correct child_column" {
            $cols = @($result.ParentToChildren["Org.UID_Org"] |
                ForEach-Object { $_.child_column })
            $cols | Should -Not -Contain "UID_Dept"
        }

        It "parent with single child has an array of count 1" {
            $result.ParentToChildren["Dept.UID_Dept"].Count | Should -Be 1
        }

        It "values are arrays not Generic.List (JSON-serialisable)" {
            $val = $result.ParentToChildren["Org.UID_Org"]
            ($val -is [System.Array]) | Should -Be $true
        }
    }

    Context "duplicate FK edges (same child, two rows)" {
        It "last-write-wins for column_to_fk_target when child appears twice" {
            $fks = @(
                New-Fk "Person" "UID_Org" "Org"     "UID_Org"
                New-Fk "Person" "UID_Org" "OrgNew"  "UID_OrgNew"
            )
            $result = Build-SchemaIndexes -FkRelations $fks
            # Second row overwrites the first
            $result.ColumnToFkTarget["Person.UID_Org"].parent_table | Should -Be "OrgNew"
        }

        It "parent_to_children accumulates both rows for each parent" {
            $fks = @(
                New-Fk "Person" "UID_Org" "Org"    "UID_Org"
                New-Fk "Person" "UID_Org" "OrgNew" "UID_OrgNew"
            )
            $result = Build-SchemaIndexes -FkRelations $fks
            # Two distinct parent keys, each with one child
            $result.ParentToChildren["Org.UID_Org"].Count    | Should -Be 1
            $result.ParentToChildren["OrgNew.UID_OrgNew"].Count | Should -Be 1
        }
    }

    Context "key correctness with dots in column names" {
        It "handles column names that contain dots (multi-part)" {
            $fks = @(New-Fk "TableA" "Col.Sub" "TableB" "UID_B")
            $result = Build-SchemaIndexes -FkRelations $fks
            $result.ColumnToFkTarget.Keys | Should -Contain "TableA.Col.Sub"
        }
    }

    Context "10-table synthetic schema (plan-spec fixture)" {
        # Simulates a 10-table, 8-FK-edge schema as described in the plan
        $fks = @(
            New-Fk "Employee"   "UID_Department" "Department" "UID_Department"
            New-Fk "Employee"   "UID_Location"   "Location"   "UID_Location"
            New-Fk "Contract"   "UID_Employee"   "Employee"   "UID_Employee"
            New-Fk "Contract"   "UID_Project"    "Project"    "UID_Project"
            New-Fk "Assignment" "UID_Employee"   "Employee"   "UID_Employee"
            New-Fk "Assignment" "UID_Role"       "Role"       "UID_Role"
            New-Fk "Project"    "UID_Department" "Department" "UID_Department"
            New-Fk "Role"       "UID_Department" "Department" "UID_Department"
        )
        $result = Build-SchemaIndexes -FkRelations $fks

        It "column_to_fk_target has one entry per FK edge" {
            $result.ColumnToFkTarget.Count | Should -Be 8
        }

        It "Department appears as parent for Employee, Project, and Role" {
            $children = @($result.ParentToChildren["Department.UID_Department"] |
                ForEach-Object { $_.child_table })
            $children | Should -Contain "Employee"
            $children | Should -Contain "Project"
            $children | Should -Contain "Role"
        }

        It "Employee appears as parent for Contract and Assignment" {
            $children = @($result.ParentToChildren["Employee.UID_Employee"] |
                ForEach-Object { $_.child_table })
            $children | Should -Contain "Contract"
            $children | Should -Contain "Assignment"
        }

        It "tables that are only children (Assignment, Contract) have no parent_to_children entry" {
            # Assignment and Contract are never referenced as parents in this fixture
            $result.ParentToChildren.Keys | Should -Not -Contain "Assignment.UID_Employee"
            $result.ParentToChildren.Keys | Should -Not -Contain "Contract.UID_Employee"
        }
    }
}
