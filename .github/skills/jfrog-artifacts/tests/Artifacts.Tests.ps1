#Requires -Modules Pester
<#
    Unit tests for jfrog-artifacts. No live JFrog credentials required.
    Run: Invoke-Pester .github/skills/jfrog-artifacts/tests/
#>

BeforeAll {
    $repoRoot = (Resolve-Path "$PSScriptRoot/../../../..").Path
    Import-Module (Join-Path $repoRoot "scripts/common/Common.psm1") -Force
}

Describe "jfrog-artifacts: approval enforcement" {
    It "MUST NOT allow upload-artifact.ps1 to proceed without approval" {
        $scriptPath = Join-Path $PSScriptRoot "../scripts/windows/upload-artifact.ps1"
        $tempFile = Join-Path ([System.IO.Path]::GetTempPath()) "test-artifact-$(Get-Random).txt"
        "test content" | Set-Content -Path $tempFile
        $opId = "op-test-no-approval-$(Get-Random)"
        try {
            { & $scriptPath -BaseUrl "https://fake.invalid" -RepoKey test-repo `
                -ItemPath "test/app.jar" -LocalFilePath $tempFile `
                -User "tester" -OperationId $opId -ErrorAction Stop } | Should -Throw
        }
        finally { Remove-Item $tempFile -Force -ErrorAction SilentlyContinue }
    }

    It "rejects path traversal in ItemPath" {
        $scriptPath = Join-Path $PSScriptRoot "../scripts/windows/get-artifact-info.ps1"
        { & $scriptPath -BaseUrl "https://fake.invalid" -RepoKey test-repo `
            -ItemPath "../../etc/passwd" -User "tester" -ErrorAction Stop } | Should -Throw
    }
}

Describe "jfrog-artifacts: operation classification" {
    It "classifies artifact.get as READ_ONLY" {
        Get-OperationClassification -OperationKey "jfrog.artifact.get" | Should -Be "READ_ONLY"
    }
    It "classifies artifact.upload as WRITE" {
        Get-OperationClassification -OperationKey "jfrog.artifact.upload" | Should -Be "WRITE"
    }
}
