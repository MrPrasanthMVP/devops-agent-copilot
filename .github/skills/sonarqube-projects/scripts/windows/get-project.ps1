#Requires -Version 7.0
<#
.SYNOPSIS
    READ_ONLY: Retrieves a single SonarQube project by key.

.DESCRIPTION
    Purpose: Fetch one project's details (GET via api/projects/search
        with projects=<key> -- SonarQube has no single-object project
        GET endpoint).
    Supported OS: Windows (PowerShell 7+), cross-platform compatible.
    Dependencies: scripts/common/Common.psm1
    Parameters: BaseUrl, ProjectKey, Organization (optional, Cloud only), User
    Authentication: SonarQube user token, read via Read-LocalSecret (POC).
    Required permissions: Browse permission on the project.
    Approval requirements: NONE - READ_ONLY operations execute immediately.
    Deployment: works against BOTH Server and Cloud (pass -Organization for Cloud).
    API/MCP dependency: REST fallback used here; prefer the SonarQube MCP
        server's project-read tool when available (see SKILL.md).
    Exit codes: 0 success, 3 auth failure, 8 not found, 1 general failure.
    Output: project JSON object on stdout.
    Verification: N/A.
    Audit: writes one READ audit record.
    Security: TLS verification enforced; token never logged or printed.

.EXAMPLE
    ./get-project.ps1 -BaseUrl "https://sonarqube.example.internal" -ProjectKey my-app -User jdoe
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$BaseUrl,
    [Parameter(Mandatory = $true)][string]$ProjectKey,
    [string]$Organization = $null,
    [Parameter(Mandatory = $true)][string]$User
)

$ScriptVersion = "1.0.0"
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Import-Module (Join-Path $PSScriptRoot "../../../../../scripts/common/Common.psm1") -Force

$operationId = New-OperationId
$target = $ProjectKey
$uri = "$BaseUrl/api/projects/search?projects=$ProjectKey"
if ($Organization) { $uri += "&organization=$Organization" }

try {
    $token = Read-LocalSecret -System sonarqube
    $result = Invoke-SecureRestMethod -Uri $uri -Method GET -Token $token

    if (-not $result.components -or $result.components.Count -eq 0) {
        Write-AuditLog -OperationId $operationId -User $User -System "sonarqube" `
            -SystemVersion "runtime-detected" -Resource "project" -Operation "GET" -Target $target `
            -ExecutionMechanism "rest-api" -Skill "sonarqube-projects" `
            -Script "get-project.ps1" -ScriptVersion $ScriptVersion `
            -Risk "READ_ONLY" -ApprovalRequired $false -ApprovalStatus "NOT_REQUIRED" `
            -Result "FAILURE" -Verification "NOT_APPLICABLE" -Error "project not found"
        Write-Error "Project '$target' not found."
        exit ([int][DevOpsExitCode]::TargetNotFound)
    }

    Write-AuditLog -OperationId $operationId -User $User -System "sonarqube" `
        -SystemVersion "runtime-detected" -Resource "project" -Operation "GET" -Target $target `
        -ExecutionMechanism "rest-api" -Skill "sonarqube-projects" `
        -Script "get-project.ps1" -ScriptVersion $ScriptVersion `
        -Risk "READ_ONLY" -ApprovalRequired $false -ApprovalStatus "NOT_REQUIRED" `
        -Result "SUCCESS" -Verification "NOT_APPLICABLE"

    $result.components[0] | ConvertTo-Json -Depth 10
    exit ([int][DevOpsExitCode]::Success)
}
catch {
    Write-AuditLog -OperationId $operationId -User $User -System "sonarqube" `
        -SystemVersion "runtime-detected" -Resource "project" -Operation "GET" -Target $target `
        -ExecutionMechanism "rest-api" -Skill "sonarqube-projects" `
        -Script "get-project.ps1" -ScriptVersion $ScriptVersion `
        -Risk "READ_ONLY" -ApprovalRequired $false -ApprovalStatus "NOT_REQUIRED" `
        -Result "FAILURE" -Verification "NOT_APPLICABLE" -Error $_.Exception.Message

    Write-Error "Failed to retrieve project '$target': $($_.Exception.Message)"
    exit ([int][DevOpsExitCode]::GeneralFailure)
}
