#Requires -Modules Pester
<#
    Cross-cutting regression guard for Confluence Cloud, independent of
    any one Skill's own test suite (requirement.md Section 43: "No
    approval -> MUST NOT EXECUTE"). No live credentials are used.

    Run: Invoke-Pester tests/confluence/
#>

BeforeAll {
    $repoRoot = (Resolve-Path "$PSScriptRoot/../..").Path
    Import-Module (Join-Path $repoRoot "scripts/common/Common.psm1") -Force
    $dummyToken = ConvertTo-SecureString "dummy-test-token" -AsPlainText -Force
}

Describe "Confluence operation classification" {
    It "classifies 'confluence.page.update' as WRITE" {
        Get-OperationClassification -OperationKey "confluence.page.update" | Should -Be "WRITE"
    }
    It "classifies 'confluence.admin.update' as ADMINISTRATIVE" {
        Get-OperationClassification -OperationKey "confluence.admin.update" | Should -Be "ADMINISTRATIVE"
    }
    It "classifies 'confluence.permissions.update' as SECURITY_SENSITIVE" {
        Get-OperationClassification -OperationKey "confluence.permissions.update" | Should -Be "SECURITY_SENSITIVE"
    }
}

Describe "Confluence: No approval -> MUST NOT EXECUTE" {

    It "update-page.ps1 refuses to execute without a valid approval record" {
        $scriptPath = Join-Path $repoRoot ".github/skills/confluence-pages/scripts/windows/update-page.ps1"
        {
            & $scriptPath -SiteUrl "https://fake.invalid" -PageId "123456" -CurrentVersion 4 `
                -Title "Test Page" -BodyStorageValue "<p>new</p>" -Email "tester@example.com" `
                -ApiToken $dummyToken -User "tester" -OperationId "op-missing-conf-1" -ErrorAction Stop
        } | Should -Throw
    }

    It "an approval issued for one page cannot authorize updating a different one" {
        $opId = "op-conf-crosscheck-$(Get-Random)"
        New-ApprovalToken -OperationId $opId -User "tester" -System "confluence" `
            -Target "123456" -Operation "confluence.page.update" -Risk "WRITE" `
            -ApprovalType "APPROVE UPDATE" | Out-Null

        $result = Test-ApprovalToken -OperationId $opId -System "confluence" `
            -Target "999999" -Operation "confluence.page.update" -ExpectedApprovalType "APPROVE UPDATE"

        $result.Valid | Should -Be $false
    }

    It "rejects a consumed approval on reuse" {
        $opId = "op-conf-reuse-$(Get-Random)"
        New-ApprovalToken -OperationId $opId -User "tester" -System "confluence" `
            -Target "123457" -Operation "confluence.page.update" -Risk "WRITE" `
            -ApprovalType "APPROVE UPDATE" | Out-Null
        Set-ApprovalConsumed -OperationId $opId

        $result = Test-ApprovalToken -OperationId $opId -System "confluence" `
            -Target "123457" -Operation "confluence.page.update" -ExpectedApprovalType "APPROVE UPDATE"

        $result.Valid | Should -Be $false
    }
}

AfterAll {
    $repoRoot = (Resolve-Path "$PSScriptRoot/../..").Path
    Remove-Item "$repoRoot/logs/.approvals/op-conf-*" -Force -ErrorAction SilentlyContinue
    Remove-Item "$repoRoot/logs/.approvals/op-missing-conf-*" -Force -ErrorAction SilentlyContinue
}
