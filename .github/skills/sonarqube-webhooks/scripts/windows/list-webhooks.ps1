#Requires -Version 7.0
<#
.SYNOPSIS
    READ_ONLY: Lists SonarQube webhooks (global, or project-scoped).

.DESCRIPTION
    Purpose: Fetch webhook configuration (GET, no mutation).
    Supported OS: Windows (PowerShell 7+), cross-platform compatible.
    Dependencies: scripts/common/Common.psm1 (Invoke-SecureRestMethod, Write-AuditLog)
    Parameters: BaseUrl, ProjectKey (optional - omit for global webhooks),
        Organization (optional, Cloud only), User
    Authentication: SonarQube user token, read via Read-LocalSecret (POC).
    Required permissions: 'Administer System' (global) or 'Administer' on
        the project (project-scoped).
    Approval requirements: NONE - READ_ONLY operations execute immediately.
    Deployment: works against BOTH Server and Cloud (pass -Organization for Cloud).
    API/MCP dependency: REST fallback used here; prefer the SonarQube MCP
        server's list_webhooks tool when available (see SKILL.md).
    Exit codes: 0 success, 3 auth failure, 1 general failure.
    Output: webhooks JSON array on stdout.
    Verification: N/A (this script IS a read, not something to verify).
    Audit: writes one READ audit record.
    Security: TLS verification enforced; token never logged or printed.

.EXAMPLE
    ./list-webhooks.ps1 -BaseUrl "https://sonarqube.example.internal" -User jdoe
    ./list-webhooks.ps1 -BaseUrl "https://sonarqube.example.internal" -ProjectKey my-app -User jdoe
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$BaseUrl,
    [string]$ProjectKey = $null,
    [string]$Organization = $null,
    [Parameter(Mandatory = $true)][string]$User
)

$ScriptVersion = "1.0.0"
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Import-Module (Join-Path $PSScriptRoot "../../../../../scripts/common/Common.psm1") -Force

$operationId = New-OperationId
$target = if ($ProjectKey) { $ProjectKey } else { "global" }

$uri = "$BaseUrl/api/webhooks/list"
$qs = @()
if ($ProjectKey) { $qs += "project=$ProjectKey" }
if ($Organization) { $qs += "organization=$Organization" }
if ($qs.Count -gt 0) { $uri += "?" + ($qs -join "&") }

try {
    $token = Read-LocalSecret -System sonarqube
    $result = Invoke-SecureRestMethod -Uri $uri -Method GET -Token $token

    Write-AuditLog -OperationId $operationId -User $User -System "sonarqube" `
        -SystemVersion "runtime-detected" -Resource "webhook" -Operation "LIST" -Target $target `
        -ExecutionMechanism "rest-api" -Skill "sonarqube-webhooks" `
        -Script "list-webhooks.ps1" -ScriptVersion $ScriptVersion `
        -Risk "READ_ONLY" -ApprovalRequired $false -ApprovalStatus "NOT_REQUIRED" `
        -Result "SUCCESS" -Verification "NOT_APPLICABLE"

    $result | ConvertTo-Json -Depth 10
    exit ([int][DevOpsExitCode]::Success)
}
catch {
    Write-AuditLog -OperationId $operationId -User $User -System "sonarqube" `
        -SystemVersion "runtime-detected" -Resource "webhook" -Operation "LIST" -Target $target `
        -ExecutionMechanism "rest-api" -Skill "sonarqube-webhooks" `
        -Script "list-webhooks.ps1" -ScriptVersion $ScriptVersion `
        -Risk "READ_ONLY" -ApprovalRequired $false -ApprovalStatus "NOT_REQUIRED" `
        -Result "FAILURE" -Verification "NOT_APPLICABLE" -Error $_.Exception.Message

    Write-Error "Failed to list SonarQube webhooks: $($_.Exception.Message)"
    exit ([int][DevOpsExitCode]::GeneralFailure)
}
