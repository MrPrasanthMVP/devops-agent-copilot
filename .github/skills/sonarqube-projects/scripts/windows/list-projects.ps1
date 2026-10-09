#Requires -Version 7.0
<#
.SYNOPSIS
    READ_ONLY: Lists/searches SonarQube projects.

.DESCRIPTION
    Purpose: Fetch the project list (GET, no mutation).
    Supported OS: Windows (PowerShell 7+), cross-platform compatible.
    Dependencies: scripts/common/Common.psm1 (Invoke-SecureRestMethod, Write-AuditLog)
    Parameters: BaseUrl, Organization (optional, Cloud only), Query (optional), User
    Authentication: SonarQube user token, read via Read-LocalSecret (POC).
    Required permissions: Browse permission on the projects returned.
    Approval requirements: NONE - READ_ONLY operations execute immediately.
    Deployment: works against BOTH SonarQube Server/Community Build
        (self-managed -BaseUrl) and SonarQube Cloud (-BaseUrl
        https://sonarcloud.io or https://sonarqube.us, plus -Organization).
    API/MCP dependency: REST fallback used here; prefer the SonarQube MCP
        server's project-search tool when available (see SKILL.md).
    Exit codes: 0 success, 3 auth failure, 1 general failure.
    Output: projects JSON array on stdout.
    Verification: N/A (this script IS a read, not something to verify).
    Audit: writes one READ audit record.
    Security: TLS verification enforced; token never logged or printed.

.EXAMPLE
    ./list-projects.ps1 -BaseUrl "https://sonarqube.example.internal" -User jdoe
    ./list-projects.ps1 -BaseUrl "https://sonarcloud.io" -Organization my-org -User jdoe
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$BaseUrl,
    [string]$Organization = $null,
    [string]$Query = $null,
    [Parameter(Mandatory = $true)][string]$User
)

$ScriptVersion = "1.0.0"
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Import-Module (Join-Path $PSScriptRoot "../../../../../scripts/common/Common.psm1") -Force

$operationId = New-OperationId
$target = if ($Query) { "search:$Query" } else { "all-projects" }

$uri = "$BaseUrl/api/projects/search?ps=500"
if ($Query) { $uri += "&q=$Query" }
if ($Organization) { $uri += "&organization=$Organization" }

try {
    $token = Read-LocalSecret -System sonarqube
    $result = Invoke-SecureRestMethod -Uri $uri -Method GET -Token $token

    Write-AuditLog -OperationId $operationId -User $User -System "sonarqube" `
        -SystemVersion "runtime-detected" -Resource "project" -Operation "LIST" -Target $target `
        -ExecutionMechanism "rest-api" -Skill "sonarqube-projects" `
        -Script "list-projects.ps1" -ScriptVersion $ScriptVersion `
        -Risk "READ_ONLY" -ApprovalRequired $false -ApprovalStatus "NOT_REQUIRED" `
        -Result "SUCCESS" -Verification "NOT_APPLICABLE"

    $result | ConvertTo-Json -Depth 10
    exit ([int][DevOpsExitCode]::Success)
}
catch {
    Write-AuditLog -OperationId $operationId -User $User -System "sonarqube" `
        -SystemVersion "runtime-detected" -Resource "project" -Operation "LIST" -Target $target `
        -ExecutionMechanism "rest-api" -Skill "sonarqube-projects" `
        -Script "list-projects.ps1" -ScriptVersion $ScriptVersion `
        -Risk "READ_ONLY" -ApprovalRequired $false -ApprovalStatus "NOT_REQUIRED" `
        -Result "FAILURE" -Verification "NOT_APPLICABLE" -Error $_.Exception.Message

    Write-Error "Failed to list SonarQube projects: $($_.Exception.Message)"
    exit ([int][DevOpsExitCode]::GeneralFailure)
}
