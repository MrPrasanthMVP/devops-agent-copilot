#Requires -Version 7.0
<#
.SYNOPSIS
    ADMINISTRATIVE: Assigns the default workflow for a Jira Cloud
    workflow scheme. Requires a pre-issued, matching
    "APPROVE ADMIN CHANGE" approval record.

.DESCRIPTION
    Purpose: Execute the UPDATE stage for a workflow scheme's default
        workflow assignment.
    Supported OS: Windows (PowerShell 7+).
    Dependencies: scripts/common/Common.psm1
    Parameters: SiteUrl, SchemeId, WorkflowName, Email, ApiToken, User,
        OperationId, UpdateDraftIfNeeded (switch, default off)
    Authentication: Jira Cloud basic auth (email + API token).
    Required permissions: "Administer Jira" global permission.
    Approval requirements: MANDATORY "APPROVE ADMIN CHANGE".
    Dry-run: -WhatIf supported.
    API/MCP dependency: REST fallback
        (PUT /rest/api/3/workflowscheme/{id}/default).
    Exit codes: 0 success, 6 approval denied, 7 verification failure,
        1 general failure.
    Output: JSON result.
    Verification: GET /rest/api/3/workflowscheme/{id}/default after the
        write; confirm the returned workflow name matches.
    Audit: writes one ADMINISTRATIVE audit record.
    Security: TLS enforced; approval re-checked immediately before PUT.

    Note: active workflow schemes cannot be edited directly - Jira
    requires updateDraftIfNeeded=true to create/update a draft instead
    of the live scheme. This script defaults to false (direct edit of
    an inactive scheme) and surfaces the Jira API error untouched if the
    target scheme turns out to be active; it does not silently fall back
    to draft semantics, since publishing a draft is a separate,
    not-yet-implemented capability in this Skill.

.EXAMPLE
    ./update-default-workflow.ps1 -SiteUrl "https://example.atlassian.net" `
        -SchemeId 10001 -WorkflowName "Engineering Workflow" `
        -Email jdoe@example.com -ApiToken $token -User jdoe -OperationId op-123
#>

[CmdletBinding(SupportsShouldAction = $true)]
param(
    [Parameter(Mandatory = $true)][string]$SiteUrl,
    [Parameter(Mandatory = $true)][string]$SchemeId,
    [Parameter(Mandatory = $true)][string]$WorkflowName,
    [Parameter(Mandatory = $true)][string]$Email,
    [Parameter(Mandatory = $true)][System.Security.SecureString]$ApiToken,
    [Parameter(Mandatory = $true)][string]$User,
    [Parameter(Mandatory = $true)][string]$OperationId,
    [switch]$UpdateDraftIfNeeded
)

$ScriptVersion = "1.0.0"
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Import-Module (Join-Path $PSScriptRoot "../../../../../scripts/common/Common.psm1") -Force

$operationKey = "jira.workflow.update"
$approval = Test-ApprovalToken -OperationId $OperationId -System "jira" `
    -Target $SchemeId -Operation $operationKey -ExpectedApprovalType "APPROVE ADMIN CHANGE"

if (-not $approval.Valid) {
    Write-AuditLog -OperationId $OperationId -User $User -System "jira" `
        -SystemVersion "cloud" -Resource "workflow_scheme" -Operation "UPDATE" -Target $SchemeId `
        -ExecutionMechanism "rest-api" -Skill "jira-workflows" `
        -Script "update-default-workflow.ps1" -ScriptVersion $ScriptVersion `
        -Risk "ADMINISTRATIVE" -ApprovalRequired $true -ApprovalStatus "DENIED" `
        -Result "DENIED" -Verification "NOT_APPLICABLE" -Error $approval.Reason
    Write-Error "Approval check failed: $($approval.Reason)"
    exit ([int][DevOpsExitCode]::ApprovalDenied)
}

$uri = "$SiteUrl/rest/api/3/workflowscheme/$SchemeId/default"

try {
    $plainToken = ConvertFrom-SecureStringPlain -Secure $ApiToken
    $basic = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes("$Email`:$plainToken"))
    $plainToken = $null
    $secureBasic = ConvertTo-SecureString -String $basic -AsPlainText -Force

    $body = @{ workflow = $WorkflowName; updateDraftIfNeeded = [bool]$UpdateDraftIfNeeded }

    if ($PSCmdlet.ShouldProcess($SchemeId, "SET default workflow to '$WorkflowName'")) {
        Invoke-SecureRestMethod -Uri $uri -Method PUT -Token $secureBasic -AuthScheme "Basic" -Body $body | Out-Null
        Set-ApprovalConsumed -OperationId $OperationId

        $verification = "UNKNOWN"; $result = "UNKNOWN"
        try {
            $current = Invoke-SecureRestMethod -Uri $uri -Method GET -Token $secureBasic -AuthScheme "Basic"
            if ($current.workflow -eq $WorkflowName) { $verification = "CONFIRMED"; $result = "SUCCESS" }
            else { $verification = "FAILED" }
        }
        catch { $verification = "FAILED" }

        Write-AuditLog -OperationId $OperationId -User $User -System "jira" `
            -SystemVersion "cloud" -Resource "workflow_scheme" -Operation "UPDATE" -Target $SchemeId `
            -ExecutionMechanism "rest-api" -Skill "jira-workflows" `
            -Script "update-default-workflow.ps1" -ScriptVersion $ScriptVersion `
            -Risk "ADMINISTRATIVE" -ApprovalRequired $true -ApprovalStatus "APPROVED" `
            -Result $result -Verification $verification

        [pscustomobject]@{ operationId = $OperationId; target = $SchemeId; result = $result; verification = $verification } | ConvertTo-Json
        if ($verification -ne "CONFIRMED") { exit ([int][DevOpsExitCode]::VerificationFailure) }
        exit ([int][DevOpsExitCode]::Success)
    }
    else {
        Write-Host "(WhatIf) Would SET default workflow for scheme '$SchemeId' to '$WorkflowName'. No change made."
        exit ([int][DevOpsExitCode]::Success)
    }
}
catch {
    Write-AuditLog -OperationId $OperationId -User $User -System "jira" `
        -SystemVersion "cloud" -Resource "workflow_scheme" -Operation "UPDATE" -Target $SchemeId `
        -ExecutionMechanism "rest-api" -Skill "jira-workflows" `
        -Script "update-default-workflow.ps1" -ScriptVersion $ScriptVersion `
        -Risk "ADMINISTRATIVE" -ApprovalRequired $true -ApprovalStatus "APPROVED" `
        -Result "FAILURE" -Verification "UNKNOWN" -Error $_.Exception.Message
    Write-Error "Failed to set default workflow for scheme '$SchemeId': $($_.Exception.Message)"
    exit ([int][DevOpsExitCode]::GeneralFailure)
}
