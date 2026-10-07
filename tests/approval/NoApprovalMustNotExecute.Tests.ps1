#Requires -Modules Pester
<#
    Cross-system regression guard for requirement.md Section 43's single
    most important test: "No approval -> MUST NOT EXECUTE". Exercises a
    representative destructive/administrative script from EACH
    integrated system in one place, independent of any one Skill's own
    test suite. No live credentials are used - every script call fails
    at the approval-check stage before any network call would occur.

    Run: Invoke-Pester tests/approval/
#>

BeforeAll {
    $repoRoot = (Resolve-Path "$PSScriptRoot/../..").Path
    Import-Module (Join-Path $repoRoot "scripts/common/Common.psm1") -Force
}

Describe "No approval -> MUST NOT EXECUTE (cross-system)" {

    $cases = @(
        @{ System = "bitbucket"; Script = ".github/skills/bitbucket-repository-admin/scripts/windows/delete-repository.ps1";
           Args = @{ BaseUrl = "https://fake.invalid"; ProjectKey = "ABC"; RepositorySlug = "TEST"; User = "tester"; OperationId = "op-missing" } }
        @{ System = "jfrog"; Script = ".github/skills/jfrog-cleanup/scripts/windows/delete-artifacts.ps1";
           Args = @{ BaseUrl = "https://fake.invalid"; Repository = "releases-local"; CandidatePaths = @("a/b.jar"); User = "tester"; OperationId = "op-missing" } }
        @{ System = "github"; Script = ".github/skills/github-branch-protection/scripts/windows/update-branch-protection.ps1";
           Args = @{ ApiBaseUrl = "https://fake.invalid"; Owner = "org"; Repo = "repo"; Branch = "main"; RequiredApprovingReviewCount = 2; EnforceAdmins = $true; User = "tester"; OperationId = "op-missing" } }
    )

    foreach ($case in $cases) {
        It "[$($case.System)] refuses to execute without a valid approval record" {
            $scriptPath = Join-Path $repoRoot $case.Script
            { & $scriptPath @($case.Args) -ErrorAction Stop } | Should -Throw
        }
    }

    It "an approval issued for one target cannot authorize a different target" {
        $opId = "op-crosscheck-$(Get-Random)"
        New-ApprovalToken -OperationId $opId -User "tester" -System "bitbucket" `
            -Target "ABC/A" -Operation "bitbucket.repository.delete" -Risk "DESTRUCTIVE" `
            -ApprovalType "APPROVE DELETE" | Out-Null

        $result = Test-ApprovalToken -OperationId $opId -System "bitbucket" `
            -Target "ABC/B" -Operation "bitbucket.repository.delete" -ExpectedApprovalType "APPROVE DELETE"

        $result.Valid | Should -Be $false
    }
}
