#Requires -Modules Pester
<#
    Pester tests for the jira-admin skill's risk classification and
    fail-closed approval binding (requirement.md Section 32, 43:
    "No approval -> MUST NOT EXECUTE"). No live Jira credentials needed.
    Run from repo root: Invoke-Pester .github/skills/jira-admin/tests/
#>

BeforeAll {
    $repoRoot = (Resolve-Path "$PSScriptRoot/../../../..").Path
    Import-Module (Join-Path $repoRoot "scripts/common/Common.psm1") -Force
    $approvalsDir = Join-Path $repoRoot "logs/.approvals"
    if (Test-Path $approvalsDir) { Remove-Item "$approvalsDir/op-test-jiraadmin-*" -Force -ErrorAction SilentlyContinue }
}

Describe "jira-admin operation classification" {

    It "classifies 'jira.admin.get' as READ_ONLY" {
        $classification = Get-OperationClassification -OperationKey "jira.admin.get"
        $classification | Should -Be "READ_ONLY"
    }

    It "classifies 'jira.project.create' as ADMINISTRATIVE" {
        $classification = Get-OperationClassification -OperationKey "jira.project.create"
        $classification | Should -Be "ADMINISTRATIVE"
    }

    It "classifies 'jira.admin.update' as ADMINISTRATIVE" {
        $classification = Get-OperationClassification -OperationKey "jira.admin.update"
        $classification | Should -Be "ADMINISTRATIVE"
    }

    It "throws (fails closed) for an unclassified operation key" {
        { Get-OperationClassification -OperationKey "jira.admin.nonexistent_operation" } | Should -Throw
    }
}

Describe "jira-admin approval binding (fail-closed)" {

    It "rejects CREATE PROJECT execution when no approval record exists" {
        $result = Test-ApprovalToken -OperationId "op-test-jiraadmin-nonexistent" -System "jira" `
            -Target "NEWPRJ" -Operation "jira.project.create" -ExpectedApprovalType "APPROVE ADMIN CHANGE"
        $result.Valid | Should -Be $false
    }

    It "accepts an approval that exactly matches system/target/operation/type" {
        $opId = "op-test-jiraadmin-match-$(Get-Random)"
        New-ApprovalToken -OperationId $opId -User "tester" -System "jira" `
            -Target "NEWPRJ" -Operation "jira.project.create" -Risk "ADMINISTRATIVE" `
            -ApprovalType "APPROVE ADMIN CHANGE" | Out-Null

        $result = Test-ApprovalToken -OperationId $opId -System "jira" `
            -Target "NEWPRJ" -Operation "jira.project.create" -ExpectedApprovalType "APPROVE ADMIN CHANGE"
        $result.Valid | Should -Be $true
    }

    It "rejects an approval presented against a DIFFERENT project key" {
        $opId = "op-test-jiraadmin-crosstarget-$(Get-Random)"
        New-ApprovalToken -OperationId $opId -User "tester" -System "jira" `
            -Target "PROJECT-A" -Operation "jira.project.create" -Risk "ADMINISTRATIVE" `
            -ApprovalType "APPROVE ADMIN CHANGE" | Out-Null

        $result = Test-ApprovalToken -OperationId $opId -System "jira" `
            -Target "PROJECT-B" -Operation "jira.project.create" -ExpectedApprovalType "APPROVE ADMIN CHANGE"
        $result.Valid | Should -Be $false
    }

    It "rejects an approval whose type does not satisfy the required phrase" {
        $opId = "op-test-jiraadmin-wrongtype-$(Get-Random)"
        New-ApprovalToken -OperationId $opId -User "tester" -System "jira" `
            -Target "NEWPRJ" -Operation "jira.project.create" -Risk "ADMINISTRATIVE" `
            -ApprovalType "APPROVE UPDATE" | Out-Null

        $result = Test-ApprovalToken -OperationId $opId -System "jira" `
            -Target "NEWPRJ" -Operation "jira.project.create" -ExpectedApprovalType "APPROVE ADMIN CHANGE"
        $result.Valid | Should -Be $false
    }

    It "rejects a consumed approval on reuse" {
        $opId = "op-test-jiraadmin-reuse-$(Get-Random)"
        New-ApprovalToken -OperationId $opId -User "tester" -System "jira" `
            -Target "NEWPRJ" -Operation "jira.project.create" -Risk "ADMINISTRATIVE" `
            -ApprovalType "APPROVE ADMIN CHANGE" | Out-Null
        Set-ApprovalConsumed -OperationId $opId

        $result = Test-ApprovalToken -OperationId $opId -System "jira" `
            -Target "NEWPRJ" -Operation "jira.project.create" -ExpectedApprovalType "APPROVE ADMIN CHANGE"
        $result.Valid | Should -Be $false
    }
}

AfterAll {
    $repoRoot = (Resolve-Path "$PSScriptRoot/../../../..").Path
    Remove-Item "$repoRoot/logs/.approvals/op-test-jiraadmin-*" -Force -ErrorAction SilentlyContinue
}
