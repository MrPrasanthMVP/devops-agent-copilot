#Requires -Version 7.0
<#
.SYNOPSIS
    READ_ONLY: Retrieves role assignments for a Confluence Cloud space.

.DESCRIPTION
    Purpose: Fetch current space role assignments (GET, no mutation).
    Supported OS: Windows (PowerShell 7+). Dependencies: scripts/common/Common.psm1
    Parameters: SiteUrl, SpaceId, Email, ApiToken, User
    Authentication: Confluence Cloud basic auth (email + API token).
    Required permissions: space "admin" role (to view role assignments).
    Approval requirements: NONE - READ_ONLY.
    Dry-run: not applicable.
    API/MCP dependency: REST fallback
        (GET /wiki/api/v2/spaces/{id}/role-assignments); prefer discovered Rovo MCP tool.
    Exit codes: 0 success, 1 general failure.
    Output: role assignments JSON on stdout.
    Verification: N/A. Audit: writes one READ audit record.
    Security: TLS enforced; token never logged or printed.

.EXAMPLE
    ./get-role-assignments.ps1 -SiteUrl "https://example.atlassian.net" -SpaceId 123456 `
        -Email jdoe@example.com -ApiToken $token -User jdoe
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$SiteUrl,
    [Parameter(Mandatory = $true)][string]$SpaceId,
    [Parameter(Mandatory = $true)][string]$Email,
    [Parameter(Mandatory = $true)][System.Security.SecureString]$ApiToken,
    [Parameter(Mandatory = $true)][string]$User
)

$ScriptVersion = "1.0.0"
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Import-Module (Join-Path $PSScriptRoot "../../../../../scripts/common/Common.psm1") -Force

$operationId = New-OperationId
$uri = "$SiteUrl/wiki/api/v2/spaces/$SpaceId/role-assignments"

try {
    $plainToken = ConvertFrom-SecureStringPlain -Secure $ApiToken
    $basic = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes("$Email`:$plainToken"))
    $plainToken = $null
    $secureBasic = ConvertTo-SecureString -String $basic -AsPlainText -Force

    $roles = Invoke-SecureRestMethod -Uri $uri -Method GET -Token $secureBasic -AuthScheme "Basic"

    Write-AuditLog -OperationId $operationId -User $User -System "confluence" `
        -SystemVersion "cloud" -Resource "space_role" -Operation "GET" -Target $SpaceId `
        -ExecutionMechanism "rest-api" -Skill "confluence-permissions" `
        -Script "get-role-assignments.ps1" -ScriptVersion $ScriptVersion `
        -Risk "READ_ONLY" -ApprovalRequired $false -ApprovalStatus "NOT_REQUIRED" `
        -Result "SUCCESS" -Verification "NOT_APPLICABLE"

    $roles | ConvertTo-Json -Depth 10
    exit ([int][DevOpsExitCode]::Success)
}
catch {
    Write-AuditLog -OperationId $operationId -User $User -System "confluence" `
        -SystemVersion "cloud" -Resource "space_role" -Operation "GET" -Target $SpaceId `
        -ExecutionMechanism "rest-api" -Skill "confluence-permissions" `
        -Script "get-role-assignments.ps1" -ScriptVersion $ScriptVersion `
        -Risk "READ_ONLY" -ApprovalRequired $false -ApprovalStatus "NOT_REQUIRED" `
        -Result "FAILURE" -Verification "NOT_APPLICABLE" -Error $_.Exception.Message
    Write-Error "Failed to retrieve role assignments for space '$SpaceId': $($_.Exception.Message)"
    exit ([int][DevOpsExitCode]::GeneralFailure)
}
