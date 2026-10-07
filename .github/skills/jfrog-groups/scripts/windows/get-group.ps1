#Requires -Version 7.0
<#
.SYNOPSIS
    READ-ONLY: Gets a JFrog Platform group's details (including
    members). No MCP tool covers group CRUD in the verified v0.442
    catalog (policies/system-policy.yaml) -- this is the REST fallback.

.DESCRIPTION
    Purpose: Read one group's configuration.
    Supported OS: Windows (PowerShell 7+).
    Dependencies: scripts/common/Common.psm1
    Parameters: BaseUrl, GroupName
    Authentication: JFrog access token (POC: local-secrets).
    Required permissions: Read access to group administration.
    Approval requirements: None (READ_ONLY).
    Dry-run: Not applicable (already read-only).
    API/MCP dependency: REST fallback (GET /access/api/v2/groups/{group_name}).
    Exit codes: 0 success, 3 auth failure, 8 target not found, 1 general failure.
    Output: JSON group object.
    Verification: Not applicable (read-only).
    Audit: writes one READ_ONLY audit record.
    Security: TLS enforced.

.EXAMPLE
    ./get-group.ps1 -BaseUrl "https://jfrog.example.com" -GroupName build-team
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$BaseUrl,
    [Parameter(Mandatory = $true)][string]$GroupName,
    [string]$User = $env:USERNAME
)

$ScriptVersion = "1.0.0"
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Import-Module (Join-Path $PSScriptRoot "../../../../../scripts/common/Common.psm1") -Force

$uri = "$BaseUrl/access/api/v2/groups/$GroupName"

try {
    $token = Read-LocalSecret -System jfrog
    $group = Invoke-SecureRestMethod -Uri $uri -Method GET -Token $token

    Write-AuditLog -OperationId "n/a" -User $User -System "jfrog" `
        -SystemVersion "runtime-detected" -Resource "group" -Operation "GET" -Target $GroupName `
        -ExecutionMechanism "rest-api" -Skill "jfrog-groups" `
        -Script "get-group.ps1" -ScriptVersion $ScriptVersion `
        -Risk "READ_ONLY" -ApprovalRequired $false -ApprovalStatus "NOT_REQUIRED" `
        -Result "SUCCESS" -Verification "NOT_APPLICABLE"

    $group | ConvertTo-Json -Depth 6
    exit ([int][DevOpsExitCode]::Success)
}
catch {
    $status = $_.Exception.Response.StatusCode.value__
    if ($status -eq 401) { Write-Error "Authentication failure."; exit ([int][DevOpsExitCode]::AuthenticationFailure) }
    if ($status -eq 404) { Write-Error "Group not found: $GroupName"; exit ([int][DevOpsExitCode]::TargetNotFound) }
    Write-Error "get-group failed: $($_.Exception.Message)"
    exit ([int][DevOpsExitCode]::GeneralFailure)
}
