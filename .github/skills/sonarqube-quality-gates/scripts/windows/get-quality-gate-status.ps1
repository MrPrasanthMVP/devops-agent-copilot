#Requires -Version 7.0
<#
.SYNOPSIS
    READ_ONLY: Gets a project's current quality gate status (PASSED/FAILED/NONE).

.DESCRIPTION
    Purpose: Fetch the computed quality gate status for a project's
        latest analysis (GET, no mutation).
    Supported OS: Windows (PowerShell 7+), cross-platform compatible.
    Dependencies: scripts/common/Common.psm1
    Parameters: BaseUrl, ProjectKey, Branch (optional), Organization (optional, Cloud only), User
    Authentication: SonarQube user token, read via Read-LocalSecret (POC).
    Required permissions: 'Browse' permission on the project.
    Approval requirements: NONE - READ_ONLY operations execute immediately.
    Deployment: works against BOTH Server and Cloud (pass -Organization for Cloud).
    API/MCP dependency: REST fallback used here; prefer the SonarQube MCP
        server's quality-gate-status tool when available (see SKILL.md).
    Exit codes: 0 success, 3 auth failure, 8 not found, 1 general failure.
    Output: project status JSON object on stdout.
    Verification: N/A.
    Audit: writes one READ audit record.
    Security: TLS verification enforced; token never logged or printed.

.EXAMPLE
    ./get-quality-gate-status.ps1 -BaseUrl "https://sonarqube.example.internal" -ProjectKey my-app -User jdoe
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$BaseUrl,
    [Parameter(Mandatory = $true)][string]$ProjectKey,
    [string]$Branch = $null,
    [string]$Organization = $null,
    [Parameter(Mandatory = $true)][string]$User
)

$ScriptVersion = "1.0.0"
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Import-Module (Join-Path $PSScriptRoot "../../../../../scripts/common/Common.psm1") -Force

$operationId = New-OperationId
$target = $ProjectKey
$uri = "$BaseUrl/api/qualitygates/project_status?projectKey=$ProjectKey"
if ($Branch) { $uri += "&branch=$Branch" }
if ($Organization) { $uri += "&organization=$Organization" }

try {
    $token = Read-LocalSecret -System sonarqube
    $result = Invoke-SecureRestMethod -Uri $uri -Method GET -Token $token

    Write-AuditLog -OperationId $operationId -User $User -System "sonarqube" `
        -SystemVersion "runtime-detected" -Resource "quality_gate" -Operation "STATUS" -Target $target `
        -ExecutionMechanism "rest-api" -Skill "sonarqube-quality-gates" `
        -Script "get-quality-gate-status.ps1" -ScriptVersion $ScriptVersion `
        -Risk "READ_ONLY" -ApprovalRequired $false -ApprovalStatus "NOT_REQUIRED" `
        -Result "SUCCESS" -Verification "NOT_APPLICABLE"

    $result | ConvertTo-Json -Depth 10
    exit ([int][DevOpsExitCode]::Success)
}
catch {
    $status = $_.Exception.Response.StatusCode.value__
    $exitCode = if ($status -eq 404) { [int][DevOpsExitCode]::TargetNotFound } else { [int][DevOpsExitCode]::GeneralFailure }

    Write-AuditLog -OperationId $operationId -User $User -System "sonarqube" `
        -SystemVersion "runtime-detected" -Resource "quality_gate" -Operation "STATUS" -Target $target `
        -ExecutionMechanism "rest-api" -Skill "sonarqube-quality-gates" `
        -Script "get-quality-gate-status.ps1" -ScriptVersion $ScriptVersion `
        -Risk "READ_ONLY" -ApprovalRequired $false -ApprovalStatus "NOT_REQUIRED" `
        -Result "FAILURE" -Verification "NOT_APPLICABLE" -Error $_.Exception.Message

    Write-Error "Failed to get quality gate status for '$target': $($_.Exception.Message)"
    exit $exitCode
}
