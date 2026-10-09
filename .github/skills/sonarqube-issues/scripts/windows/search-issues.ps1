#Requires -Version 7.0
<#
.SYNOPSIS
    READ_ONLY: Searches SonarQube issues.

.DESCRIPTION
    Purpose: Fetch issues matching project/assignee/status filters (GET, no mutation).
    Supported OS: Windows (PowerShell 7+), cross-platform compatible.
    Dependencies: scripts/common/Common.psm1 (Invoke-SecureRestMethod, Write-AuditLog)
    Parameters: BaseUrl, Organization (optional, Cloud only), ProjectKeys
        (optional, comma-separated), IssueKeys (optional, comma-separated),
        Assignees (optional, comma-separated), Statuses (optional,
        comma-separated), User
    Authentication: SonarQube user token, read via Read-LocalSecret (POC).
    Required permissions: Browse permission on the project(s) searched.
    Approval requirements: NONE - READ_ONLY operations execute immediately.
    Deployment: works against BOTH SonarQube Server/Community Build
        (self-managed -BaseUrl) and SonarQube Cloud (-BaseUrl
        https://sonarcloud.io or https://sonarqube.us, plus -Organization).
    API/MCP dependency: REST fallback used here; prefer the SonarQube MCP
        server's search_sonar_issues_in_projects tool when available (see SKILL.md).
    Exit codes: 0 success, 3 auth failure, 1 general failure.
    Output: issues JSON array on stdout.
    Verification: N/A (this script IS a read, not something to verify).
    Audit: writes one READ audit record.
    Security: TLS verification enforced; token never logged or printed.

.EXAMPLE
    ./search-issues.ps1 -BaseUrl "https://sonarqube.example.internal" -ProjectKeys my-app -User jdoe
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$BaseUrl,
    [string]$Organization = $null,
    [string]$ProjectKeys = $null,
    [string]$IssueKeys = $null,
    [string]$Assignees = $null,
    [string]$Statuses = $null,
    [Parameter(Mandatory = $true)][string]$User
)

$ScriptVersion = "1.0.0"
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Import-Module (Join-Path $PSScriptRoot "../../../../../scripts/common/Common.psm1") -Force

$operationId = New-OperationId
$target = if ($ProjectKeys) { "projects:$ProjectKeys" } elseif ($IssueKeys) { "issues:$IssueKeys" } else { "all-issues" }

$uri = "$BaseUrl/api/issues/search?ps=500"
if ($ProjectKeys) { $uri += "&componentKeys=$ProjectKeys" }
if ($IssueKeys) { $uri += "&issues=$IssueKeys" }
if ($Assignees) { $uri += "&assignees=$Assignees" }
if ($Statuses) { $uri += "&issueStatuses=$Statuses" }
if ($Organization) { $uri += "&organization=$Organization" }

try {
    $token = Read-LocalSecret -System sonarqube
    $result = Invoke-SecureRestMethod -Uri $uri -Method GET -Token $token

    Write-AuditLog -OperationId $operationId -User $User -System "sonarqube" `
        -SystemVersion "runtime-detected" -Resource "issue" -Operation "SEARCH" -Target $target `
        -ExecutionMechanism "rest-api" -Skill "sonarqube-issues" `
        -Script "search-issues.ps1" -ScriptVersion $ScriptVersion `
        -Risk "READ_ONLY" -ApprovalRequired $false -ApprovalStatus "NOT_REQUIRED" `
        -Result "SUCCESS" -Verification "NOT_APPLICABLE"

    $result | ConvertTo-Json -Depth 10
    exit ([int][DevOpsExitCode]::Success)
}
catch {
    Write-AuditLog -OperationId $operationId -User $User -System "sonarqube" `
        -SystemVersion "runtime-detected" -Resource "issue" -Operation "SEARCH" -Target $target `
        -ExecutionMechanism "rest-api" -Skill "sonarqube-issues" `
        -Script "search-issues.ps1" -ScriptVersion $ScriptVersion `
        -Risk "READ_ONLY" -ApprovalRequired $false -ApprovalStatus "NOT_REQUIRED" `
        -Result "FAILURE" -Verification "NOT_APPLICABLE" -Error $_.Exception.Message

    Write-Error "Failed to search SonarQube issues: $($_.Exception.Message)"
    exit ([int][DevOpsExitCode]::GeneralFailure)
}
