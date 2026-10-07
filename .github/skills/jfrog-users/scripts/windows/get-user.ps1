#Requires -Version 7.0
<#
.SYNOPSIS
    READ_ONLY: Retrieves a JFrog Platform user account via the Access API.

.DESCRIPTION
    Purpose: Fetch current user account details (GET only).
    Supported OS: Windows (PowerShell 7+).
    Dependencies: scripts/common/Common.psm1
    Parameters: BaseUrl, Username, User
    Authentication: JFrog access token (POC: local-secrets).
    Required permissions: admin privileges.
    Approval requirements: NONE - READ_ONLY.
    Dry-run: not applicable.
    API/MCP dependency: REST fallback (GET /access/api/v2/users/{username}).
    Exit codes: 0 success, 8 not found, 1 general failure.
    Output: user JSON on stdout (password/credential fields never present
        in this response per JFrog Access API design).
    Verification: N/A.
    Audit: writes one READ audit record.
    Security: TLS enforced; token never logged or printed.

.EXAMPLE
    ./get-user.ps1 -BaseUrl "https://jfrog.example.com" -Username jdoe -User admin-jdoe
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$BaseUrl,
    [Parameter(Mandatory = $true)][string]$Username,
    [Parameter(Mandatory = $true)][string]$User
)

$ScriptVersion = "1.0.0"
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Import-Module (Join-Path $PSScriptRoot "../../../../../scripts/common/Common.psm1") -Force

$operationId = New-OperationId
$uri = "$BaseUrl/access/api/v2/users/$Username"

try {
    $token = Read-LocalSecret -System jfrog
    $user = Invoke-SecureRestMethod -Uri $uri -Method GET -Token $token

    Write-AuditLog -OperationId $operationId -User $User -System "jfrog" `
        -SystemVersion "runtime-detected" -Resource "user" -Operation "GET" -Target $Username `
        -ExecutionMechanism "rest-api" -Skill "jfrog-users" `
        -Script "get-user.ps1" -ScriptVersion $ScriptVersion `
        -Risk "READ_ONLY" -ApprovalRequired $false -ApprovalStatus "NOT_REQUIRED" `
        -Result "SUCCESS" -Verification "NOT_APPLICABLE"

    $user | ConvertTo-Json -Depth 10
    exit ([int][DevOpsExitCode]::Success)
}
catch {
    Write-AuditLog -OperationId $operationId -User $User -System "jfrog" `
        -SystemVersion "runtime-detected" -Resource "user" -Operation "GET" -Target $Username `
        -ExecutionMechanism "rest-api" -Skill "jfrog-users" `
        -Script "get-user.ps1" -ScriptVersion $ScriptVersion `
        -Risk "READ_ONLY" -ApprovalRequired $false -ApprovalStatus "NOT_REQUIRED" `
        -Result "FAILURE" -Verification "NOT_APPLICABLE" -Error $_.Exception.Message

    Write-Error "Failed to retrieve user '$Username': $($_.Exception.Message)"
    exit ([int][DevOpsExitCode]::GeneralFailure)
}
