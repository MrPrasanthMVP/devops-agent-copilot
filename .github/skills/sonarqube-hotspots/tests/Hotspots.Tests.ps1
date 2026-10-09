#Requires -Modules Pester
<#
    Unit tests for sonarqube-hotspots. No live SonarQube credentials required.
    Run: Invoke-Pester .github/skills/sonarqube-hotspots/tests/
#>

BeforeAll {
    $repoRoot = (Resolve-Path "$PSScriptRoot/../../../..").Path
    Import-Module (Join-Path $repoRoot "scripts/common/Common.psm1") -Force
}

Describe "sonarqube-hotspots: approval enforcement" {
    It "MUST NOT allow change-hotspot-status.ps1 to proceed without approval" {
        $scriptPath = Join-Path $PSScriptRoot "../scripts/windows/change-hotspot-status.ps1"
        $opId = "op-test-no-approval-$(Get-Random)"
        { & $scriptPath -BaseUrl "https://fake.invalid" -HotspotKey AbCd1234 -Status REVIEWED -Resolution FIXED `
            -User "tester" -OperationId $opId -ErrorAction Stop } | Should -Throw
    }
}

Describe "sonarqube-hotspots: operation classification" {
    It "classifies hotspot.search as READ_ONLY" {
        Get-OperationClassification -OperationKey "sonarqube.hotspot.search" | Should -Be "READ_ONLY"
    }
    It "classifies hotspot.get as READ_ONLY" {
        Get-OperationClassification -OperationKey "sonarqube.hotspot.get" | Should -Be "READ_ONLY"
    }
    It "classifies hotspot.change_status as WRITE" {
        Get-OperationClassification -OperationKey "sonarqube.hotspot.change_status" | Should -Be "WRITE"
    }
}
