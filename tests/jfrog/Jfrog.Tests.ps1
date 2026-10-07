#Requires -Modules Pester
<#
    Cross-cutting regression guard for JFrog Artifactory, independent of
    any one Skill's own test suite (requirement.md Section 43: "No
    approval -> MUST NOT EXECUTE"). No live credentials are used.

    Run: Invoke-Pester tests/jfrog/
#>

BeforeAll {
    $repoRoot = (Resolve-Path "$PSScriptRoot/../..").Path
    Import-Module (Join-Path $repoRoot "scripts/common/Common.psm1") -Force
}

Describe "JFrog operation classification" {
    It "classifies 'jfrog.artifact.delete' as DESTRUCTIVE" {
        Get-OperationClassification -OperationKey "jfrog.artifact.delete" | Should -Be "DESTRUCTIVE"
    }
    It "classifies 'jfrog.repository.create' as ADMINISTRATIVE" {
        Get-OperationClassification -OperationKey "jfrog.repository.create" | Should -Be "ADMINISTRATIVE"
    }
    It "classifies 'jfrog.permissions.update' as SECURITY_SENSITIVE" {
        Get-OperationClassification -OperationKey "jfrog.permissions.update" | Should -Be "SECURITY_SENSITIVE"
    }
}

Describe "JFrog: No approval -> MUST NOT EXECUTE" {

    $cases = @(
        @{ Name = "jfrog-cleanup delete-artifacts"; Script = ".github/skills/jfrog-cleanup/scripts/windows/delete-artifacts.ps1";
           Args = @{ BaseUrl = "https://fake.invalid"; Repository = "releases-local"; CandidatePaths = @("a/b.jar"); User = "tester"; OperationId = "op-missing-jfrog-1" } }
        @{ Name = "jfrog-repositories delete-repository"; Script = ".github/skills/jfrog-repositories/scripts/windows/delete-repository.ps1";
           Args = @{ BaseUrl = "https://fake.invalid"; RepoKey = "old-unused-local"; User = "tester"; OperationId = "op-missing-jfrog-2" } }
    )

    foreach ($case in $cases) {
        It "[$($case.Name)] refuses to execute without a valid approval record" {
            $scriptPath = Join-Path $repoRoot $case.Script
            { & $scriptPath @($case.Args) -ErrorAction Stop } | Should -Throw
        }
    }

    It "an approval issued for one repository cannot authorize a delete in a different one" {
        $opId = "op-jfrog-crosscheck-$(Get-Random)"
        New-ApprovalToken -OperationId $opId -User "tester" -System "jfrog" `
            -Target "releases-local" -Operation "jfrog.artifact.delete" -Risk "DESTRUCTIVE" `
            -ApprovalType "APPROVE DELETE" | Out-Null

        $result = Test-ApprovalToken -OperationId $opId -System "jfrog" `
            -Target "other-repo-local" -Operation "jfrog.artifact.delete" -ExpectedApprovalType "APPROVE DELETE"

        $result.Valid | Should -Be $false
    }
}

AfterAll {
    $repoRoot = (Resolve-Path "$PSScriptRoot/../..").Path
    Remove-Item "$repoRoot/logs/.approvals/op-jfrog-*" -Force -ErrorAction SilentlyContinue
    Remove-Item "$repoRoot/logs/.approvals/op-missing-jfrog-*" -Force -ErrorAction SilentlyContinue
}
