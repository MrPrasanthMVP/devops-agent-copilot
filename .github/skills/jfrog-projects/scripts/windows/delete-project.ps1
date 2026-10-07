#Requires -Version 7.0
<#
.SYNOPSIS
    DESTRUCTIVE: Deletes a JFrog Platform Project. Requires a
    pre-issued "APPROVE DELETE" approval record. No project-delete tool
    was found in the verified v0.442 MCP catalog -- REST fallback.

.DESCRIPTION
    Purpose: Execute the DELETE stage for a JFrog Project.
    Supported OS: Windows (PowerShell 7+).
    Dependencies: scripts/common/Common.psm1
    Parameters: BaseUrl, ProjectKey, User, OperationId
    Authentication: JFrog access token (POC: local-secrets).
    Required permissions: Access admin privileges.
    Approval requirements: MANDATORY "APPROVE DELETE" bound to this ProjectKey.
    Dry-run: -WhatIf supported.
    API/MCP dependency: REST fallback (DELETE /access/api/v1/projects/{projectKey}).
    Exit codes: 0 success, 6 approval denied, 7 verification failure, 1 general failure.
    Output: JSON result.
    Verification: GET after delete; expect 404/NOT_FOUND.
    Audit: writes one DESTRUCTIVE audit record.
    Security: TLS enforced; approval re-checked immediately before DELETE.

.EXAMPLE
    ./delete-project.ps1 -BaseUrl "https://jfrog.example.com" -ProjectKey payments `
        -User admin-jdoe -OperationId op-123
#>

[CmdletBinding(SupportsShouldAction = $true)]
param(
    [Parameter(Mandatory = $true)][string]$BaseUrl,
    [Parameter(Mandatory = $true)][ValidatePattern('^[a-z0-9]+$')][string]$ProjectKey,
    [Parameter(Mandatory = $true)][string]$User,
    [Parameter(Mandatory = $true)][string]$OperationId
)

$ScriptVersion = "1.0.0"
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Import-Module (Join-Path $PSScriptRoot "../../../../../scripts/common/Common.psm1") -Force

$operationKey = "jfrog.projects.delete"
$approval = Test-ApprovalToken -OperationId $OperationId -System "jfrog" `
    -Target $ProjectKey -Operation $operationKey -ExpectedApprovalType "APPROVE DELETE"

if (-not $approval.Valid) {
    Write-AuditLog -OperationId $OperationId -User $User -System "jfrog" `
        -SystemVersion "runtime-detected" -Resource "project" -Operation "DELETE" -Target $ProjectKey `
        -ExecutionMechanism "rest-api" -Skill "jfrog-projects" `
        -Script "delete-project.ps1" -ScriptVersion $ScriptVersion `
        -Risk "DESTRUCTIVE" -ApprovalRequired $true -ApprovalStatus "DENIED" `
        -Result "DENIED" -Verification "NOT_APPLICABLE" -Error $approval.Reason
    Write-Error "Approval check failed: $($approval.Reason)"
    exit ([int][DevOpsExitCode]::ApprovalDenied)
}

$uri = "$BaseUrl/access/api/v1/projects/$ProjectKey"

try {
    $token = Read-LocalSecret -System jfrog

    if ($PSCmdlet.ShouldProcess($ProjectKey, "DELETE JFrog project")) {
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
            -SystemVersion "runtime-detected" -Resource "project" -Operation "DELETE" -Target $ProjectKey `
            -ExecutionMechanism "rest-api" -Skill "jfrog-projects" `
            -Script "delete-project.ps1" -ScriptVersion $ScriptVersion `
            -Risk "DESTRUCTIVE" -ApprovalRequired $true -ApprovalStatus "APPROVED" `
            -Result $result -Verification $verification

        [pscustomobject]@{ operationId = $OperationId; target = $ProjectKey; result = $result; verification = $verification } | ConvertTo-Json
        if ($verification -ne "CONFIRMED") { exit ([int][DevOpsExitCode]::VerificationFailure) }
        exit ([int][DevOpsExitCode]::Success)
    }
    else {
        Write-Host "(WhatIf) Would DELETE JFrog project '$ProjectKey'. No change made."
        exit ([int][DevOpsExitCode]::Success)
    }
}
catch {
    Write-AuditLog -OperationId $OperationId -User $User -System "jfrog" `
        -SystemVersion "runtime-detected" -Resource "project" -Operation "DELETE" -Target $ProjectKey `
        -ExecutionMechanism "rest-api" -Skill "jfrog-projects" `
        -Script "delete-project.ps1" -ScriptVersion $ScriptVersion `
        -Risk "DESTRUCTIVE" -ApprovalRequired $true -ApprovalStatus "APPROVED" `
        -Result "FAILURE" -Verification "UNKNOWN" -Error $_.Exception.Message
    Write-Error "Failed to delete project '$ProjectKey': $($_.Exception.Message)"
    exit ([int][DevOpsExitCode]::GeneralFailure)
}
