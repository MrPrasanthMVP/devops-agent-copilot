#Requires -Modules Pester
<#
    Unit tests for jira-workflows. No live credentials required.
    Run: Invoke-Pester .github/skills/jira-workflows/tests/
#>

BeforeAll {
    $repoRoot = (Resolve-Path "$PSScriptRoot/../../../..").Path
    Import-Module (Join-Path $repoRoot "scripts/common/Common.psm1") -Force
}

Describe "jira-workflows: operation classification" {
    It "classifies jira.workflow.get as READ_ONLY" {
        Get-OperationClassification -OperationKey "jira.workflow.get" | Should -Be "READ_ONLY"
    }
    It "classifies jira.workflow.update as ADMINISTRATIVE (even though unimplemented)" {
        Get-OperationClassification -OperationKey "jira.workflow.update" | Should -Be "ADMINISTRATIVE"
    }
}

Describe "jira-workflows: write scope" {
    It "has no write script (update is NOT IMPLEMENTED by design)" {
        $writeScripts = Get-ChildItem -Path (Join-Path $PSScriptRoot "../scripts/windows") -Filter "update-*.ps1" -ErrorAction SilentlyContinue
        $writeScripts.Count | Should -Be 0
    }
}
