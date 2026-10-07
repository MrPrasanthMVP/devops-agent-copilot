#Requires -Version 7.0
<#
.SYNOPSIS
    ADMINISTRATIVE: Creates a new Jira Cloud project. Requires a
    pre-issued, matching "APPROVE ADMIN CHANGE" approval record.

.DESCRIPTION
    Purpose: Execute the CREATE stage for a new Jira project.
    Supported OS: Windows (PowerShell 7+).
    Dependencies: scripts/common/Common.psm1
    Parameters: SiteUrl, ProjectKey, ProjectName, ProjectTypeKey,
        LeadAccountId, Email, ApiToken, User, OperationId
    Authentication: Jira Cloud basic auth (email + API token).
    Required permissions: "Administer Jira" global permission (verified:
        https://developer.atlassian.com/cloud/jira/platform/rest/v3/api-group-projects/ ,
        required fields key/name/projectTypeKey/leadAccountId confirmed
        against the same official page).
    Approval requirements: MANDATORY "APPROVE ADMIN CHANGE" bound to this
        exact ProjectKey.
    Dry-run: -WhatIf supported.
    API/MCP dependency: REST fallback (POST /rest/api/3/project).
    Exit codes: 0 success, 6 approval denied, 7 verification failure,
        1 general failure.
    Output: JSON result.
    Verification: GET the created project after the write; confirm the
        key and name match the proposal.
    Audit: writes one WRITE audit record (classified ADMINISTRATIVE).
    Security: TLS enforced; approval re-checked immediately before POST.

.EXAMPLE
    ./create-project.ps1 -SiteUrl "https://example.atlassian.net" `
        -ProjectKey NEWPRJ -ProjectName "New Project" -ProjectTypeKey business `
        -LeadAccountId "5b10a2844c20165700ede21g" -Email jdoe@example.com `
        -ApiToken $token -User jdoe -OperationId op-123
#>

[CmdletBinding(SupportsShouldAction = $true)]
param(
    [Parameter(Mandatory = $true)][string]$SiteUrl,
    [Parameter(Mandatory = $true)][string]$ProjectKey,
    [Parameter(Mandatory = $true)][string]$ProjectName,
    [Parameter(Mandatory = $true)][string]$ProjectTypeKey,
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

$operationKey = "jira.project.create"
$approval = Test-ApprovalToken -OperationId $OperationId -System "jira" `
    -Target $ProjectKey -Operation $operationKey -ExpectedApprovalType "APPROVE ADMIN CHANGE"

if (-not $approval.Valid) {
    Write-AuditLog -OperationId $OperationId -User $User -System "jira" `
        -SystemVersion "cloud" -Resource "project" -Operation "CREATE" -Target $ProjectKey `
        -ExecutionMechanism "rest-api" -Skill "jira-admin" `
        -Script "create-project.ps1" -ScriptVersion $ScriptVersion `
        -Risk "ADMINISTRATIVE" -ApprovalRequired $true -ApprovalStatus "DENIED" `
        -Result "DENIED" -Verification "NOT_APPLICABLE" -Error $approval.Reason
    Write-Error "Approval check failed: $($approval.Reason)"
    exit ([int][DevOpsExitCode]::ApprovalDenied)
}

$uri = "$SiteUrl/rest/api/3/project"

try {
    $plainToken = ConvertFrom-SecureStringPlain -Secure $ApiToken
    $basic = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes("$Email`:$plainToken"))
    $plainToken = $null
    $secureBasic = ConvertTo-SecureString -String $basic -AsPlainText -Force

    $body = @{
        key            = $ProjectKey
        name           = $ProjectName
        projectTypeKey = $ProjectTypeKey
        leadAccountId  = $LeadAccountId
    }

    if ($PSCmdlet.ShouldProcess($ProjectKey, "CREATE Jira project")) {
        $created = Invoke-SecureRestMethod -Uri $uri -Method POST -Token $secureBasic -AuthScheme "Basic" -Body $body
        Set-ApprovalConsumed -OperationId $OperationId

        $verification = "UNKNOWN"; $result = "UNKNOWN"
        try {
            $checkUri = "$SiteUrl/rest/api/3/project/$ProjectKey"
            $current = Invoke-SecureRestMethod -Uri $checkUri -Method GET -Token $secureBasic -AuthScheme "Basic"
            if ($current.key -eq $ProjectKey -and $current.name -eq $ProjectName) { $verification = "CONFIRMED"; $result = "SUCCESS" }
            else { $verification = "FAILED" }
        }
        catch { $verification = "FAILED" }

        Write-AuditLog -OperationId $OperationId -User $User -System "jira" `
            -SystemVersion "cloud" -Resource "project" -Operation "CREATE" -Target $ProjectKey `
            -ExecutionMechanism "rest-api" -Skill "jira-admin" `
            -Script "create-project.ps1" -ScriptVersion $ScriptVersion `
            -Risk "ADMINISTRATIVE" -ApprovalRequired $true -ApprovalStatus "APPROVED" `
            -Result $result -Verification $verification

        [pscustomobject]@{ operationId = $OperationId; target = $ProjectKey; result = $result; verification = $verification; created = $created } | ConvertTo-Json -Depth 10
        if ($verification -ne "CONFIRMED") { exit ([int][DevOpsExitCode]::VerificationFailure) }
        exit ([int][DevOpsExitCode]::Success)
    }
    else {
        Write-Host "(WhatIf) Would CREATE Jira project '$ProjectKey'. No change made."
        exit ([int][DevOpsExitCode]::Success)
    }
}
catch {
    Write-AuditLog -OperationId $OperationId -User $User -System "jira" `
        -SystemVersion "cloud" -Resource "project" -Operation "CREATE" -Target $ProjectKey `
        -ExecutionMechanism "rest-api" -Skill "jira-admin" `
        -Script "create-project.ps1" -ScriptVersion $ScriptVersion `
        -Risk "ADMINISTRATIVE" -ApprovalRequired $true -ApprovalStatus "APPROVED" `
        -Result "FAILURE" -Verification "UNKNOWN" -Error $_.Exception.Message
    Write-Error "Failed to create project '$ProjectKey': $($_.Exception.Message)"
    exit ([int][DevOpsExitCode]::GeneralFailure)
}
