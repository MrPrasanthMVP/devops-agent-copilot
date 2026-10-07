#Requires -Modules Pester
<#
    Cross-cutting regression guard for Bitbucket Data Center, independent
    of any one Skill's own test suite (requirement.md Section 43: "No
    approval -> MUST NOT EXECUTE"). No live credentials are used - every
    script call fails at the approval-check stage before any network
    call would occur.

    Run: Invoke-Pester tests/bitbucket/
#>

BeforeAll {
    $repoRoot = (Resolve-Path "$PSScriptRoot/../..").Path
    Import-Module (Join-Path $repoRoot "scripts/common/Common.psm1") -Force
}

Describe "Bitbucket operation classification" {
    It "classifies 'bitbucket.repository.delete' as DESTRUCTIVE" {
        Get-OperationClassification -OperationKey "bitbucket.repository.delete" | Should -Be "DESTRUCTIVE"
    }
    It "classifies 'bitbucket.repository.get' as READ_ONLY" {
        Get-OperationClassification -OperationKey "bitbucket.repository.get" | Should -Be "READ_ONLY"
    }
    It "classifies 'bitbucket.pull_request.merge' as WRITE" {
        Get-OperationClassification -OperationKey "bitbucket.pull_request.merge" | Should -Be "WRITE"
    }
    It "classifies 'bitbucket.permissions.update' as SECURITY_SENSITIVE" {
        Get-OperationClassification -OperationKey "bitbucket.permissions.update" | Should -Be "SECURITY_SENSITIVE"
    }
}

Describe "Bitbucket: No approval -> MUST NOT EXECUTE" {

    $cases = @(
        @{ Name = "delete-repository"; Script = ".github/skills/bitbucket-repository-admin/scripts/windows/delete-repository.ps1";
           Args = @{ BaseUrl = "https://fake.invalid"; ProjectKey = "ABC"; RepositorySlug = "TEST"; User = "tester"; OperationId = "op-missing-bb-1" } }
        @{ Name = "merge-pull-request"; Script = ".github/skills/bitbucket-pull-requests/scripts/windows/merge-pull-request.ps1";
           Args = @{ BaseUrl = "https://fake.invalid"; ProjectKey = "ABC"; RepositorySlug = "app"; PullRequestId = 42; Version = 1; User = "tester"; OperationId = "op-missing-bb-2" } }
    )

    foreach ($case in $cases) {
        It "[$($case.Name)] refuses to execute without a valid approval record" {
            $scriptPath = Join-Path $repoRoot $case.Script
            { & $scriptPath @($case.Args) -ErrorAction Stop } | Should -Throw
        }
    }

    It "an approval issued for one repository cannot authorize deletion of a different one" {
        $opId = "op-bb-crosscheck-$(Get-Random)"
        New-ApprovalToken -OperationId $opId -User "tester" -System "bitbucket" `
            -Target "ABC/REPO-A" -Operation "bitbucket.repository.delete" -Risk "DESTRUCTIVE" `
            -ApprovalType "APPROVE DELETE" | Out-Null

        $result = Test-ApprovalToken -OperationId $opId -System "bitbucket" `
            -Target "ABC/REPO-B" -Operation "bitbucket.repository.delete" -ExpectedApprovalType "APPROVE DELETE"

        $result.Valid | Should -Be $false
    }

    It "an approval of the wrong type (APPROVE UPDATE) does not satisfy a DELETE requirement" {
        $opId = "op-bb-wrongtype-$(Get-Random)"
        New-ApprovalToken -OperationId $opId -User "tester" -System "bitbucket" `
            -Target "ABC/REPO-C" -Operation "bitbucket.repository.delete" -Risk "DESTRUCTIVE" `
            -ApprovalType "APPROVE UPDATE" | Out-Null

        $result = Test-ApprovalToken -OperationId $opId -System "bitbucket" `
            -Target "ABC/REPO-C" -Operation "bitbucket.repository.delete" -ExpectedApprovalType "APPROVE DELETE"

        $result.Valid | Should -Be $false
    }
}

AfterAll {
    $repoRoot = (Resolve-Path "$PSScriptRoot/../..").Path
    Remove-Item "$repoRoot/logs/.approvals/op-bb-*" -Force -ErrorAction SilentlyContinue
    Remove-Item "$repoRoot/logs/.approvals/op-missing-bb-*" -Force -ErrorAction SilentlyContinue
}
