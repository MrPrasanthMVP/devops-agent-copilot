#Requires -Version 7.0
<#
.SYNOPSIS
    READ_ONLY: Retrieves a JFrog Artifactory repository configuration.

.DESCRIPTION
    Purpose: Fetch current repository configuration (GET, no mutation).
    Supported OS: Windows (PowerShell 7+).
    Dependencies: scripts/common/Common.psm1
    Parameters: BaseUrl, RepoKey, User
    Authentication: JFrog access token (POC: local-secrets).
    Required permissions: read access to repository configuration.
    Approval requirements: NONE - READ_ONLY.
    Dry-run: not applicable.
    API/MCP dependency: REST fallback
        (GET /artifactory/api/repositories/{repoKey}); prefer the
        discovered JFrog MCP repository-read tool when available.
    Exit codes: 0 success, 1 general failure.
    Output: repository configuration JSON on stdout.
    Verification: N/A.
    Audit: writes one READ audit record.
    Security: TLS enforced; token never logged or printed.

.EXAMPLE
    ./get-repository.ps1 -BaseUrl "https://jfrog.example.com" -RepoKey releases-local -User jdoe
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$BaseUrl,
    [Parameter(Mandatory = $true)][ValidatePattern('^[A-Za-z0-9._-]+$')][string]$RepoKey,
    [Parameter(Mandatory = $true)][string]$User
)

$ScriptVersion = "1.0.0"
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Import-Module (Join-Path $PSScriptRoot "../../../../../scripts/common/Common.psm1") -Force

$operationId = New-OperationId
$uri = "$BaseUrl/artifactory/api/repositories/$RepoKey"

try {
    $token = Read-LocalSecret -System jfrog
    $repo = Invoke-SecureRestMethod -Uri $uri -Method GET -Token $token

    Write-AuditLog -OperationId $operationId -User $User -System "jfrog" `
        -SystemVersion "runtime-detected" -Resource "repository" -Operation "GET" -Target $RepoKey `
        -ExecutionMechanism "rest-api" -Skill "jfrog-repositories" `
        -Script "get-repository.ps1" -ScriptVersion $ScriptVersion `
        -Risk "READ_ONLY" -ApprovalRequired $false -ApprovalStatus "NOT_REQUIRED" `
        -Result "SUCCESS" -Verification "NOT_APPLICABLE"

    $repo | ConvertTo-Json -Depth 10
    exit ([int][DevOpsExitCode]::Success)
}
catch {
    Write-AuditLog -OperationId $operationId -User $User -System "jfrog" `
        -SystemVersion "runtime-detected" -Resource "repository" -Operation "GET" -Target $RepoKey `
        -ExecutionMechanism "rest-api" -Skill "jfrog-repositories" `
        -Script "get-repository.ps1" -ScriptVersion $ScriptVersion `
        -Risk "READ_ONLY" -ApprovalRequired $false -ApprovalStatus "NOT_REQUIRED" `
        -Result "FAILURE" -Verification "NOT_APPLICABLE" -Error $_.Exception.Message

    Write-Error "Failed to retrieve repository '$RepoKey': $($_.Exception.Message)"
    exit ([int][DevOpsExitCode]::GeneralFailure)
}
