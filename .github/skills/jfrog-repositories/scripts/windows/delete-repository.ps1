#Requires -Version 7.0
<#
.SYNOPSIS
    DESTRUCTIVE: Deletes a JFrog Artifactory repository configuration AND
    all content inside it. Requires a pre-issued "APPROVE DELETE" approval.

.DESCRIPTION
    Purpose: Execute the DELETE stage for a repository.
    Supported OS: Windows (PowerShell 7+).
    Dependencies: scripts/common/Common.psm1
    Parameters: BaseUrl, RepoKey, User, OperationId
    Authentication: JFrog access token (POC: local-secrets).
    Required permissions: Artifactory admin permission.
    Approval requirements: MANDATORY "APPROVE DELETE" bound to this RepoKey.
    Dry-run: -WhatIf supported.
    API/MCP dependency: REST fallback
        (DELETE /artifactory/api/repositories/{repoKey}).
    Exit codes: 0 success, 6 approval denied, 7 verification failure, 1 general failure.
    Output: JSON result.
    Verification: GET after delete; expect 404/NOT_FOUND.
    Audit: writes one DESTRUCTIVE audit record.
    Security: TLS enforced; approval re-checked immediately before DELETE.

.EXAMPLE
    ./delete-repository.ps1 -BaseUrl "https://jfrog.example.com" `
        -RepoKey old-unused-local -User jdoe -OperationId op-123
#>

[CmdletBinding(SupportsShouldAction = $true)]
param(
    [Parameter(Mandatory = $true)][string]$BaseUrl,
    [Parameter(Mandatory = $true)][ValidatePattern('^[A-Za-z0-9._-]+$')][string]$RepoKey,
    [Parameter(Mandatory = $true)][string]$User,
    [Parameter(Mandatory = $true)][string]$OperationId
)

$ScriptVersion = "1.0.0"
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Import-Module (Join-Path $PSScriptRoot "../../../../../scripts/common/Common.psm1") -Force

$operationKey = "jfrog.repository.delete"
$approval = Test-ApprovalToken -OperationId $OperationId -System "jfrog" `
    -Target $RepoKey -Operation $operationKey -ExpectedApprovalType "APPROVE DELETE"

if (-not $approval.Valid) {
    Write-AuditLog -OperationId $OperationId -User $User -System "jfrog" `
        -SystemVersion "runtime-detected" -Resource "repository" -Operation "DELETE" -Target $RepoKey `
        -ExecutionMechanism "rest-api" -Skill "jfrog-repositories" `
        -Script "delete-repository.ps1" -ScriptVersion $ScriptVersion `
        -Risk "DESTRUCTIVE" -ApprovalRequired $true -ApprovalStatus "DENIED" `
        -Result "DENIED" -Verification "NOT_APPLICABLE" -Error $approval.Reason
    Write-Error "Approval check failed: $($approval.Reason)"
    exit ([int][DevOpsExitCode]::ApprovalDenied)
}

$uri = "$BaseUrl/artifactory/api/repositories/$RepoKey"

try {
    $token = Read-LocalSecret -System jfrog

    if ($PSCmdlet.ShouldProcess($RepoKey, "DELETE JFrog repository (config + content)")) {
        Invoke-SecureRestMethod -Uri $uri -Method DELETE -Token $token | Out-Null
        Set-ApprovalConsumed -OperationId $OperationId

        $verification = "UNKNOWN"; $result = "UNKNOWN"
        try {
            Invoke-SecureRestMethod -Uri $uri -Method GET -Token $token | Out-Null
            $verification = "FAILED"
        }
        catch {
            $verification = "CONFIRMED"; $result = "SUCCESS"
        }

        Write-AuditLog -OperationId $OperationId -User $User -System "jfrog" `
            -SystemVersion "runtime-detected" -Resource "repository" -Operation "DELETE" -Target $RepoKey `
            -ExecutionMechanism "rest-api" -Skill "jfrog-repositories" `
            -Script "delete-repository.ps1" -ScriptVersion $ScriptVersion `
            -Risk "DESTRUCTIVE" -ApprovalRequired $true -ApprovalStatus "APPROVED" `
            -Result $result -Verification $verification

        [pscustomobject]@{ operationId = $OperationId; target = $RepoKey; result = $result; verification = $verification } | ConvertTo-Json
        if ($verification -ne "CONFIRMED") { exit ([int][DevOpsExitCode]::VerificationFailure) }
        exit ([int][DevOpsExitCode]::Success)
    }
    else {
        Write-Host "(WhatIf) Would DELETE JFrog repository '$RepoKey' (config + ALL content). No change made."
        exit ([int][DevOpsExitCode]::Success)
    }
}
catch {
    Write-AuditLog -OperationId $OperationId -User $User -System "jfrog" `
        -SystemVersion "runtime-detected" -Resource "repository" -Operation "DELETE" -Target $RepoKey `
        -ExecutionMechanism "rest-api" -Skill "jfrog-repositories" `
        -Script "delete-repository.ps1" -ScriptVersion $ScriptVersion `
        -Risk "DESTRUCTIVE" -ApprovalRequired $true -ApprovalStatus "APPROVED" `
        -Result "FAILURE" -Verification "UNKNOWN" -Error $_.Exception.Message
    Write-Error "Failed to delete repository '$RepoKey': $($_.Exception.Message)"
    exit ([int][DevOpsExitCode]::GeneralFailure)
}
