#Requires -Version 7.0
<#
.SYNOPSIS
    SECURITY_SENSITIVE: Assigns a role to a principal on a Confluence
    Cloud space. Requires a pre-issued, matching
    "APPROVE PERMISSION CHANGE" approval record.

.DESCRIPTION
    Purpose: Execute the WRITE stage for one space role assignment.
    Supported OS: Windows (PowerShell 7+). Dependencies: scripts/common/Common.psm1
    Parameters: SiteUrl, SpaceId, PrincipalId, PrincipalType, RoleId,
        Email, ApiToken, User, OperationId
    Authentication: Confluence Cloud basic auth (email + API token).
    Required permissions: space "admin" role.
    Approval requirements: MANDATORY "APPROVE PERMISSION CHANGE" bound
        to this exact SpaceId target.
    Dry-run: -WhatIf supported.
    API/MCP dependency: REST fallback
        (POST /wiki/api/v2/spaces/{id}/role-assignments).
    Exit codes: 0 success, 6 approval denied, 7 verification failure, 1 general failure.
    Output: JSON result.
    Verification: GET role assignments after write; confirm the
        principal+role pair appears.
    Audit: writes one SECURITY_SENSITIVE audit record.
    Security: TLS enforced; approval re-checked immediately before POST.

.EXAMPLE
    ./set-role-assignment.ps1 -SiteUrl "https://example.atlassian.net" -SpaceId 123456 `
        -PrincipalId "group-abc" -PrincipalType GROUP -RoleId "viewer-role-id" `
        -Email jdoe@example.com -ApiToken $token -User jdoe -OperationId op-123
#>

[CmdletBinding(SupportsShouldAction = $true)]
param(
    [Parameter(Mandatory = $true)][string]$SiteUrl,
    [Parameter(Mandatory = $true)][string]$SpaceId,
    [Parameter(Mandatory = $true)][string]$PrincipalId,
    [Parameter(Mandatory = $true)][string]$PrincipalType,
    [Parameter(Mandatory = $true)][string]$RoleId,
    [Parameter(Mandatory = $true)][string]$Email,
    [Parameter(Mandatory = $true)][System.Security.SecureString]$ApiToken,
    [Parameter(Mandatory = $true)][string]$User,
    [Parameter(Mandatory = $true)][string]$OperationId
)

$ScriptVersion = "1.0.0"
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Import-Module (Join-Path $PSScriptRoot "../../../../../scripts/common/Common.psm1") -Force

$operationKey = "confluence.permissions.update"
$approval = Test-ApprovalToken -OperationId $OperationId -System "confluence" `
    -Target $SpaceId -Operation $operationKey -ExpectedApprovalType "APPROVE PERMISSION CHANGE"

if (-not $approval.Valid) {
    Write-AuditLog -OperationId $OperationId -User $User -System "confluence" `
        -SystemVersion "cloud" -Resource "space_role" -Operation "UPDATE" -Target $SpaceId `
        -ExecutionMechanism "rest-api" -Skill "confluence-permissions" `
        -Script "set-role-assignment.ps1" -ScriptVersion $ScriptVersion `
        -Risk "SECURITY_SENSITIVE" -ApprovalRequired $true -ApprovalStatus "DENIED" `
        -Result "DENIED" -Verification "NOT_APPLICABLE" -Error $approval.Reason
    Write-Error "Approval check failed: $($approval.Reason)"
    exit ([int][DevOpsExitCode]::ApprovalDenied)
}

$uri = "$SiteUrl/wiki/api/v2/spaces/$SpaceId/role-assignments"

try {
    $plainToken = ConvertFrom-SecureStringPlain -Secure $ApiToken
    $basic = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes("$Email`:$plainToken"))
    $plainToken = $null
    $secureBasic = ConvertTo-SecureString -String $basic -AsPlainText -Force

    $body = @{
        principals = @(@{ id = $PrincipalId; type = $PrincipalType; roleId = $RoleId })
    }

    if ($PSCmdlet.ShouldProcess($SpaceId, "ASSIGN role '$RoleId' to $PrincipalType '$PrincipalId'")) {
        Invoke-SecureRestMethod -Uri $uri -Method POST -Token $secureBasic -AuthScheme "Basic" -Body $body | Out-Null
        Set-ApprovalConsumed -OperationId $OperationId

        $verification = "UNKNOWN"; $result = "UNKNOWN"
        try {
            $current = Invoke-SecureRestMethod -Uri $uri -Method GET -Token $secureBasic -AuthScheme "Basic"
            $match = $current.results | Where-Object { $_.principalId -eq $PrincipalId -and $_.roleId -eq $RoleId }
            if ($match) { $verification = "CONFIRMED"; $result = "SUCCESS" } else { $verification = "FAILED" }
        }
        catch { $verification = "FAILED" }

        Write-AuditLog -OperationId $OperationId -User $User -System "confluence" `
            -SystemVersion "cloud" -Resource "space_role" -Operation "UPDATE" -Target $SpaceId `
            -ExecutionMechanism "rest-api" -Skill "confluence-permissions" `
            -Script "set-role-assignment.ps1" -ScriptVersion $ScriptVersion `
            -Risk "SECURITY_SENSITIVE" -ApprovalRequired $true -ApprovalStatus "APPROVED" `
            -Result $result -Verification $verification

        [pscustomobject]@{ operationId = $OperationId; target = $SpaceId; result = $result; verification = $verification } | ConvertTo-Json
        if ($verification -ne "CONFIRMED") { exit ([int][DevOpsExitCode]::VerificationFailure) }
        exit ([int][DevOpsExitCode]::Success)
    }
    else {
        Write-Host "(WhatIf) Would ASSIGN role '$RoleId' to $PrincipalType '$PrincipalId' on space '$SpaceId'. No change made."
        exit ([int][DevOpsExitCode]::Success)
    }
}
catch {
    Write-AuditLog -OperationId $OperationId -User $User -System "confluence" `
        -SystemVersion "cloud" -Resource "space_role" -Operation "UPDATE" -Target $SpaceId `
        -ExecutionMechanism "rest-api" -Skill "confluence-permissions" `
        -Script "set-role-assignment.ps1" -ScriptVersion $ScriptVersion `
        -Risk "SECURITY_SENSITIVE" -ApprovalRequired $true -ApprovalStatus "APPROVED" `
        -Result "FAILURE" -Verification "UNKNOWN" -Error $_.Exception.Message
    Write-Error "Failed to assign role on space '$SpaceId': $($_.Exception.Message)"
    exit ([int][DevOpsExitCode]::GeneralFailure)
}
