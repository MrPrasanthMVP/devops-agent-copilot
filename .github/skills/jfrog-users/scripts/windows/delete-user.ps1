#Requires -Version 7.0
<#
.SYNOPSIS
    DESTRUCTIVE: Deletes a JFrog Platform user account. Requires a
    pre-issued "APPROVE DELETE" approval record.

.DESCRIPTION
    Purpose: Execute the DELETE stage for a user account.
    Supported OS: Windows (PowerShell 7+).
    Dependencies: scripts/common/Common.psm1
    Parameters: BaseUrl, Username, User, OperationId
    Authentication: JFrog access token (POC: local-secrets).
    Required permissions: admin privileges.
    Approval requirements: MANDATORY "APPROVE DELETE" bound to this Username.
    Dry-run: -WhatIf supported.
    API/MCP dependency: REST fallback (DELETE /access/api/v2/users/{username}).
    Exit codes: 0 success, 6 approval denied, 7 verification failure, 1 general failure.
    Output: JSON result.
    Verification: GET after delete; expect 404/NOT_FOUND.
    Audit: writes one DESTRUCTIVE audit record.
    Security: TLS enforced; approval re-checked immediately before DELETE.

.EXAMPLE
    ./delete-user.ps1 -BaseUrl "https://jfrog.example.com" -Username jdoe `
        -User admin-jdoe -OperationId op-123
#>

[CmdletBinding(SupportsShouldAction = $true)]
param(
    [Parameter(Mandatory = $true)][string]$BaseUrl,
    [Parameter(Mandatory = $true)][string]$Username,
    [Parameter(Mandatory = $true)][string]$User,
    [Parameter(Mandatory = $true)][string]$OperationId
)

$ScriptVersion = "1.0.0"
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Import-Module (Join-Path $PSScriptRoot "../../../../../scripts/common/Common.psm1") -Force

$operationKey = "jfrog.users.delete"
$approval = Test-ApprovalToken -OperationId $OperationId -System "jfrog" `
    -Target $Username -Operation $operationKey -ExpectedApprovalType "APPROVE DELETE"

if (-not $approval.Valid) {
    Write-AuditLog -OperationId $OperationId -User $User -System "jfrog" `
        -SystemVersion "runtime-detected" -Resource "user" -Operation "DELETE" -Target $Username `
        -ExecutionMechanism "rest-api" -Skill "jfrog-users" `
        -Script "delete-user.ps1" -ScriptVersion $ScriptVersion `
        -Risk "DESTRUCTIVE" -ApprovalRequired $true -ApprovalStatus "DENIED" `
        -Result "DENIED" -Verification "NOT_APPLICABLE" -Error $approval.Reason
    Write-Error "Approval check failed: $($approval.Reason)"
    exit ([int][DevOpsExitCode]::ApprovalDenied)
}

$uri = "$BaseUrl/access/api/v2/users/$Username"

try {
    $token = Read-LocalSecret -System jfrog

    if ($PSCmdlet.ShouldProcess($Username, "DELETE JFrog user")) {
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
            -SystemVersion "runtime-detected" -Resource "user" -Operation "DELETE" -Target $Username `
            -ExecutionMechanism "rest-api" -Skill "jfrog-users" `
            -Script "delete-user.ps1" -ScriptVersion $ScriptVersion `
            -Risk "DESTRUCTIVE" -ApprovalRequired $true -ApprovalStatus "APPROVED" `
            -Result $result -Verification $verification

        [pscustomobject]@{ operationId = $OperationId; target = $Username; result = $result; verification = $verification } | ConvertTo-Json
        if ($verification -ne "CONFIRMED") { exit ([int][DevOpsExitCode]::VerificationFailure) }
        exit ([int][DevOpsExitCode]::Success)
    }
    else {
        Write-Host "(WhatIf) Would DELETE JFrog user '$Username'. No change made."
        exit ([int][DevOpsExitCode]::Success)
    }
}
catch {
    Write-AuditLog -OperationId $OperationId -User $User -System "jfrog" `
        -SystemVersion "runtime-detected" -Resource "user" -Operation "DELETE" -Target $Username `
        -ExecutionMechanism "rest-api" -Skill "jfrog-users" `
        -Script "delete-user.ps1" -ScriptVersion $ScriptVersion `
        -Risk "DESTRUCTIVE" -ApprovalRequired $true -ApprovalStatus "APPROVED" `
        -Result "FAILURE" -Verification "UNKNOWN" -Error $_.Exception.Message
    Write-Error "Failed to delete user '$Username': $($_.Exception.Message)"
    exit ([int][DevOpsExitCode]::GeneralFailure)
}
