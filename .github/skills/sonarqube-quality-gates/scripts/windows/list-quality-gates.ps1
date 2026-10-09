#Requires -Version 7.0
<#
.SYNOPSIS
    READ_ONLY: Lists all SonarQube quality gates defined on the instance/organization.

.DESCRIPTION
    Purpose: Fetch the quality gate list (GET, no mutation).
    Supported OS: Windows (PowerShell 7+), cross-platform compatible.
    Dependencies: scripts/common/Common.psm1
    Parameters: BaseUrl, Organization (optional, Cloud only), User
    Authentication: SonarQube user token, read via Read-LocalSecret (POC).
    Required permissions: none beyond a valid token (instance-wide read).
    Approval requirements: NONE - READ_ONLY operations execute immediately.
    Deployment: works against BOTH Server and Cloud (pass -Organization for Cloud).
    API/MCP dependency: REST fallback used here; prefer the SonarQube MCP
        server's quality-gate-list tool when available (see SKILL.md).
    Exit codes: 0 success, 3 auth failure, 1 general failure.
    Output: quality gates JSON array on stdout.
    Verification: N/A.
    Audit: writes one READ audit record.
    Security: TLS verification enforced; token never logged or printed.

.EXAMPLE
    ./list-quality-gates.ps1 -BaseUrl "https://sonarqube.example.internal" -User jdoe
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$BaseUrl,
    [string]$Organization = $null,
    [Parameter(Mandatory = $true)][string]$User
)

$ScriptVersion = "1.0.0"
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Import-Module (Join-Path $PSScriptRoot "../../../../../scripts/common/Common.psm1") -Force

$operationId = New-OperationId
$target = "all-quality-gates"
$uri = "$BaseUrl/api/qualitygates/list"
if ($Organization) { $uri += "?organization=$Organization" }

try {
    $token = Read-LocalSecret -System sonarqube
    $result = Invoke-SecureRestMethod -Uri $uri -Method GET -Token $token

    Write-AuditLog -OperationId $operationId -User $User -System "sonarqube" `
        -SystemVersion "runtime-detected" -Resource "quality_gate" -Operation "LIST" -Target $target `
        -ExecutionMechanism "rest-api" -Skill "sonarqube-quality-gates" `
        -Script "list-quality-gates.ps1" -ScriptVersion $ScriptVersion `
        -Risk "READ_ONLY" -ApprovalRequired $false -ApprovalStatus "NOT_REQUIRED" `
        -Result "SUCCESS" -Verification "NOT_APPLICABLE"

    $result | ConvertTo-Json -Depth 10
    exit ([int][DevOpsExitCode]::Success)
}
catch {
    Write-AuditLog -OperationId $operationId -User $User -System "sonarqube" `
        -SystemVersion "runtime-detected" -Resource "quality_gate" -Operation "LIST" -Target $target `
        -ExecutionMechanism "rest-api" -Skill "sonarqube-quality-gates" `
        -Script "list-quality-gates.ps1" -ScriptVersion $ScriptVersion `
        -Risk "READ_ONLY" -ApprovalRequired $false -ApprovalStatus "NOT_REQUIRED" `
        -Result "FAILURE" -Verification "NOT_APPLICABLE" -Error $_.Exception.Message

    Write-Error "Failed to list quality gates: $($_.Exception.Message)"
    exit ([int][DevOpsExitCode]::GeneralFailure)
}
