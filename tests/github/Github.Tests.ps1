#Requires -Modules Pester
<#
    Cross-cutting regression guard for GitHub Enterprise, independent of
    any one Skill's own test suite (requirement.md Section 43: "No
    approval -> MUST NOT EXECUTE"). No live credentials are used.

    Run: Invoke-Pester tests/github/
#>

BeforeAll {
    $repoRoot = (Resolve-Path "$PSScriptRoot/../..").Path
    Import-Module (Join-Path $repoRoot "scripts/common/Common.psm1") -Force
}

Describe "GitHub operation classification" {
    It "classifies 'github.branch_protection.update' as ADMINISTRATIVE" {
        Get-OperationClassification -OperationKey "github.branch_protection.update" | Should -Be "ADMINISTRATIVE"
    }
    It "classifies 'github.repository.delete' as DESTRUCTIVE" {
        Get-OperationClassification -OperationKey "github.repository.delete" | Should -Be "DESTRUCTIVE"
    }
    It "classifies 'github.webhook.create' as SECURITY_SENSITIVE" {
        Get-OperationClassification -OperationKey "github.webhook.create" | Should -Be "SECURITY_SENSITIVE"
    }
}

Describe "GitHub: No approval -> MUST NOT EXECUTE" {

    It "update-branch-protection.ps1 refuses to execute without a valid approval record" {
        $scriptPath = Join-Path $repoRoot ".github/skills/github-branch-protection/scripts/windows/update-branch-protection.ps1"
        {
            & $scriptPath -ApiBaseUrl "https://fake.invalid" -Owner "org" -Repo "repo" -Branch "main" `
                -RequiredApprovingReviewCount 2 -EnforceAdmins $true -User "tester" `
                -OperationId "op-missing-gh-1" -ErrorAction Stop
        } | Should -Throw
    }

    It "an approval issued for one branch cannot authorize updating a different one" {
        $opId = "op-gh-crosscheck-$(Get-Random)"
        New-ApprovalToken -OperationId $opId -User "tester" -System "github" `
            -Target "org/repo@main" -Operation "github.branch_protection.update" -Risk "ADMINISTRATIVE" `
            -ApprovalType "APPROVE BRANCH PROTECTION" | Out-Null

        $result = Test-ApprovalToken -OperationId $opId -System "github" `
            -Target "org/repo@develop" -Operation "github.branch_protection.update" -ExpectedApprovalType "APPROVE BRANCH PROTECTION"

        $result.Valid | Should -Be $false
    }

    It "rejects a consumed approval on reuse" {
        $opId = "op-gh-reuse-$(Get-Random)"
        New-ApprovalToken -OperationId $opId -User "tester" -System "github" `
            -Target "org/repo2" -Operation "github.repository.delete" -Risk "DESTRUCTIVE" `
            -ApprovalType "APPROVE DELETE" | Out-Null
        Set-ApprovalConsumed -OperationId $opId

        $result = Test-ApprovalToken -OperationId $opId -System "github" `
            -Target "org/repo2" -Operation "github.repository.delete" -ExpectedApprovalType "APPROVE DELETE"

        $result.Valid | Should -Be $false
    }
}

AfterAll {
    $repoRoot = (Resolve-Path "$PSScriptRoot/../..").Path
    Remove-Item "$repoRoot/logs/.approvals/op-gh-*" -Force -ErrorAction SilentlyContinue
    Remove-Item "$repoRoot/logs/.approvals/op-missing-gh-*" -Force -ErrorAction SilentlyContinue
}
