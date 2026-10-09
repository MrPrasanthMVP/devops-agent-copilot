#Requires -Version 7.0
<#
.SYNOPSIS
    READ_ONLY: Retrieves detailed information for one SonarQube security hotspot.

.DESCRIPTION
    Purpose: Fetch a single hotspot's details (GET, no mutation).
    Supported OS: Windows (PowerShell 7+), cross-platform compatible.
    Dependencies: scripts/common/Common.psm1 (Invoke-SecureRestMethod, Write-AuditLog)
    Parameters: BaseUrl, HotspotKey, Organization (optional, Cloud only), User
    Authentication: SonarQube user token, read via Read-LocalSecret (POC).
    Required permissions: Browse permission on the hotspot's project.
    Approval requirements: NONE - READ_ONLY operations execute immediately.
    Deployment: works against BOTH Server and Cloud (pass -Organization for Cloud).
    API/MCP dependency: REST fallback used here; prefer the SonarQube MCP
        server's show_security_hotspot tool when available (see SKILL.md).
    Exit codes: 0 success, 3 auth failure, 8 not found, 1 general failure.
    Output: hotspot JSON object on stdout.
    Verification: N/A (this script IS a read, not something to verify).
    Audit: writes one READ audit record.
    Security: TLS verification enforced; token never logged or printed.

.EXAMPLE
    ./show-hotspot.ps1 -BaseUrl "https://sonarqube.example.internal" -HotspotKey AbCd1234 -User jdoe
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$BaseUrl,
    [Parameter(Mandatory = $true)][string]$HotspotKey,
    [string]$Organization = $null,
    [Parameter(Mandatory = $true)][string]$User
)

$ScriptVersion = "1.0.0"
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Import-Module (Join-Path $PSScriptRoot "../../../../../scripts/common/Common.psm1") -Force

$operationId = New-OperationId
$target = $HotspotKey
$uri = "$BaseUrl/api/hotspots/show?hotspot=$HotspotKey"
if ($Organization) { $uri += "&organization=$Organization" }

try {
    $token = Read-LocalSecret -System sonarqube
    $hotspot = Invoke-SecureRestMethod -Uri $uri -Method GET -Token $token

    Write-AuditLog -OperationId $operationId -User $User -System "sonarqube" `
        -SystemVersion "runtime-detected" -Resource "hotspot" -Operation "GET" -Target $target `
        -ExecutionMechanism "rest-api" -Skill "sonarqube-hotspots" `
        -Script "show-hotspot.ps1" -ScriptVersion $ScriptVersion `
        -Risk "READ_ONLY" -ApprovalRequired $false -ApprovalStatus "NOT_REQUIRED" `
        -Result "SUCCESS" -Verification "NOT_APPLICABLE"

    $hotspot | ConvertTo-Json -Depth 10
    exit ([int][DevOpsExitCode]::Success)
}
catch {
    Write-AuditLog -OperationId $operationId -User $User -System "sonarqube" `
        -SystemVersion "runtime-detected" -Resource "hotspot" -Operation "GET" -Target $target `
        -ExecutionMechanism "rest-api" -Skill "sonarqube-hotspots" `
        -Script "show-hotspot.ps1" -ScriptVersion $ScriptVersion `
        -Risk "READ_ONLY" -ApprovalRequired $false -ApprovalStatus "NOT_REQUIRED" `
        -Result "FAILURE" -Verification "NOT_APPLICABLE" -Error $_.Exception.Message

    Write-Error "Failed to retrieve hotspot '$target': $($_.Exception.Message)"
    exit ([int][DevOpsExitCode]::GeneralFailure)
}
