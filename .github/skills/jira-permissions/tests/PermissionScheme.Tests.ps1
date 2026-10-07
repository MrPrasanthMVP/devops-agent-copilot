#Requires -Modules Pester
<#
    Unit tests for jira-permissions. Uses mocked/absent HTTP responses -
    no live Jira credentials required (requirement.md Section 44).
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
    It "MUST NOT allow add-permission-grant.ps1 to proceed without a valid approval" {
        $scriptPath = Join-Path $PSScriptRoot "../scripts/windows/add-permission-grant.ps1"
        $fakeToken = ConvertTo-SecureString -String "fake" -AsPlainText -Force
        $opId = "op-test-no-approval-$(Get-Random)"
        { & $scriptPath -SiteUrl "https://fake.invalid" -SchemeId "10000" `
            -HolderType "group" -HolderParameter "qa-team" -PermissionKey "BROWSE_PROJECTS" `
            -Email "a@b.com" -ApiToken $fakeToken -User "tester" -OperationId $opId `
            -ErrorAction Stop } | Should -Throw
    }

    It "MUST reject an approval record issued for a different scheme (no cross-target reuse)" {
        $repoRoot = (Resolve-Path "$PSScriptRoot/../../../..").Path
        $opId = "op-test-wrong-target-$(Get-Random)"
        New-ApprovalToken -OperationId $opId -User "tester" -System "jira" `
            -Target "99999" -Operation "jira.permissions.update" -Risk "SECURITY_SENSITIVE" `
            -ApprovalType "APPROVE PERMISSION CHANGE" | Out-Null

        $result = Test-ApprovalToken -OperationId $opId -System "jira" -Target "10000" `
            -Operation "jira.permissions.update" -ExpectedApprovalType "APPROVE PERMISSION CHANGE"

        $result.Valid | Should -Be $false

        # cleanup
        $approvalPath = Join-Path $repoRoot "logs/.approvals/$opId.json"
        if (Test-Path $approvalPath) { Remove-Item $approvalPath -Force }
    }
}
