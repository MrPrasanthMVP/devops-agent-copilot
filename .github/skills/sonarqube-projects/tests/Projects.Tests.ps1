#Requires -Modules Pester
<#
    Unit tests for sonarqube-projects. No live SonarQube credentials required.
    Run: Invoke-Pester .github/skills/sonarqube-projects/tests/
#>

BeforeAll {
    $repoRoot = (Resolve-Path "$PSScriptRoot/../../../..").Path
    Import-Module (Join-Path $repoRoot "scripts/common/Common.psm1") -Force
}

Describe "sonarqube-projects: approval enforcement" {
    It "MUST NOT allow create-project.ps1 to proceed without approval" {
        $scriptPath = Join-Path $PSScriptRoot "../scripts/windows/create-project.ps1"
        $opId = "op-test-no-approval-$(Get-Random)"
        { & $scriptPath -BaseUrl "https://fake.invalid" -ProjectKey test-proj -ProjectName "Test Project" `
            -User "tester" -OperationId $opId -ErrorAction Stop } | Should -Throw
    }
    It "MUST NOT allow delete-project.ps1 to proceed without approval" {
        $scriptPath = Join-Path $PSScriptRoot "../scripts/windows/delete-project.ps1"
        $opId = "op-test-no-approval-$(Get-Random)"
        { & $scriptPath -BaseUrl "https://fake.invalid" -ProjectKey test-proj `
            -User "tester" -OperationId $opId -ErrorAction Stop } | Should -Throw
    }
}

Describe "sonarqube-projects: operation classification" {
    It "classifies project.list as READ_ONLY" {
        Get-OperationClassification -OperationKey "sonarqube.project.list" | Should -Be "READ_ONLY"
    }
    It "classifies project.get as READ_ONLY" {
        Get-OperationClassification -OperationKey "sonarqube.project.get" | Should -Be "READ_ONLY"
    }
    It "classifies project.create as WRITE" {
        Get-OperationClassification -OperationKey "sonarqube.project.create" | Should -Be "WRITE"
    }
    It "classifies project.delete as DESTRUCTIVE" {
        Get-OperationClassification -OperationKey "sonarqube.project.delete" | Should -Be "DESTRUCTIVE"
    }
}
