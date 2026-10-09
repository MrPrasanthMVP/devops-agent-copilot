#Requires -Version 7.0
<#
.SYNOPSIS
    READ_ONLY: Retrieves a Bitbucket Data Center project's details.

.DESCRIPTION
    Purpose: Fetch current project metadata (GET, no mutation).
    Supported OS: Windows (PowerShell 7+), cross-platform compatible.
    Dependencies: scripts/common/Common.psm1 (Invoke-SecureRestMethod, Write-AuditLog)
    Parameters: BaseUrl, ProjectKey, User
    Authentication: Bitbucket HTTP access token, read via Read-LocalSecret
        (POC) - pass a SecureString token directly in production
        integrations instead of relying on the local file.
    Required permissions: Bitbucket "Project view" permission.
    Approval requirements: NONE - READ_ONLY operations execute immediately.
    Dry-run: not applicable (no mutation occurs).
    API/MCP dependency: REST fallback used here; prefer the Bitbucket DC
        MCP server's project-read tool when available (see SKILL.md).
    Exit codes: 0 success, 3 auth failure, 8 not found, 1 general failure.
    Output: project JSON object on stdout.
    Verification: N/A (this script IS a read, not something to verify).
    Audit: writes one READ audit record.
    Security: TLS verification enforced; token never logged or printed.

.EXAMPLE
    ./get-project.ps1 -BaseUrl "https://bitbucket.example.com" -ProjectKey ABC -User jdoe
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$BaseUrl,
    [Parameter(Mandatory = $true)][string]$ProjectKey,
    [Parameter(Mandatory = $true)][string]$User
)

$ScriptVersion = "1.0.0"
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Import-Module (Join-Path $PSScriptRoot "../../../../../scripts/common/Common.psm1") -Force

$operationId = New-OperationId
$target = "$ProjectKey"
$uri = "$BaseUrl/rest/api/1.0/projects/$ProjectKey"

try {
    $token = Read-LocalSecret -System bitbucket
    $project = Invoke-SecureRestMethod -Uri $uri -Method GET -Token $token

    Write-AuditLog -OperationId $operationId -User $User -System "bitbucket" `
        -SystemVersion "runtime-detected" -Resource "project" -Operation "GET" -Target $target `
        -ExecutionMechanism "rest-api" -Skill "bitbucket-project-admin" `
        -Script "get-project.ps1" -ScriptVersion $ScriptVersion `
        -Risk "READ_ONLY" -ApprovalRequired $false -ApprovalStatus "NOT_REQUIRED" `
        -Result "SUCCESS" -Verification "NOT_APPLICABLE"

    $project | ConvertTo-Json -Depth 10
    exit ([int][DevOpsExitCode]::Success)
}
catch {
    Write-AuditLog -OperationId $operationId -User $User -System "bitbucket" `
        -SystemVersion "runtime-detected" -Resource "project" -Operation "GET" -Target $target `
        -ExecutionMechanism "rest-api" -Skill "bitbucket-project-admin" `
        -Script "get-project.ps1" -ScriptVersion $ScriptVersion `
        -Risk "READ_ONLY" -ApprovalRequired $false -ApprovalStatus "NOT_REQUIRED" `
        -Result "FAILURE" -Verification "NOT_APPLICABLE" -Error $_.Exception.Message

    Write-Error "Failed to retrieve project '$target': $($_.Exception.Message)"
    exit ([int][DevOpsExitCode]::GeneralFailure)
}
