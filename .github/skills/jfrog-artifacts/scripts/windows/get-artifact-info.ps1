#Requires -Version 7.0
<#
.SYNOPSIS
    READ_ONLY: Retrieves JFrog Artifactory storage info for one artifact.

.DESCRIPTION
    Purpose: Fetch size/checksum/metadata for an artifact (GET only).
    Supported OS: Windows (PowerShell 7+).
    Dependencies: scripts/common/Common.psm1
    Parameters: BaseUrl, RepoKey, ItemPath, User
    Authentication: JFrog access token (POC: local-secrets).
    Required permissions: read access on the target repository.
    Approval requirements: NONE - READ_ONLY.
    Dry-run: not applicable.
    API/MCP dependency: REST fallback
        (GET /artifactory/api/storage/{repoKey}/{itemPath}).
    Exit codes: 0 success, 8 not found, 1 general failure.
    Output: storage info JSON on stdout.
    Verification: N/A.
    Audit: writes one READ audit record.
    Security: TLS enforced; ItemPath rejected if it contains ".." path
        traversal segments; token never logged or printed.

.EXAMPLE
    ./get-artifact-info.ps1 -BaseUrl "https://jfrog.example.com" `
        -RepoKey releases-local -ItemPath "com/example/app/1.0/app.jar" -User jdoe
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$BaseUrl,
    [Parameter(Mandatory = $true)][ValidatePattern('^[A-Za-z0-9._-]+$')][string]$RepoKey,
    [Parameter(Mandatory = $true)][string]$ItemPath,
    [Parameter(Mandatory = $true)][string]$User
)

$ScriptVersion = "1.0.0"
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Import-Module (Join-Path $PSScriptRoot "../../../../../scripts/common/Common.psm1") -Force

if ($ItemPath -match '\.\.') {
    Write-Error "ItemPath must not contain '..' path traversal segments."
    exit ([int][DevOpsExitCode]::InvalidParameters)
}

$operationId = New-OperationId
$target = "$RepoKey/$ItemPath"
$uri = "$BaseUrl/artifactory/api/storage/$RepoKey/$ItemPath"

try {
    $token = Read-LocalSecret -System jfrog
    $info = Invoke-SecureRestMethod -Uri $uri -Method GET -Token $token

    Write-AuditLog -OperationId $operationId -User $User -System "jfrog" `
        -SystemVersion "runtime-detected" -Resource "artifact" -Operation "GET" -Target $target `
        -ExecutionMechanism "rest-api" -Skill "jfrog-artifacts" `
        -Script "get-artifact-info.ps1" -ScriptVersion $ScriptVersion `
        -Risk "READ_ONLY" -ApprovalRequired $false -ApprovalStatus "NOT_REQUIRED" `
        -Result "SUCCESS" -Verification "NOT_APPLICABLE"

    $info | ConvertTo-Json -Depth 10
    exit ([int][DevOpsExitCode]::Success)
}
catch {
    Write-AuditLog -OperationId $operationId -User $User -System "jfrog" `
        -SystemVersion "runtime-detected" -Resource "artifact" -Operation "GET" -Target $target `
        -ExecutionMechanism "rest-api" -Skill "jfrog-artifacts" `
        -Script "get-artifact-info.ps1" -ScriptVersion $ScriptVersion `
        -Risk "READ_ONLY" -ApprovalRequired $false -ApprovalStatus "NOT_REQUIRED" `
        -Result "FAILURE" -Verification "NOT_APPLICABLE" -Error $_.Exception.Message

    Write-Error "Failed to retrieve artifact info for '$target': $($_.Exception.Message)"
    exit ([int][DevOpsExitCode]::GeneralFailure)
}
