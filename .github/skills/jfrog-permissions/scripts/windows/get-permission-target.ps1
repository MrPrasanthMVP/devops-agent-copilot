#Requires -Version 7.0
<#
.SYNOPSIS
    READ_ONLY: Retrieves a JFrog Artifactory permission target (v2).

.DESCRIPTION
    Purpose: Fetch current permission target definition (GET only).
    Supported OS: Windows (PowerShell 7+).
    Dependencies: scripts/common/Common.psm1
    Parameters: BaseUrl, PermissionTargetName, User
    Authentication: JFrog access token (POC: local-secrets).
    Required permissions: admin or "Manage" permission on the target.
    Approval requirements: NONE - READ_ONLY.
    Dry-run: not applicable.
    API/MCP dependency: REST fallback
        (GET /artifactory/api/v2/security/permissions/{name}).
    Exit codes: 0 success, 8 not found, 1 general failure.
    Output: permission target JSON on stdout.
    Verification: N/A.
    Audit: writes one READ audit record.
    Security: TLS enforced; token never logged or printed.

.EXAMPLE
    ./get-permission-target.ps1 -BaseUrl "https://jfrog.example.com" `
        -PermissionTargetName releases-local-perm -User jdoe
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$BaseUrl,
    [Parameter(Mandatory = $true)][string]$PermissionTargetName,
    [Parameter(Mandatory = $true)][string]$User
)

$ScriptVersion = "1.0.0"
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Import-Module (Join-Path $PSScriptRoot "../../../../../scripts/common/Common.psm1") -Force

$operationId = New-OperationId
$uri = "$BaseUrl/artifactory/api/v2/security/permissions/$PermissionTargetName"

try {
    $token = Read-LocalSecret -System jfrog
    $perm = Invoke-SecureRestMethod -Uri $uri -Method GET -Token $token

    Write-AuditLog -OperationId $operationId -User $User -System "jfrog" `
        -SystemVersion "runtime-detected" -Resource "permission_target" -Operation "GET" -Target $PermissionTargetName `
        -ExecutionMechanism "rest-api" -Skill "jfrog-permissions" `
        -Script "get-permission-target.ps1" -ScriptVersion $ScriptVersion `
        -Risk "READ_ONLY" -ApprovalRequired $false -ApprovalStatus "NOT_REQUIRED" `
        -Result "SUCCESS" -Verification "NOT_APPLICABLE"

    $perm | ConvertTo-Json -Depth 10
    exit ([int][DevOpsExitCode]::Success)
}
catch {
    Write-AuditLog -OperationId $operationId -User $User -System "jfrog" `
        -SystemVersion "runtime-detected" -Resource "permission_target" -Operation "GET" -Target $PermissionTargetName `
        -ExecutionMechanism "rest-api" -Skill "jfrog-permissions" `
        -Script "get-permission-target.ps1" -ScriptVersion $ScriptVersion `
        -Risk "READ_ONLY" -ApprovalRequired $false -ApprovalStatus "NOT_REQUIRED" `
        -Result "FAILURE" -Verification "NOT_APPLICABLE" -Error $_.Exception.Message

    Write-Error "Failed to retrieve permission target '$PermissionTargetName': $($_.Exception.Message)"
    exit ([int][DevOpsExitCode]::GeneralFailure)
}
