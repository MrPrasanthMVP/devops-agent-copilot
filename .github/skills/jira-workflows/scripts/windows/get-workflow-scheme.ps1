#Requires -Version 7.0
<#
.SYNOPSIS
    READ_ONLY: Retrieves a Jira Cloud workflow scheme.

.DESCRIPTION
    Purpose: Fetch current workflow scheme configuration (GET, no mutation).
    Supported OS: Windows (PowerShell 7+).
    Dependencies: scripts/common/Common.psm1
    Parameters: SiteUrl, SchemeId, Email, ApiToken, User
    Authentication: Jira Cloud basic auth (email + API token).
    Required permissions: "Administer Jira" global permission.
    Approval requirements: NONE - READ_ONLY.
    Dry-run: not applicable.
    API/MCP dependency: REST fallback; prefer discovered Rovo MCP tool.
    Exit codes: 0 success, 1 general failure.
    Output: workflow scheme JSON on stdout.
    Verification: N/A. Audit: writes one READ audit record.
    Security: TLS enforced; token never logged or printed.

.EXAMPLE
    ./get-workflow-scheme.ps1 -SiteUrl "https://example.atlassian.net" -SchemeId 10001 `
        -Email jdoe@example.com -ApiToken $token -User jdoe
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$SiteUrl,
    [Parameter(Mandatory = $true)][string]$SchemeId,
    [Parameter(Mandatory = $true)][string]$Email,
    [Parameter(Mandatory = $true)][System.Security.SecureString]$ApiToken,
    [Parameter(Mandatory = $true)][string]$User
)

$ScriptVersion = "1.0.0"
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Import-Module (Join-Path $PSScriptRoot "../../../../../scripts/common/Common.psm1") -Force

$operationId = New-OperationId
$uri = "$SiteUrl/rest/api/3/workflowscheme/$SchemeId"

try {
    $plainToken = ConvertFrom-SecureStringPlain -Secure $ApiToken
    $basic = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes("$Email`:$plainToken"))
    $plainToken = $null
    $secureBasic = ConvertTo-SecureString -String $basic -AsPlainText -Force

    $scheme = Invoke-SecureRestMethod -Uri $uri -Method GET -Token $secureBasic -AuthScheme "Basic"

    Write-AuditLog -OperationId $operationId -User $User -System "jira" `
        -SystemVersion "cloud" -Resource "workflow_scheme" -Operation "GET" -Target $SchemeId `
        -ExecutionMechanism "rest-api" -Skill "jira-workflows" `
        -Script "get-workflow-scheme.ps1" -ScriptVersion $ScriptVersion `
        -Risk "READ_ONLY" -ApprovalRequired $false -ApprovalStatus "NOT_REQUIRED" `
        -Result "SUCCESS" -Verification "NOT_APPLICABLE"

    $scheme | ConvertTo-Json -Depth 10
    exit ([int][DevOpsExitCode]::Success)
}
catch {
    Write-AuditLog -OperationId $operationId -User $User -System "jira" `
        -SystemVersion "cloud" -Resource "workflow_scheme" -Operation "GET" -Target $SchemeId `
        -ExecutionMechanism "rest-api" -Skill "jira-workflows" `
        -Script "get-workflow-scheme.ps1" -ScriptVersion $ScriptVersion `
        -Risk "READ_ONLY" -ApprovalRequired $false -ApprovalStatus "NOT_REQUIRED" `
        -Result "FAILURE" -Verification "NOT_APPLICABLE" -Error $_.Exception.Message

    Write-Error "Failed to retrieve workflow scheme '$SchemeId': $($_.Exception.Message)"
    exit ([int][DevOpsExitCode]::GeneralFailure)
}
