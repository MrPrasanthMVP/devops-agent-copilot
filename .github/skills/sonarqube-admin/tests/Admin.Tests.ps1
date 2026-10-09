#Requires -Modules Pester
<#
    Unit tests for sonarqube-admin. No live SonarQube credentials required.
    Server-only: all three scripted operations are READ_ONLY, so there is
    no approval-enforcement surface to test here (unlike the other
    sonarqube-* skills, which each have at least one WRITE/DESTRUCTIVE op).
    Run: Invoke-Pester .github/skills/sonarqube-admin/tests/
#>

BeforeAll {
    $repoRoot = (Resolve-Path "$PSScriptRoot/../../../..").Path
    Import-Module (Join-Path $repoRoot "scripts/common/Common.psm1") -Force
}

Describe "sonarqube-admin: operation classification" {
    It "classifies system.health as READ_ONLY" {
        Get-OperationClassification -OperationKey "sonarqube.system.health" | Should -Be "READ_ONLY"
    }
    It "classifies system.info as READ_ONLY" {
        Get-OperationClassification -OperationKey "sonarqube.system.info" | Should -Be "READ_ONLY"
    }
    It "classifies system.ping as READ_ONLY" {
        Get-OperationClassification -OperationKey "sonarqube.system.ping" | Should -Be "READ_ONLY"
    }
}
