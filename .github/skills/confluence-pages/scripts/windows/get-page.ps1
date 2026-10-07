#Requires -Version 7.0
<#
.SYNOPSIS
    READ_ONLY: Retrieves a Confluence Cloud page.

.DESCRIPTION
    Purpose: Fetch current page content/version (GET, no mutation).
    Supported OS: Windows (PowerShell 7+).
    Dependencies: scripts/common/Common.psm1
    Parameters: SiteUrl, PageId, Email, ApiToken, User
    Authentication: Confluence Cloud basic auth (email + API token).
    Required permissions: "View" permission on the page's space.
    Approval requirements: NONE - READ_ONLY.
    Dry-run: not applicable.
    API/MCP dependency: REST fallback; prefer discovered Rovo MCP read tool.
    Exit codes: 0 success, 1 general failure.
    Output: page JSON on stdout (includes version.number needed for updates).
    Verification: N/A.
    Audit: writes one READ audit record.
    Security: TLS enforced; token never logged or printed.

.EXAMPLE
    ./get-page.ps1 -SiteUrl "https://example.atlassian.net" -PageId 123456 `
        -Email jdoe@example.com -ApiToken $token -User jdoe
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$SiteUrl,
    [Parameter(Mandatory = $true)][string]$PageId,
    [Parameter(Mandatory = $true)][string]$Email,
    [Parameter(Mandatory = $true)][System.Security.SecureString]$ApiToken,
    [Parameter(Mandatory = $true)][string]$User
)

$ScriptVersion = "1.0.0"
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Import-Module (Join-Path $PSScriptRoot "../../../../../scripts/common/Common.psm1") -Force

$operationId = New-OperationId
$uri = "$SiteUrl/wiki/api/v2/pages/$PageId`?body-format=storage"

try {
    $plainToken = ConvertFrom-SecureStringPlain -Secure $ApiToken
    $basic = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes("$Email`:$plainToken"))
    $plainToken = $null
    $secureBasic = ConvertTo-SecureString -String $basic -AsPlainText -Force

    $page = Invoke-SecureRestMethod -Uri $uri -Method GET -Token $secureBasic -AuthScheme "Basic"

    Write-AuditLog -OperationId $operationId -User $User -System "confluence" `
        -SystemVersion "cloud" -Resource "page" -Operation "GET" -Target $PageId `
        -ExecutionMechanism "rest-api" -Skill "confluence-pages" `
        -Script "get-page.ps1" -ScriptVersion $ScriptVersion `
        -Risk "READ_ONLY" -ApprovalRequired $false -ApprovalStatus "NOT_REQUIRED" `
        -Result "SUCCESS" -Verification "NOT_APPLICABLE"

    $page | ConvertTo-Json -Depth 10
    exit ([int][DevOpsExitCode]::Success)
}
catch {
    Write-AuditLog -OperationId $operationId -User $User -System "confluence" `
        -SystemVersion "cloud" -Resource "page" -Operation "GET" -Target $PageId `
        -ExecutionMechanism "rest-api" -Skill "confluence-pages" `
        -Script "get-page.ps1" -ScriptVersion $ScriptVersion `
        -Risk "READ_ONLY" -ApprovalRequired $false -ApprovalStatus "NOT_REQUIRED" `
        -Result "FAILURE" -Verification "NOT_APPLICABLE" -Error $_.Exception.Message

    Write-Error "Failed to retrieve page '$PageId': $($_.Exception.Message)"
    exit ([int][DevOpsExitCode]::GeneralFailure)
}
