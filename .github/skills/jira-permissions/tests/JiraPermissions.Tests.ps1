#Requires -Modules Pester
<#
    Unit tests for jira-permissions. No live credentials required.
    Run: Invoke-Pester .github/skills/jira-permissions/tests/
#>

BeforeAll {
    $repoRoot = (Resolve-Path "$PSScriptRoot/../../../..").Path
    Import-Module (Join-Path $repoRoot "scripts/common/Common.psm1") -Force
}

Describe "jira-permissions: operation classification" {
    It "classifies jira.permissions.get as READ_ONLY" {
        Get-OperationClassification -OperationKey "jira.permissions.get" | Should -Be "READ_ONLY"
    }
    It "classifies jira.permissions.update as SECURITY_SENSITIVE" {
        Get-OperationClassification -OperationKey "jira.permissions.update" | Should -Be "SECURITY_SENSITIVE"
    }
}

Describe "jira-permissions: approval enforcement" {
    It "MUST NOT allow add-permission-grant.ps1 to proceed without approval" {
        $scriptPath = Join-Path $PSScriptRoot "../scripts/windows/add-permission-grant.ps1"
        $fakeToken = ConvertTo-SecureString -String "fake" -AsPlainText -Force
        $opId = "op-test-no-approval-$(Get-Random)"
        { & $scriptPath -SiteUrl "https://fake.invalid" -SchemeId "10000" -PermissionKey "ADMINISTER_PROJECTS" `
            -HolderType group -HolderParameter "platform-eng" -Email "a@b.com" -ApiToken $fakeToken `
            -User "tester" -OperationId $opId -ErrorAction Stop } | Should -Throw
    }
}
