#Requires -Version 7.0
<#
.SYNOPSIS
    WRITE: Updates a single Jira Cloud issue field (e.g. priority).
    Requires a pre-issued, matching "APPROVE UPDATE" approval record.

.DESCRIPTION
    Purpose: Execute the UPDATE stage for one issue field.
    Supported OS: Windows (PowerShell 7+).
    Dependencies: scripts/common/Common.psm1
    Parameters: SiteUrl, IssueKey, FieldName, FieldValueJson, Email,
        ApiToken, User, OperationId
    Authentication: Jira Cloud basic auth (email + API token).
    Required permissions: "Edit issues" Jira permission.
    Approval requirements: MANDATORY "APPROVE UPDATE" bound to this exact
        IssueKey + field.
    Dry-run: -WhatIf supported.
    API/MCP dependency: REST fallback
        (PUT /rest/api/3/issue/{issueIdOrKey}).
    Exit codes: 0 success, 6 approval denied, 7 verification failure,
        1 general failure.
    Output: JSON result.
    Verification: GET after update; confirm field value matches.
    Audit: writes one WRITE audit record.
    Security: TLS enforced; approval re-checked immediately before PUT.

.EXAMPLE
    ./update-issue-field.ps1 -SiteUrl "https://example.atlassian.net" `
        -IssueKey ABC-123 -FieldName priority -FieldValueJson '{"name":"P1"}' `
        -Email jdoe@example.com -ApiToken $token -User jdoe -OperationId op-123
#>

[CmdletBinding(SupportsShouldAction = $true)]
param(
    [Parameter(Mandatory = $true)][string]$SiteUrl,
    [Parameter(Mandatory = $true)][string]$IssueKey,
    [Parameter(Mandatory = $true)][string]$FieldName,
    [Parameter(Mandatory = $true)][string]$FieldValueJson,
    [Parameter(Mandatory = $true)][string]$Email,
    [Parameter(Mandatory = $true)][System.Security.SecureString]$ApiToken,
    [Parameter(Mandatory = $true)][string]$User,
    [Parameter(Mandatory = $true)][string]$OperationId
)

$ScriptVersion = "1.0.0"
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Import-Module (Join-Path $PSScriptRoot "../../../../../scripts/common/Common.psm1") -Force

$operationKey = "jira.issue.update"
$approval = Test-ApprovalToken -OperationId $OperationId -System "jira" `
    -Target $IssueKey -Operation $operationKey -ExpectedApprovalType "APPROVE UPDATE"

if (-not $approval.Valid) {
    Write-AuditLog -OperationId $OperationId -User $User -System "jira" `
        -SystemVersion "cloud" -Resource "issue" -Operation "UPDATE" -Target $IssueKey `
        -ExecutionMechanism "rest-api" -Skill "jira-issues" `
        -Script "update-issue-field.ps1" -ScriptVersion $ScriptVersion `
        -Risk "WRITE" -ApprovalRequired $true -ApprovalStatus "DENIED" `
        -Result "DENIED" -Verification "NOT_APPLICABLE" -Error $approval.Reason
    Write-Error "Approval check failed: $($approval.Reason)"
    exit ([int][DevOpsExitCode]::ApprovalDenied)
}

$uri = "$SiteUrl/rest/api/3/issue/$IssueKey"

try {
    $plainToken = ConvertFrom-SecureStringPlain -Secure $ApiToken
    $basic = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes("$Email`:$plainToken"))
    $plainToken = $null
    $secureBasic = ConvertTo-SecureString -String $basic -AsPlainText -Force

    $fieldValue = $FieldValueJson | ConvertFrom-Json
    $body = @{ fields = @{ $FieldName = $fieldValue } }

    if ($PSCmdlet.ShouldProcess($IssueKey, "UPDATE field '$FieldName'")) {
        Invoke-SecureRestMethod -Uri $uri -Method PUT -Token $secureBasic -AuthScheme "Basic" -Body $body | Out-Null
        Set-ApprovalConsumed -OperationId $OperationId

        $verification = "UNKNOWN"; $result = "UNKNOWN"
        try {
            $current = Invoke-SecureRestMethod -Uri $uri -Method GET -Token $secureBasic -AuthScheme "Basic"
            $currentValue = $current.fields.$FieldName | ConvertTo-Json -Compress
            $expectedValue = $fieldValue | ConvertTo-Json -Compress
            if ($currentValue -eq $expectedValue) { $verification = "CONFIRMED"; $result = "SUCCESS" }
            else { $verification = "FAILED" }
        }
        catch { $verification = "FAILED" }

        Write-AuditLog -OperationId $OperationId -User $User -System "jira" `
            -SystemVersion "cloud" -Resource "issue" -Operation "UPDATE" -Target $IssueKey `
            -ExecutionMechanism "rest-api" -Skill "jira-issues" `
            -Script "update-issue-field.ps1" -ScriptVersion $ScriptVersion `
            -Risk "WRITE" -ApprovalRequired $true -ApprovalStatus "APPROVED" `
            -Result $result -Verification $verification

        [pscustomobject]@{ operationId = $OperationId; target = $IssueKey; result = $result; verification = $verification } | ConvertTo-Json
        if ($verification -ne "CONFIRMED") { exit ([int][DevOpsExitCode]::VerificationFailure) }
        exit ([int][DevOpsExitCode]::Success)
    }
    else {
        Write-Host "(WhatIf) Would UPDATE field '$FieldName' on issue '$IssueKey'. No change made."
        exit ([int][DevOpsExitCode]::Success)
    }
}
catch {
    Write-AuditLog -OperationId $OperationId -User $User -System "jira" `
        -SystemVersion "cloud" -Resource "issue" -Operation "UPDATE" -Target $IssueKey `
        -ExecutionMechanism "rest-api" -Skill "jira-issues" `
        -Script "update-issue-field.ps1" -ScriptVersion $ScriptVersion `
        -Risk "WRITE" -ApprovalRequired $true -ApprovalStatus "APPROVED" `
        -Result "FAILURE" -Verification "UNKNOWN" -Error $_.Exception.Message
    Write-Error "Failed to update field '$FieldName' on issue '$IssueKey': $($_.Exception.Message)"
    exit ([int][DevOpsExitCode]::GeneralFailure)
}
