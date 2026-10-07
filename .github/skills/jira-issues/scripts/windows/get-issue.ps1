#Requires -Version 7.0
<#
.SYNOPSIS
    READ_ONLY: Retrieves a Jira Cloud issue.

.DESCRIPTION
    Purpose: Fetch current issue fields (GET, no mutation).
    Supported OS: Windows (PowerShell 7+).
    Dependencies: scripts/common/Common.psm1
    Parameters: SiteUrl (e.g. https://your-domain.atlassian.net),
        IssueKey, Email, ApiToken (SecureString), User
    Authentication: Jira Cloud basic auth (email + API token), per
        https://developer.atlassian.com/cloud/jira/platform/rest/v3/intro/ .
        No local-secrets file is defined for Jira (Section 12) - pass the
        token explicitly or via an environment variable your orchestrator
        populates; never hardcode it.
    Required permissions: "Browse projects" Jira permission.
    Approval requirements: NONE - READ_ONLY.
    Dry-run: not applicable.
    API/MCP dependency: REST fallback used here; prefer the discovered
        Rovo MCP issue-read tool when available (see SKILL.md).
    Exit codes: 0 success, 1 general failure.
    Output: issue JSON on stdout.
    Verification: N/A.
    Audit: writes one READ audit record.
    Security: TLS enforced; token never logged or printed.

.EXAMPLE
    $token = Read-Host -AsSecureString "API token"
    ./get-issue.ps1 -SiteUrl "https://example.atlassian.net" -IssueKey ABC-123 `
        -Email "jdoe@example.com" -ApiToken $token -User jdoe
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$SiteUrl,
    [Parameter(Mandatory = $true)][string]$IssueKey,
    [Parameter(Mandatory = $true)][string]$Email,
    [Parameter(Mandatory = $true)][System.Security.SecureString]$ApiToken,
    [Parameter(Mandatory = $true)][string]$User
)

$ScriptVersion = "1.0.0"
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Import-Module (Join-Path $PSScriptRoot "../../../../../scripts/common/Common.psm1") -Force

$operationId = New-OperationId
$uri = "$SiteUrl/rest/api/3/issue/$IssueKey"

try {
    $plainToken = ConvertFrom-SecureStringPlain -Secure $ApiToken
    $basic = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes("$Email`:$plainToken"))
    $plainToken = $null
    $secureBasic = ConvertTo-SecureString -String $basic -AsPlainText -Force

    $issue = Invoke-SecureRestMethod -Uri $uri -Method GET -Token $secureBasic -AuthScheme "Basic"

    Write-AuditLog -OperationId $operationId -User $User -System "jira" `
        -SystemVersion "cloud" -Resource "issue" -Operation "GET" -Target $IssueKey `
        -ExecutionMechanism "rest-api" -Skill "jira-issues" `
        -Script "get-issue.ps1" -ScriptVersion $ScriptVersion `
        -Risk "READ_ONLY" -ApprovalRequired $false -ApprovalStatus "NOT_REQUIRED" `
        -Result "SUCCESS" -Verification "NOT_APPLICABLE"

    $issue | ConvertTo-Json -Depth 10
    exit ([int][DevOpsExitCode]::Success)
}
catch {
    Write-AuditLog -OperationId $operationId -User $User -System "jira" `
        -SystemVersion "cloud" -Resource "issue" -Operation "GET" -Target $IssueKey `
        -ExecutionMechanism "rest-api" -Skill "jira-issues" `
        -Script "get-issue.ps1" -ScriptVersion $ScriptVersion `
        -Risk "READ_ONLY" -ApprovalRequired $false -ApprovalStatus "NOT_REQUIRED" `
        -Result "FAILURE" -Verification "NOT_APPLICABLE" -Error $_.Exception.Message

    Write-Error "Failed to retrieve issue '$IssueKey': $($_.Exception.Message)"
    exit ([int][DevOpsExitCode]::GeneralFailure)
}
