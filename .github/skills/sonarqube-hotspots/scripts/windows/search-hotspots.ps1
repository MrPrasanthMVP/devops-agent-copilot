#Requires -Version 7.0
<#
.SYNOPSIS
    READ_ONLY: Searches SonarQube security hotspots.

.DESCRIPTION
    Purpose: Fetch hotspots matching project/status filters (GET, no mutation).
    Supported OS: Windows (PowerShell 7+), cross-platform compatible.
    Dependencies: scripts/common/Common.psm1 (Invoke-SecureRestMethod, Write-AuditLog)
    Parameters: BaseUrl, Organization (optional, Cloud only), ProjectKey
        (optional), Status (optional: TO_REVIEW|REVIEWED), User
    Authentication: SonarQube user token, read via Read-LocalSecret (POC).
    Required permissions: Browse permission on the project(s) searched.
    Approval requirements: NONE - READ_ONLY operations execute immediately.
    Deployment: works against BOTH SonarQube Server/Community Build
        (self-managed -BaseUrl) and SonarQube Cloud (-BaseUrl
        https://sonarcloud.io or https://sonarqube.us, plus -Organization).
    API/MCP dependency: REST fallback used here; prefer the SonarQube MCP
        server's search_security_hotspots tool when available (see SKILL.md).
    Exit codes: 0 success, 3 auth failure, 1 general failure.
    Output: hotspots JSON array on stdout.
    Verification: N/A (this script IS a read, not something to verify).
    Audit: writes one READ audit record.
    Security: TLS verification enforced; token never logged or printed.

.EXAMPLE
    ./search-hotspots.ps1 -BaseUrl "https://sonarqube.example.internal" -ProjectKey my-app -User jdoe
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$BaseUrl,
    [string]$Organization = $null,
    [string]$ProjectKey = $null,
    [ValidateSet('TO_REVIEW', 'REVIEWED')][string]$Status = $null,
    [Parameter(Mandatory = $true)][string]$User
)

$ScriptVersion = "1.0.0"
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Import-Module (Join-Path $PSScriptRoot "../../../../../scripts/common/Common.psm1") -Force

$operationId = New-OperationId
$target = if ($ProjectKey) { $ProjectKey } else { "all-projects" }

$uri = "$BaseUrl/api/hotspots/search?ps=500"
if ($ProjectKey) { $uri += "&projectKey=$ProjectKey" }
if ($Status) { $uri += "&status=$Status" }
if ($Organization) { $uri += "&organization=$Organization" }

try {
    $token = Read-LocalSecret -System sonarqube
    $result = Invoke-SecureRestMethod -Uri $uri -Method GET -Token $token

    Write-AuditLog -OperationId $operationId -User $User -System "sonarqube" `
        -SystemVersion "runtime-detected" -Resource "hotspot" -Operation "SEARCH" -Target $target `
        -ExecutionMechanism "rest-api" -Skill "sonarqube-hotspots" `
        -Script "search-hotspots.ps1" -ScriptVersion $ScriptVersion `
        -Risk "READ_ONLY" -ApprovalRequired $false -ApprovalStatus "NOT_REQUIRED" `
        -Result "SUCCESS" -Verification "NOT_APPLICABLE"

    $result | ConvertTo-Json -Depth 10
    exit ([int][DevOpsExitCode]::Success)
}
catch {
    Write-AuditLog -OperationId $operationId -User $User -System "sonarqube" `
        -SystemVersion "runtime-detected" -Resource "hotspot" -Operation "SEARCH" -Target $target `
        -ExecutionMechanism "rest-api" -Skill "sonarqube-hotspots" `
        -Script "search-hotspots.ps1" -ScriptVersion $ScriptVersion `
        -Risk "READ_ONLY" -ApprovalRequired $false -ApprovalStatus "NOT_REQUIRED" `
        -Result "FAILURE" -Verification "NOT_APPLICABLE" -Error $_.Exception.Message

    Write-Error "Failed to search SonarQube hotspots: $($_.Exception.Message)"
    exit ([int][DevOpsExitCode]::GeneralFailure)
}
