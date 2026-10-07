#Requires -Version 7.0
<#
.SYNOPSIS
    DESTRUCTIVE: Permanently deletes a Bitbucket Data Center 9.4.5
    repository via the REST API fallback. Requires a pre-issued,
    matching "APPROVE DELETE" approval record.

.DESCRIPTION
    Purpose: Execute the DELETE stage for a Bitbucket repository.
    Supported OS: Windows (PowerShell 7+).
    Dependencies: scripts/common/Common.psm1
    Parameters: BaseUrl, ProjectKey, RepositorySlug, User, OperationId
    Authentication: Bitbucket HTTP access token (POC: local-secrets).
    Required permissions: Repository admin (or project admin).
    Approval requirements: MANDATORY "APPROVE DELETE" bound to this
        exact ProjectKey/RepositorySlug.
    Dry-run: -WhatIf supported.
    API/MCP dependency: REST fallback
        (DELETE /rest/api/1.0/projects/{projectKey}/repos/{repositorySlug}).
    Exit codes: 0 success, 6 approval denied, 7 verification failure,
        1 general failure.
    Output: JSON result.
    Verification: GET after DELETE; expect HTTP 404.
    Audit: writes one DESTRUCTIVE audit record.
    Security: TLS enforced; approval re-checked immediately before
        DELETE; never bypassable via a bare --approved flag.

.EXAMPLE
    ./delete-repository.ps1 -BaseUrl "https://bitbucket.example.internal" `
        -ProjectKey PROJ -RepositorySlug test -User jdoe -OperationId op-123
#>

[CmdletBinding(SupportsShouldAction = $true)]
param(
    [Parameter(Mandatory = $true)][string]$BaseUrl,
    [Parameter(Mandatory = $true)][ValidatePattern('^[A-Za-z0-9_.-]+$')][string]$ProjectKey,
    [Parameter(Mandatory = $true)][ValidatePattern('^[A-Za-z0-9_.-]+$')][string]$RepositorySlug,
    [Parameter(Mandatory = $true)][string]$User,
    [Parameter(Mandatory = $true)][string]$OperationId
)

$ScriptVersion = "1.0.0"
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Import-Module (Join-Path $PSScriptRoot "../../../../../scripts/common/Common.psm1") -Force

$target = "$ProjectKey/$RepositorySlug"
$operationKey = "bitbucket.repository.delete"

$approval = Test-ApprovalToken -OperationId $OperationId -System "bitbucket" `
    -Target $target -Operation $operationKey -ExpectedApprovalType "APPROVE DELETE"

if (-not $approval.Valid) {
    Write-AuditLog -OperationId $OperationId -User $User -System "bitbucket" `
        -SystemVersion "9.4.5" -Resource "repository" -Operation "DELETE" -Target $target `
        -ExecutionMechanism "rest-api" -Skill "bitbucket-repository-admin" `
        -Script "delete-repository.ps1" -ScriptVersion $ScriptVersion `
        -Risk "DESTRUCTIVE" -ApprovalRequired $true -ApprovalStatus "DENIED" `
        -Result "DENIED" -Verification "NOT_APPLICABLE" -Error $approval.Reason
    Write-Error "Approval check failed: $($approval.Reason)"
    exit ([int][DevOpsExitCode]::ApprovalDenied)
}

$uri = "$BaseUrl/rest/api/1.0/projects/$ProjectKey/repos/$RepositorySlug"

try {
    $token = Read-LocalSecret -System bitbucket

    if ($PSCmdlet.ShouldProcess($target, "DELETE Bitbucket repository")) {
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

        Write-AuditLog -OperationId $OperationId -User $User -System "bitbucket" `
            -SystemVersion "9.4.5" -Resource "repository" -Operation "DELETE" -Target $target `
            -ExecutionMechanism "rest-api" -Skill "bitbucket-repository-admin" `
            -Script "delete-repository.ps1" -ScriptVersion $ScriptVersion `
            -Risk "DESTRUCTIVE" -ApprovalRequired $true -ApprovalStatus "APPROVED" `
            -Result $result -Verification $verification

        [pscustomobject]@{ operationId = $OperationId; target = $target; result = $result; verification = $verification } | ConvertTo-Json
        if ($verification -ne "CONFIRMED") { exit ([int][DevOpsExitCode]::VerificationFailure) }
        exit ([int][DevOpsExitCode]::Success)
    }
    else {
        Write-Host "(WhatIf) Would DELETE Bitbucket repository '$target'. No change made."
        exit ([int][DevOpsExitCode]::Success)
    }
}
catch {
    Write-AuditLog -OperationId $OperationId -User $User -System "bitbucket" `
        -SystemVersion "9.4.5" -Resource "repository" -Operation "DELETE" -Target $target `
        -ExecutionMechanism "rest-api" -Skill "bitbucket-repository-admin" `
        -Script "delete-repository.ps1" -ScriptVersion $ScriptVersion `
        -Risk "DESTRUCTIVE" -ApprovalRequired $true -ApprovalStatus "APPROVED" `
        -Result "FAILURE" -Verification "UNKNOWN" -Error $_.Exception.Message
    Write-Error "Failed to delete repository '$target': $($_.Exception.Message)"
    exit ([int][DevOpsExitCode]::GeneralFailure)
}
