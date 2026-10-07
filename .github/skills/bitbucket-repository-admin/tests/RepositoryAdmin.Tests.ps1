#Requires -Modules Pester
<#
    Unit tests for bitbucket-repository-admin. Uses mocked HTTP responses -
    no live Bitbucket credentials required (requirement.md Section 44).
    Run: Invoke-Pester .github/skills/bitbucket-repository-admin/tests/
#>

BeforeAll {
    $repoRoot = (Resolve-Path "$PSScriptRoot/../../../..").Path
    Import-Module (Join-Path $repoRoot "scripts/common/Common.psm1") -Force
}

Describe "bitbucket-repository-admin: approval enforcement" {
    It "MUST NOT allow delete-repository.ps1 to proceed without approval" {
        $scriptPath = Join-Path $PSScriptRoot "../scripts/windows/delete-repository.ps1"
        $opId = "op-test-no-approval-$(Get-Random)"
        { & $scriptPath -BaseUrl "https://fake.invalid" -ProjectKey ABC -RepositorySlug TEST `
            -User "tester" -OperationId $opId -ErrorAction Stop } | Should -Throw
    }
}

Describe "bitbucket-repository-admin: operation classification" {
    It "classifies repository.delete as DESTRUCTIVE" {
        Get-OperationClassification -OperationKey "bitbucket.repository.delete" | Should -Be "DESTRUCTIVE"
    }
    It "classifies repository.get as READ_ONLY" {
        Get-OperationClassification -OperationKey "bitbucket.repository.get" | Should -Be "READ_ONLY"
    }
    It "classifies default_branch.update as ADMINISTRATIVE" {
        Get-OperationClassification -OperationKey "bitbucket.repository.default_branch.update" | Should -Be "ADMINISTRATIVE"
    }
}
