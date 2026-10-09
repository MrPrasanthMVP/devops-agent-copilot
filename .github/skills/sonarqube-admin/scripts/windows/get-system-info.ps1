#Requires -Version 7.0
<#
.SYNOPSIS
    READ_ONLY: Retrieves SonarQube Server system configuration details.
    Server/Community Build ONLY -- SonarQube Cloud has no equivalent
    self-reported system-info endpoint (it is a managed SaaS instance).

.DESCRIPTION
    Purpose: Fetch instance configuration details (GET, no mutation).
    Supported OS: Windows (PowerShell 7+), cross-platform compatible.
    Dependencies: scripts/common/Common.psm1 (Invoke-SecureRestMethod, Write-AuditLog)
    Parameters: BaseUrl, User
    Authentication: SonarQube user token, read via Read-LocalSecret (POC).
    Required permissions: 'Administer System' permission.
    Approval requirements: NONE - READ_ONLY operations execute immediately.
    Deployment: Server/Community Build ONLY. Do not call this against
        SonarQube Cloud.
    API/MCP dependency: REST fallback used here; prefer the SonarQube MCP
        server's get_system_info tool when available (see SKILL.md).
    Exit codes: 0 success, 3 auth failure, 1 general failure.
    Output: system info JSON object on stdout.
    Verification: N/A (this script IS a read, not something to verify).
    Audit: writes one READ audit record.
    Security: TLS verification enforced; token never logged or printed.

.EXAMPLE
    ./get-system-info.ps1 -BaseUrl "https://sonarqube.example.internal" -User jdoe
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$BaseUrl,
    [Parameter(Mandatory = $true)][string]$User
)

$ScriptVersion = "1.0.0"
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Import-Module (Join-Path $PSScriptRoot "../../../../../scripts/common/Common.psm1") -Force

$operationId = New-OperationId
$target = "server-info"
$uri = "$BaseUrl/api/system/info"

try {
    $token = Read-LocalSecret -System sonarqube
    $info = Invoke-SecureRestMethod -Uri $uri -Method GET -Token $token

    Write-AuditLog -OperationId $operationId -User $User -System "sonarqube" `
        -SystemVersion "runtime-detected" -Resource "system" -Operation "INFO" -Target $target `
        -ExecutionMechanism "rest-api" -Skill "sonarqube-admin" `
        -Script "get-system-info.ps1" -ScriptVersion $ScriptVersion `
        -Risk "READ_ONLY" -ApprovalRequired $false -ApprovalStatus "NOT_REQUIRED" `
        -Result "SUCCESS" -Verification "NOT_APPLICABLE"

    $info | ConvertTo-Json -Depth 10
    exit ([int][DevOpsExitCode]::Success)
}
catch {
    Write-AuditLog -OperationId $operationId -User $User -System "sonarqube" `
        -SystemVersion "runtime-detected" -Resource "system" -Operation "INFO" -Target $target `
        -ExecutionMechanism "rest-api" -Skill "sonarqube-admin" `
        -Script "get-system-info.ps1" -ScriptVersion $ScriptVersion `
        -Risk "READ_ONLY" -ApprovalRequired $false -ApprovalStatus "NOT_REQUIRED" `
        -Result "FAILURE" -Verification "NOT_APPLICABLE" -Error $_.Exception.Message

    Write-Error "Failed to get SonarQube system info: $($_.Exception.Message)"
    exit ([int][DevOpsExitCode]::GeneralFailure)
}
