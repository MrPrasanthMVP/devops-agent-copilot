#Requires -Modules Pester
<#
    Pester tests for the human-approval skill's binding guarantees
    (requirement.md Section 32, 43: "No approval -> MUST NOT EXECUTE").
    Run from repo root: Invoke-Pester .github/skills/human-approval/tests/
#>

BeforeAll {
    $repoRoot = (Resolve-Path "$PSScriptRoot/../../../..").Path
    Import-Module (Join-Path $repoRoot "scripts/common/Common.psm1") -Force
    $approvalsDir = Join-Path $repoRoot "logs/.approvals"
    if (Test-Path $approvalsDir) { Remove-Item "$approvalsDir/op-test-*" -Force -ErrorAction SilentlyContinue }
}

Describe "Approval token binding" {

    It "rejects execution when no approval record exists" {
        $result = Test-ApprovalToken -OperationId "op-test-nonexistent" -System "bitbucket" `
            -Target "ABC/TEST" -Operation "bitbucket.repository.delete" -ExpectedApprovalType "APPROVE DELETE"
        $result.Valid | Should -Be $false
    }

    It "accepts an approval that exactly matches system/target/operation" {
        $opId = "op-test-match-$(Get-Random)"
        New-ApprovalToken -OperationId $opId -User "tester" -System "bitbucket" `
            -Target "ABC/TEST" -Operation "bitbucket.repository.delete" -Risk "DESTRUCTIVE" `
            -ApprovalType "APPROVE DELETE" | Out-Null

        $result = Test-ApprovalToken -OperationId $opId -System "bitbucket" `
            -Target "ABC/TEST" -Operation "bitbucket.repository.delete" -ExpectedApprovalType "APPROVE DELETE"
        $result.Valid | Should -Be $true
    }

    It "rejects an approval presented against a DIFFERENT target (A != B)" {
        $opId = "op-test-crosstarget-$(Get-Random)"
        New-ApprovalToken -OperationId $opId -User "tester" -System "jfrog" `
            -Target "releases-local/app/A.jar" -Operation "jfrog.artifact.delete" -Risk "DESTRUCTIVE" `
            -ApprovalType "APPROVE DELETE" | Out-Null

        $result = Test-ApprovalToken -OperationId $opId -System "jfrog" `
            -Target "releases-local/app/B.jar" -Operation "jfrog.artifact.delete" -ExpectedApprovalType "APPROVE DELETE"
        $result.Valid | Should -Be $false
    }

    It "rejects a generic affirmative as if it were an approval type" {
        { New-ApprovalToken -OperationId "op-test-generic" -User "tester" -System "github" `
            -Target "org/repo" -Operation "github.repository.delete" -Risk "DESTRUCTIVE" `
            -ApprovalType "yes" } | Should -Not -Throw
        # Even though issuance doesn't validate phrase text (the agent layer
        # must never call New-ApprovalToken from a generic affirmative in the
        # first place), verification against the REQUIRED type still fails:
        $result = Test-ApprovalToken -OperationId "op-test-generic" -System "github" `
            -Target "org/repo" -Operation "github.repository.delete" -ExpectedApprovalType "APPROVE DELETE"
        $result.Valid | Should -Be $false
    }

    It "rejects a consumed approval on reuse" {
        $opId = "op-test-reuse-$(Get-Random)"
        New-ApprovalToken -OperationId $opId -User "tester" -System "github" `
            -Target "org/repo" -Operation "github.repository.delete" -Risk "DESTRUCTIVE" `
            -ApprovalType "APPROVE DELETE" | Out-Null
        Set-ApprovalConsumed -OperationId $opId

        $result = Test-ApprovalToken -OperationId $opId -System "github" `
            -Target "org/repo" -Operation "github.repository.delete" -ExpectedApprovalType "APPROVE DELETE"
        $result.Valid | Should -Be $false
    }
}

AfterAll {
    $repoRoot = (Resolve-Path "$PSScriptRoot/../../../..").Path
    Remove-Item "$repoRoot/logs/.approvals/op-test-*" -Force -ErrorAction SilentlyContinue
}
