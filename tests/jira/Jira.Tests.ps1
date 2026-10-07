#Requires -Modules Pester
<#
    Cross-cutting regression guard for Jira Cloud, independent of any
    one Skill's own test suite (requirement.md Section 43: "No approval
    -> MUST NOT EXECUTE"). No live credentials are used.

    Run: Invoke-Pester tests/jira/
#>

BeforeAll {
    $repoRoot = (Resolve-Path "$PSScriptRoot/../..").Path
    Import-Module (Join-Path $repoRoot "scripts/common/Common.psm1") -Force
    $dummyToken = ConvertTo-SecureString "dummy-test-token" -AsPlainText -Force
}

Describe "Jira operation classification" {
    It "classifies 'jira.issue.update' as WRITE" {
        Get-OperationClassification -OperationKey "jira.issue.update" | Should -Be "WRITE"
    }
    It "classifies 'jira.issue.delete' as DESTRUCTIVE" {
        Get-OperationClassification -OperationKey "jira.issue.delete" | Should -Be "DESTRUCTIVE"
    }
    It "classifies 'jira.permissions.update' as SECURITY_SENSITIVE" {
        Get-OperationClassification -OperationKey "jira.permissions.update" | Should -Be "SECURITY_SENSITIVE"
    }
}

Describe "Jira: No approval -> MUST NOT EXECUTE" {

    It "update-issue-field.ps1 refuses to execute without a valid approval record" {
        $scriptPath = Join-Path $repoRoot ".github/skills/jira-issues/scripts/windows/update-issue-field.ps1"
        {
            & $scriptPath -SiteUrl "https://fake.invalid" -IssueKey "ABC-123" -FieldName "priority" `
                -FieldValueJson '{"name":"P1"}' -Email "tester@example.com" -ApiToken $dummyToken `
                -User "tester" -OperationId "op-missing-jira-1" -ErrorAction Stop
        } | Should -Throw
    }

    It "an approval issued for one issue cannot authorize updating a different one" {
        $opId = "op-jira-crosscheck-$(Get-Random)"
        New-ApprovalToken -OperationId $opId -User "tester" -System "jira" `
            -Target "ABC-123" -Operation "jira.issue.update" -Risk "WRITE" `
            -ApprovalType "APPROVE UPDATE" | Out-Null

        $result = Test-ApprovalToken -OperationId $opId -System "jira" `
            -Target "ABC-124" -Operation "jira.issue.update" -ExpectedApprovalType "APPROVE UPDATE"

        $result.Valid | Should -Be $false
    }

    It "rejects a consumed approval on reuse" {
        $opId = "op-jira-reuse-$(Get-Random)"
        New-ApprovalToken -OperationId $opId -User "tester" -System "jira" `
            -Target "ABC-125" -Operation "jira.issue.update" -Risk "WRITE" `
            -ApprovalType "APPROVE UPDATE" | Out-Null
        Set-ApprovalConsumed -OperationId $opId

        $result = Test-ApprovalToken -OperationId $opId -System "jira" `
            -Target "ABC-125" -Operation "jira.issue.update" -ExpectedApprovalType "APPROVE UPDATE"

        $result.Valid | Should -Be $false
    }
}

AfterAll {
    $repoRoot = (Resolve-Path "$PSScriptRoot/../..").Path
    Remove-Item "$repoRoot/logs/.approvals/op-jira-*" -Force -ErrorAction SilentlyContinue
    Remove-Item "$repoRoot/logs/.approvals/op-missing-jira-*" -Force -ErrorAction SilentlyContinue
}
