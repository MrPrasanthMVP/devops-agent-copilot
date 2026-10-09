#Requires -Modules Pester
<#
    Unit tests for sonarqube-issues. No live SonarQube credentials required.
    Run: Invoke-Pester .github/skills/sonarqube-issues/tests/
#>

BeforeAll {
    $repoRoot = (Resolve-Path "$PSScriptRoot/../../../..").Path
    Import-Module (Join-Path $repoRoot "scripts/common/Common.psm1") -Force
}

Describe "sonarqube-issues: approval enforcement" {
    It "MUST NOT allow assign-issue.ps1 to proceed without approval" {
        $scriptPath = Join-Path $PSScriptRoot "../scripts/windows/assign-issue.ps1"
        $opId = "op-test-no-approval-$(Get-Random)"
        { & $scriptPath -BaseUrl "https://fake.invalid" -IssueKey AbCd1234 -Assignee jdoe `
            -User "tester" -OperationId $opId -ErrorAction Stop } | Should -Throw
    }
    It "MUST NOT allow transition-issue.ps1 to proceed without approval" {
        $scriptPath = Join-Path $PSScriptRoot "../scripts/windows/transition-issue.ps1"
        $opId = "op-test-no-approval-$(Get-Random)"
        { & $scriptPath -BaseUrl "https://fake.invalid" -IssueKey AbCd1234 -Transition resolve `
            -User "tester" -OperationId $opId -ErrorAction Stop } | Should -Throw
    }
}

Describe "sonarqube-issues: operation classification" {
    It "classifies issue.search as READ_ONLY" {
        Get-OperationClassification -OperationKey "sonarqube.issue.search" | Should -Be "READ_ONLY"
    }
    It "classifies issue.assign as WRITE" {
        Get-OperationClassification -OperationKey "sonarqube.issue.assign" | Should -Be "WRITE"
    }
    It "classifies issue.transition as WRITE" {
        Get-OperationClassification -OperationKey "sonarqube.issue.transition" | Should -Be "WRITE"
    }
}
