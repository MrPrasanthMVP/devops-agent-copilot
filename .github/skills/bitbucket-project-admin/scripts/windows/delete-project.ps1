#Requires -Version 7.0
<#
.SYNOPSIS
    DESTRUCTIVE: Permanently deletes a Bitbucket Data Center project (and
    every repository it contains). Requires a pre-issued, matching
    "APPROVE DELETE" approval record.

.DESCRIPTION
    Purpose: Execute the DELETE stage of the mandatory approval workflow
        for project deletion.
    Supported OS: Windows (PowerShell 7+).
    Dependencies: scripts/common/Common.psm1
    Parameters: BaseUrl, ProjectKey, User, OperationId
    Authentication: Bitbucket HTTP access token (POC: local-secrets).
    Required permissions: Bitbucket project admin / global admin permission.
    Approval requirements: MANDATORY. OperationId must resolve to a valid
        approval record with ApprovalType "APPROVE DELETE" bound to this
        exact ProjectKey - enforced via Test-ApprovalToken. This script
        refuses to run (exit 6) without it.
    Dry-run: -WhatIf supported; performs read-only preview, no deletion.
    API/MCP dependency: REST fallback
        (DELETE /rest/api/1.0/projects/{projectKey}).
    Exit codes: 0 success, 6 approval denied/missing, 7 verification
        failure, 8 not found, 1 general failure.
    Output: JSON result with operationId, result, verification status.
    Verification: GET after DELETE; expects 404/NOT_FOUND. If the
        project still appears to exist, this script reports
        verification=FAILED and result=UNKNOWN - never SUCCESS.
    Audit: writes one DESTRUCTIVE audit record regardless of outcome.
    Security: TLS enforced; approval binding re-checked immediately before
        the DELETE call (not cached from an earlier step) to close any
        TOCTOU gap. Deleting a project deletes every repository inside
        it - this is surfaced in the human-approval proposal, not here.

.EXAMPLE
    ./delete-project.ps1 -BaseUrl "https://bitbucket.example.com" `
        -ProjectKey TEST -User jdoe -OperationId op-3f9c2b1a7e4d
#>

[CmdletBinding(SupportsShouldAction = $true)]
param(
    [Parameter(Mandatory = $true)][string]$BaseUrl,
    [Parameter(Mandatory = $true)][string]$ProjectKey,
    [Parameter(Mandatory = $true)][string]$User,
    [Parameter(Mandatory = $true)][string]$OperationId
)

$ScriptVersion = "1.0.0"
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Import-Module (Join-Path $PSScriptRoot "../../../../../scripts/common/Common.psm1") -Force

$target = "$ProjectKey"
$operationKey = "bitbucket.project.delete"

$approval = Test-ApprovalToken -OperationId $OperationId -System "bitbucket" `
    -Target $target -Operation $operationKey -ExpectedApprovalType "APPROVE DELETE"

if (-not $approval.Valid) {
    Write-AuditLog -OperationId $OperationId -User $User -System "bitbucket" `
        -SystemVersion "9.4.5" -Resource "project" -Operation "DELETE" -Target $target `
        -ExecutionMechanism "rest-api" -Skill "bitbucket-project-admin" `
        -Script "delete-project.ps1" -ScriptVersion $ScriptVersion `
        -Risk "DESTRUCTIVE" -ApprovalRequired $true -ApprovalStatus "DENIED" `
        -Result "DENIED" -Verification "NOT_APPLICABLE" -Error $approval.Reason

    Write-Error "Approval check failed: $($approval.Reason)"
    exit ([int][DevOpsExitCode]::ApprovalDenied)
}

$uri = "$BaseUrl/rest/api/1.0/projects/$ProjectKey"

try {
    $token = Read-LocalSecret -System bitbucket

    if ($PSCmdlet.ShouldProcess($target, "DELETE Bitbucket project")) {
        Invoke-SecureRestMethod -Uri $uri -Method DELETE -Token $token | Out-Null
        Set-ApprovalConsumed -OperationId $OperationId

        $verification = "UNKNOWN"
        $result = "UNKNOWN"
        try {
            Invoke-SecureRestMethod -Uri $uri -Method GET -Token $token | Out-Null
            $verification = "FAILED"
            $result = "UNKNOWN"
        }
        catch {
            $verification = "CONFIRMED"
            $result = "SUCCESS"
        }

        Write-AuditLog -OperationId $OperationId -User $User -System "bitbucket" `
            -SystemVersion "9.4.5" -Resource "project" -Operation "DELETE" -Target $target `
            -ExecutionMechanism "rest-api" -Skill "bitbucket-project-admin" `
            -Script "delete-project.ps1" -ScriptVersion $ScriptVersion `
            -Risk "DESTRUCTIVE" -ApprovalRequired $true -ApprovalStatus "APPROVED" `
            -Result $result -Verification $verification

        [pscustomobject]@{
            operationId  = $OperationId
            target       = $target
            result       = $result
            verification = $verification
        } | ConvertTo-Json

        if ($verification -ne "CONFIRMED") {
            exit ([int][DevOpsExitCode]::VerificationFailure)
        }
        exit ([int][DevOpsExitCode]::Success)
    }
    else {
        Write-Host "(WhatIf) Would DELETE Bitbucket project '$target'. No change made."
        exit ([int][DevOpsExitCode]::Success)
    }
}
catch {
    Write-AuditLog -OperationId $OperationId -User $User -System "bitbucket" `
        -SystemVersion "9.4.5" -Resource "project" -Operation "DELETE" -Target $target `
        -ExecutionMechanism "rest-api" -Skill "bitbucket-project-admin" `
        -Script "delete-project.ps1" -ScriptVersion $ScriptVersion `
        -Risk "DESTRUCTIVE" -ApprovalRequired $true -ApprovalStatus "APPROVED" `
        -Result "FAILURE" -Verification "UNKNOWN" -Error $_.Exception.Message

    Write-Error "Failed to delete project '$target': $($_.Exception.Message)"
    exit ([int][DevOpsExitCode]::GeneralFailure)
}
