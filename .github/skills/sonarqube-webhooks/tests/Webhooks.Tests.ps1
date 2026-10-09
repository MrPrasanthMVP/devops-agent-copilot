#Requires -Modules Pester
<#
    Unit tests for sonarqube-webhooks. No live SonarQube credentials required.
    Run: Invoke-Pester .github/skills/sonarqube-webhooks/tests/
#>

BeforeAll {
    $repoRoot = (Resolve-Path "$PSScriptRoot/../../../..").Path
    Import-Module (Join-Path $repoRoot "scripts/common/Common.psm1") -Force
}

Describe "sonarqube-webhooks: approval enforcement" {
    It "MUST NOT allow create-webhook.ps1 to proceed without approval" {
        $scriptPath = Join-Path $PSScriptRoot "../scripts/windows/create-webhook.ps1"
        $opId = "op-test-no-approval-$(Get-Random)"
        { & $scriptPath -BaseUrl "https://fake.invalid" -Name "ci-notify" -Url "https://ci.example.invalid/hook" `
            -User "tester" -OperationId $opId -ErrorAction Stop } | Should -Throw
    }
    It "MUST NOT allow delete-webhook.ps1 to proceed without approval" {
        $scriptPath = Join-Path $PSScriptRoot "../scripts/windows/delete-webhook.ps1"
        $opId = "op-test-no-approval-$(Get-Random)"
        { & $scriptPath -BaseUrl "https://fake.invalid" -WebhookKey AbCd1234 `
            -User "tester" -OperationId $opId -ErrorAction Stop } | Should -Throw
    }
}

Describe "sonarqube-webhooks: operation classification" {
    It "classifies webhook.list as READ_ONLY" {
        Get-OperationClassification -OperationKey "sonarqube.webhook.list" | Should -Be "READ_ONLY"
    }
    It "classifies webhook.create as WRITE" {
        Get-OperationClassification -OperationKey "sonarqube.webhook.create" | Should -Be "WRITE"
    }
    It "classifies webhook.delete as DESTRUCTIVE" {
        Get-OperationClassification -OperationKey "sonarqube.webhook.delete" | Should -Be "DESTRUCTIVE"
    }
}
