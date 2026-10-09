#Requires -Version 7.0
<#
.SYNOPSIS
    READ_ONLY: Lists Bitbucket Data Center projects visible to the caller.

.DESCRIPTION
    Purpose: Fetch the paged collection of projects (GET, no mutation).
    Supported OS: Windows (PowerShell 7+), cross-platform compatible.
    Dependencies: scripts/common/Common.psm1
    Parameters: BaseUrl, User, [Filter]
    Authentication: Bitbucket HTTP access token, read via Read-LocalSecret.
    Required permissions: none beyond authentication (results are scoped
        to projects the caller can view).
    Approval requirements: NONE - READ_ONLY operations execute immediately.
    Dry-run: not applicable.
    API/MCP dependency: REST fallback used here; prefer the Bitbucket DC
        MCP server's project-list tool when available (see SKILL.md).
    Exit codes: 0 success, 1 general failure.
    Output: paged project collection JSON on stdout.
    Verification: N/A.
    Audit: writes one READ audit record.
    Security: TLS verification enforced; token never logged or printed.

.EXAMPLE
    ./list-projects.ps1 -BaseUrl "https://bitbucket.example.com" -User jdoe -Filter "PAY"
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$BaseUrl,
    [Parameter(Mandatory = $true)][string]$User,
    [string]$Filter = ""
)

$ScriptVersion = "1.0.0"
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Import-Module (Join-Path $PSScriptRoot "../../../../../scripts/common/Common.psm1") -Force

$operationId = New-OperationId
$target = if ($Filter) { "filter:$Filter" } else { "all" }
$uri = "$BaseUrl/rest/api/1.0/projects"
if ($Filter) { $uri += "?name=$([uri]::EscapeDataString($Filter))" }

try {
    $token = Read-LocalSecret -System bitbucket
    $projects = Invoke-SecureRestMethod -Uri $uri -Method GET -Token $token

    Write-AuditLog -OperationId $operationId -User $User -System "bitbucket" `
        -SystemVersion "runtime-detected" -Resource "project" -Operation "LIST" -Target $target `
        -ExecutionMechanism "rest-api" -Skill "bitbucket-project-admin" `
        -Script "list-projects.ps1" -ScriptVersion $ScriptVersion `
        -Risk "READ_ONLY" -ApprovalRequired $false -ApprovalStatus "NOT_REQUIRED" `
        -Result "SUCCESS" -Verification "NOT_APPLICABLE"

    $projects | ConvertTo-Json -Depth 10
    exit ([int][DevOpsExitCode]::Success)
}
catch {
    Write-AuditLog -OperationId $operationId -User $User -System "bitbucket" `
        -SystemVersion "runtime-detected" -Resource "project" -Operation "LIST" -Target $target `
        -ExecutionMechanism "rest-api" -Skill "bitbucket-project-admin" `
        -Script "list-projects.ps1" -ScriptVersion $ScriptVersion `
        -Risk "READ_ONLY" -ApprovalRequired $false -ApprovalStatus "NOT_REQUIRED" `
        -Result "FAILURE" -Verification "NOT_APPLICABLE" -Error $_.Exception.Message

    Write-Error "Failed to list projects: $($_.Exception.Message)"
    exit ([int][DevOpsExitCode]::GeneralFailure)
}
