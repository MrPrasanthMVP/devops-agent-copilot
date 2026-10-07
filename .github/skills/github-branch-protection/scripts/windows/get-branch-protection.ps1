#Requires -Version 7.0
<#
.SYNOPSIS
    READ_ONLY: Retrieves branch protection settings for a GitHub
    Enterprise (Cloud or Server) repository branch.

.DESCRIPTION
    Purpose: Fetch current branch protection configuration (GET only).
    Supported OS: Windows (PowerShell 7+).
    Dependencies: scripts/common/Common.psm1
    Parameters: ApiBaseUrl (e.g. https://api.github.com or
        https://<ghes-host>/api/v3), Owner, Repo, Branch, User
    Authentication: GitHub token (POC: local-secrets).
    Required permissions: repository admin read access.
    Approval requirements: NONE - READ_ONLY.
    Dry-run: not applicable.
    API/MCP dependency: REST fallback used here; prefer the discovered
        GitHub MCP branch-protection-read tool when available.
    Exit codes: 0 success, 8 not found (unprotected branch), 1 general failure.
    Output: branch protection JSON on stdout.
    Verification: N/A.
    Audit: writes one READ audit record.
    Security: TLS enforced; token never logged or printed.

.EXAMPLE
    ./get-branch-protection.ps1 -ApiBaseUrl "https://api.github.com" `
        -Owner myorg -Repo myrepo -Branch main -User jdoe
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$ApiBaseUrl,
    [Parameter(Mandatory = $true)][string]$Owner,
    [Parameter(Mandatory = $true)][string]$Repo,
    [Parameter(Mandatory = $true)][string]$Branch,
    [Parameter(Mandatory = $true)][string]$User
)

$ScriptVersion = "1.0.0"
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Import-Module (Join-Path $PSScriptRoot "../../../../../scripts/common/Common.psm1") -Force

$operationId = New-OperationId
$target = "$Owner/$Repo@$Branch"
$uri = "$ApiBaseUrl/repos/$Owner/$Repo/branches/$Branch/protection"

try {
    $token = Read-LocalSecret -System github
    $protection = Invoke-SecureRestMethod -Uri $uri -Method GET -Token $token

    Write-AuditLog -OperationId $operationId -User $User -System "github" `
        -SystemVersion "runtime-detected" -Resource "branch_protection" -Operation "GET" -Target $target `
        -ExecutionMechanism "rest-api" -Skill "github-branch-protection" `
        -Script "get-branch-protection.ps1" -ScriptVersion $ScriptVersion `
        -Risk "READ_ONLY" -ApprovalRequired $false -ApprovalStatus "NOT_REQUIRED" `
        -Result "SUCCESS" -Verification "NOT_APPLICABLE"

    $protection | ConvertTo-Json -Depth 10
    exit ([int][DevOpsExitCode]::Success)
}
catch {
    Write-AuditLog -OperationId $operationId -User $User -System "github" `
        -SystemVersion "runtime-detected" -Resource "branch_protection" -Operation "GET" -Target $target `
        -ExecutionMechanism "rest-api" -Skill "github-branch-protection" `
        -Script "get-branch-protection.ps1" -ScriptVersion $ScriptVersion `
        -Risk "READ_ONLY" -ApprovalRequired $false -ApprovalStatus "NOT_REQUIRED" `
        -Result "FAILURE" -Verification "NOT_APPLICABLE" -Error $_.Exception.Message

    Write-Error "Failed to retrieve branch protection for '$target': $($_.Exception.Message)"
    exit ([int][DevOpsExitCode]::GeneralFailure)
}
