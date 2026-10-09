#Requires -Modules Pester
<#
    Unit tests for sonarqube-quality-gates. No live SonarQube credentials required.
    Run: Invoke-Pester .github/skills/sonarqube-quality-gates/tests/
#>

BeforeAll {
    $repoRoot = (Resolve-Path "$PSScriptRoot/../../../..").Path
    Import-Module (Join-Path $repoRoot "scripts/common/Common.psm1") -Force
}

Describe "sonarqube-quality-gates: approval enforcement" {
    It "MUST NOT allow select-quality-gate.ps1 to proceed without approval" {
        $scriptPath = Join-Path $PSScriptRoot "../scripts/windows/select-quality-gate.ps1"
        $opId = "op-test-no-approval-$(Get-Random)"
        { & $scriptPath -BaseUrl "https://fake.invalid" -ProjectKey test-proj -GateName "Sonar way" `
            -User "tester" -OperationId $opId -ErrorAction Stop } | Should -Throw
    }
}

Describe "sonarqube-quality-gates: operation classification" {
    It "classifies quality_gate.list as READ_ONLY" {
        Get-OperationClassification -OperationKey "sonarqube.quality_gate.list" | Should -Be "READ_ONLY"
    }
    It "classifies quality_gate.status as READ_ONLY" {
        Get-OperationClassification -OperationKey "sonarqube.quality_gate.status" | Should -Be "READ_ONLY"
    }
    It "classifies quality_gate.select as WRITE" {
        Get-OperationClassification -OperationKey "sonarqube.quality_gate.select" | Should -Be "WRITE"
    }
}
