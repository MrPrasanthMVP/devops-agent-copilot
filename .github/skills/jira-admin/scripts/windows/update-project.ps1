#Requires -Version 7.0
<#
.SYNOPSIS
    ADMINISTRATIVE: Updates a Jira Cloud project's lead. Requires a
    pre-issued, matching "APPROVE ADMIN CHANGE" approval record.

.DESCRIPTION
    Purpose: Execute the UPDATE stage for one project admin field.
    Supported OS: Windows (PowerShell 7+).
    Dependencies: scripts/common/Common.psm1
    Parameters: SiteUrl, ProjectKey, LeadAccountId, Email, ApiToken,
        User, OperationId
    Authentication: Jira Cloud basic auth (email + API token).
    Required permissions: "Administer projects" Jira permission.
    Approval requirements: MANDATORY "APPROVE ADMIN CHANGE".
    Dry-run: -WhatIf supported.
    API/MCP dependency: REST fallback (PUT /rest/api/3/project/{projectIdOrKey}).
    Exit codes: 0 success, 6 approval denied, 7 verification failure, 1 general failure.
    Output: JSON result.
    Verification: GET after update; confirm lead.accountId matches.
    Audit: writes one ADMINISTRATIVE audit record.
    Security: TLS enforced; approval re-checked immediately before PUT.

.EXAMPLE
    ./update-project.ps1 -SiteUrl "https://example.atlassian.net" -ProjectKey ABC `
        -LeadAccountId "5b10a2844c20165700ede21g" -Email jdoe@example.com `
        -ApiToken $token -User jdoe -OperationId op-123
#>

[CmdletBinding(SupportsShouldAction = $true)]
param(
    [Parameter(Mandatory = $true)][string]$SiteUrl,
    [Parameter(Mandatory = $true)][string]$ProjectKey,
    [Parameter(Mandatory = $true)][string]$LeadAccountId,
    [Parameter(Mandatory = $true)][string]$Email,
    [Parameter(Mandatory = $true)][System.Security.SecureString]$ApiToken,
    [Parameter(Mandatory = $true)][string]$User,
    [Parameter(Mandatory = $true)][string]$OperationId
)

$ScriptVersion = "1.0.0"
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Import-Module (Join-Path $PSScriptRoot "../../../../../scripts/common/Common.psm1") -Force

$operationKey = "jira.admin.update"
$approval = Test-ApprovalToken -OperationId $OperationId -System "jira" `
    -Target $ProjectKey -Operation $operationKey -ExpectedApprovalType "APPROVE ADMIN CHANGE"

if (-not $approval.Valid) {
    Write-AuditLog -OperationId $OperationId -User $User -System "jira" `
        -SystemVersion "cloud" -Resource "project" -Operation "UPDATE" -Target $ProjectKey `
        -ExecutionMechanism "rest-api" -Skill "jira-admin" `
        -Script "update-project.ps1" -ScriptVersion $ScriptVersion `
        -Risk "ADMINISTRATIVE" -ApprovalRequired $true -ApprovalStatus "DENIED" `
        -Result "DENIED" -Verification "NOT_APPLICABLE" -Error $approval.Reason
    Write-Error "Approval check failed: $($approval.Reason)"
    exit ([int][DevOpsExitCode]::ApprovalDenied)
}

$uri = "$SiteUrl/rest/api/3/project/$ProjectKey"

try {
    $plainToken = ConvertFrom-SecureStringPlain -Secure $ApiToken
    $basic = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes("$Email`:$plainToken"))
    $plainToken = $null
    $secureBasic = ConvertTo-SecureString -String $basic -AsPlainText -Force

    if ($PSCmdlet.ShouldProcess($ProjectKey, "UPDATE project lead")) {
        Invoke-SecureRestMethod -Uri $uri -Method PUT -Token $secureBasic -AuthScheme "Basic" `
            -Body @{ leadAccountId = $LeadAccountId } | Out-Null
        Set-ApprovalConsumed -OperationId $OperationId

        $verification = "UNKNOWN"; $result = "UNKNOWN"
        try {
            $current = Invoke-SecureRestMethod -Uri $uri -Method GET -Token $secureBasic -AuthScheme "Basic"
            if ($current.lead.accountId -eq $LeadAccountId) { $verification = "CONFIRMED"; $result = "SUCCESS" }
            else { $verification = "FAILED" }
        }
        catch { $verification = "FAILED" }

        Write-AuditLog -OperationId $OperationId -User $User -System "jira" `
            -SystemVersion "cloud" -Resource "project" -Operation "UPDATE" -Target $ProjectKey `
            -ExecutionMechanism "rest-api" -Skill "jira-admin" `
            -Script "update-project.ps1" -ScriptVersion $ScriptVersion `
            -Risk "ADMINISTRATIVE" -ApprovalRequired $true -ApprovalStatus "APPROVED" `
            -Result $result -Verification $verification

        [pscustomobject]@{ operationId = $OperationId; target = $ProjectKey; result = $result; verification = $verification } | ConvertTo-Json
        if ($verification -ne "CONFIRMED") { exit ([int][DevOpsExitCode]::VerificationFailure) }
        exit ([int][DevOpsExitCode]::Success)
    }
    else {
        Write-Host "(WhatIf) Would UPDATE project '$ProjectKey' lead to '$LeadAccountId'. No change made."
        exit ([int][DevOpsExitCode]::Success)
    }
}
catch {
    Write-AuditLog -OperationId $OperationId -User $User -System "jira" `
        -SystemVersion "cloud" -Resource "project" -Operation "UPDATE" -Target $ProjectKey `
        -ExecutionMechanism "rest-api" -Skill "jira-admin" `
        -Script "update-project.ps1" -ScriptVersion $ScriptVersion `
        -Risk "ADMINISTRATIVE" -ApprovalRequired $true -ApprovalStatus "APPROVED" `
        -Result "FAILURE" -Verification "UNKNOWN" -Error $_.Exception.Message
    Write-Error "Failed to update project '$ProjectKey': $($_.Exception.Message)"
    exit ([int][DevOpsExitCode]::GeneralFailure)
}
