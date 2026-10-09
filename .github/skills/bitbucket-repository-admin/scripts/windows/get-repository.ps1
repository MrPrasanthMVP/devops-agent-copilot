#Requires -Version 7.0
<#
.SYNOPSIS
    READ_ONLY: Retrieves a Bitbucket Data Center repository's settings.

.DESCRIPTION
    Purpose: Fetch current repository configuration (GET, no mutation).
    Supported OS: Windows (PowerShell 7+), cross-platform compatible.
    Dependencies: scripts/common/Common.psm1 (Invoke-SecureRestMethod, Write-AuditLog)
    Parameters: BaseUrl, ProjectKey, RepositorySlug, User
    Authentication: Bitbucket HTTP access token, read via Read-LocalSecret
        (POC) - pass a SecureString token directly in production
        integrations instead of relying on the local file.
    Required permissions: Bitbucket "Read" project/repository permission.
    Approval requirements: NONE - READ_ONLY operations execute immediately.
    Dry-run: not applicable (no mutation occurs).
    API/MCP dependency: REST fallback used here; prefer the Bitbucket DC
        MCP server's repository-read tool when available (see SKILL.md).
    Exit codes: 0 success, 3 auth failure, 8 not found, 1 general failure.
    Output: repository JSON object on stdout.
    Verification: N/A (this script IS a read, not something to verify).
    Audit: writes one READ audit record.
    Security: TLS verification enforced; token never logged or printed.

.EXAMPLE
    ./get-repository.ps1 -BaseUrl "https://bitbucket.example.com" `
        -ProjectKey ABC -RepositorySlug test-repo -User jdoe
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$BaseUrl,
    [Parameter(Mandatory = $true)][string]$ProjectKey,
    [Parameter(Mandatory = $true)][string]$RepositorySlug,
    [Parameter(Mandatory = $true)][string]$User
)

$ScriptVersion = "1.0.0"
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Import-Module (Join-Path $PSScriptRoot "../../../../../scripts/common/Common.psm1") -Force

$operationId = New-OperationId
$target = "$ProjectKey/$RepositorySlug"
$uri = "$BaseUrl/rest/api/1.0/projects/$ProjectKey/repos/$RepositorySlug"

try {
    $token = Read-LocalSecret -System bitbucket
    $repo = Invoke-SecureRestMethod -Uri $uri -Method GET -Token $token

    Write-AuditLog -OperationId $operationId -User $User -System "bitbucket" `
        -SystemVersion "runtime-detected" -Resource "repository" -Operation "GET" -Target $target `
        -ExecutionMechanism "rest-api" -Skill "bitbucket-repository-admin" `
        -Script "get-repository.ps1" -ScriptVersion $ScriptVersion `
        -Risk "READ_ONLY" -ApprovalRequired $false -ApprovalStatus "NOT_REQUIRED" `
        -Result "SUCCESS" -Verification "NOT_APPLICABLE"

    $repo | ConvertTo-Json -Depth 10
    exit ([int][DevOpsExitCode]::Success)
}
catch {
    Write-AuditLog -OperationId $operationId -User $User -System "bitbucket" `
        -SystemVersion "runtime-detected" -Resource "repository" -Operation "GET" -Target $target `
        -ExecutionMechanism "rest-api" -Skill "bitbucket-repository-admin" `
        -Script "get-repository.ps1" -ScriptVersion $ScriptVersion `
        -Risk "READ_ONLY" -ApprovalRequired $false -ApprovalStatus "NOT_REQUIRED" `
        -Result "FAILURE" -Verification "NOT_APPLICABLE" -Error $_.Exception.Message

    Write-Error "Failed to retrieve repository '$target': $($_.Exception.Message)"
    exit ([int][DevOpsExitCode]::GeneralFailure)
}
