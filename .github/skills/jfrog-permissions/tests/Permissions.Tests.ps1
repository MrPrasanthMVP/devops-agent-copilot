#Requires -Modules Pester
<#
    Unit tests for jfrog-permissions. No live JFrog credentials required.
    Run: Invoke-Pester .github/skills/jfrog-permissions/tests/
#>

BeforeAll {
    $repoRoot = (Resolve-Path "$PSScriptRoot/../../../..").Path
    Import-Module (Join-Path $repoRoot "scripts/common/Common.psm1") -Force
}

Describe "jfrog-permissions: approval enforcement" {
    It "MUST NOT allow set-permission-target.ps1 to proceed without approval" {
        $scriptPath = Join-Path $PSScriptRoot "../scripts/windows/set-permission-target.ps1"
        $opId = "op-test-no-approval-$(Get-Random)"
        { & $scriptPath -BaseUrl "https://fake.invalid" -PermissionTargetName test-perm `
            -BodyJson '{"name":"test-perm"}' -User "tester" -OperationId $opId -ErrorAction Stop } | Should -Throw
    }
}

Describe "jfrog-permissions: operation classification" {
    It "classifies permissions.get as READ_ONLY" {
        Get-OperationClassification -OperationKey "jfrog.permissions.get" | Should -Be "READ_ONLY"
    }
    It "classifies permissions.update as SECURITY_SENSITIVE" {
        Get-OperationClassification -OperationKey "jfrog.permissions.update" | Should -Be "SECURITY_SENSITIVE"
    }
}
