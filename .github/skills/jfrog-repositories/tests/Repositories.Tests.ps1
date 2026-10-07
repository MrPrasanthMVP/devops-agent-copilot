#Requires -Modules Pester
<#
    Unit tests for jfrog-repositories. No live JFrog credentials required.
    Run: Invoke-Pester .github/skills/jfrog-repositories/tests/
#>

BeforeAll {
    $repoRoot = (Resolve-Path "$PSScriptRoot/../../../..").Path
    Import-Module (Join-Path $repoRoot "scripts/common/Common.psm1") -Force
}

Describe "jfrog-repositories: approval enforcement" {
    It "MUST NOT allow create-repository.ps1 to proceed without approval" {
        $scriptPath = Join-Path $PSScriptRoot "../scripts/windows/create-repository.ps1"
        $opId = "op-test-no-approval-$(Get-Random)"
        { & $scriptPath -BaseUrl "https://fake.invalid" -RepoKey test-repo -RClass local `
            -PackageType generic -User "tester" -OperationId $opId -ErrorAction Stop } | Should -Throw
    }
    It "MUST NOT allow delete-repository.ps1 to proceed without approval" {
        $scriptPath = Join-Path $PSScriptRoot "../scripts/windows/delete-repository.ps1"
        $opId = "op-test-no-approval-$(Get-Random)"
        { & $scriptPath -BaseUrl "https://fake.invalid" -RepoKey test-repo `
            -User "tester" -OperationId $opId -ErrorAction Stop } | Should -Throw
    }
}

Describe "jfrog-repositories: operation classification" {
    It "classifies repository.get as READ_ONLY" {
        Get-OperationClassification -OperationKey "jfrog.repository.get" | Should -Be "READ_ONLY"
    }
    It "classifies repository.create as ADMINISTRATIVE" {
        Get-OperationClassification -OperationKey "jfrog.repository.create" | Should -Be "ADMINISTRATIVE"
    }
    It "classifies repository.delete as DESTRUCTIVE" {
        Get-OperationClassification -OperationKey "jfrog.repository.delete" | Should -Be "DESTRUCTIVE"
    }
}
