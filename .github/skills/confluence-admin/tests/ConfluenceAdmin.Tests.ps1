#Requires -Modules Pester
<#
    Unit tests for confluence-admin. No live credentials required.
    Run: Invoke-Pester .github/skills/confluence-admin/tests/
#>

BeforeAll {
    $repoRoot = (Resolve-Path "$PSScriptRoot/../../../..").Path
    Import-Module (Join-Path $repoRoot "scripts/common/Common.psm1") -Force
}

Describe "confluence-admin: operation classification" {
    It "classifies confluence.admin.get as READ_ONLY" {
        Get-OperationClassification -OperationKey "confluence.admin.get" | Should -Be "READ_ONLY"
    }
    It "classifies confluence.admin.update as ADMINISTRATIVE (even though unimplemented)" {
        Get-OperationClassification -OperationKey "confluence.admin.update" | Should -Be "ADMINISTRATIVE"
    }
}

Describe "confluence-admin: write scope" {
    It "has no write script (create-space is NOT IMPLEMENTED by design)" {
        $writeScripts = Get-ChildItem -Path (Join-Path $PSScriptRoot "../scripts/windows") -Filter "create-*.ps1" -ErrorAction SilentlyContinue
        $writeScripts.Count | Should -Be 0
    }
}
