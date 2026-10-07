#Requires -Version 7.0
<#
.SYNOPSIS
    SECURITY_SENSITIVE: Adds a permission grant to a Jira Cloud
    permission scheme. Requires a pre-issued, matching
    "APPROVE PERMISSION CHANGE" approval record.

.DESCRIPTION
    Purpose: Execute the UPDATE stage for a permission scheme grant.
    Supported OS: Windows (PowerShell 7+).
    Dependencies: scripts/common/Common.psm1
    Parameters: SiteUrl, SchemeId, HolderType, HolderParameter,
        PermissionKey, Email, ApiToken, User, OperationId
    Authentication: Jira Cloud basic auth (email + API token).
    Required permissions: "Administer Jira" global permission (verified:
        https://developer.atlassian.com/cloud/jira/platform/rest/v3/api-group-permission-schemes/ ).
    Approval requirements: MANDATORY "APPROVE PERMISSION CHANGE" bound to
        this exact SchemeId + holder + permission combination.
    Dry-run: -WhatIf supported.
    API/MCP dependency: REST fallback
        (POST /rest/api/3/permissionscheme/{schemeId}/permission).
    Exit codes: 0 success, 6 approval denied, 7 verification failure,
        1 general failure.
    Output: JSON result.
    Verification: GET the scheme after the write; confirm a grant with
        the matching holder and permission key is present.
    Audit: writes one WRITE audit record (classified SECURITY_SENSITIVE).
    Security: TLS enforced; approval re-checked immediately before POST.
        A permission grant is a security-control change - never execute
        from a generic affirmative.

.EXAMPLE
    ./grant-permission.ps1 -SiteUrl "https://example.atlassian.net" -SchemeId 10000 `
        -HolderType group -HolderParameter "jira-administrators" -PermissionKey ADMINISTER_PROJECTS `
        -Email jdoe@example.com -ApiToken $token -User jdoe -OperationId op-123
#>

[CmdletBinding(SupportsShouldAction = $true)]
param(
    [Parameter(Mandatory = $true)][string]$SiteUrl,
    [Parameter(Mandatory = $true)][string]$SchemeId,
    [Parameter(Mandatory = $true)][ValidateSet('group', 'user', 'projectRole', 'applicationRole')]
    [string]$HolderType,
    [Parameter(Mandatory = $true)][string]$HolderParameter,
    [Parameter(Mandatory = $true)][string]$PermissionKey,
    [Parameter(Mandatory = $true)][string]$Email,
    [Parameter(Mandatory = $true)][System.Security.SecureString]$ApiToken,
    [Parameter(Mandatory = $true)][string]$User,
    [Parameter(Mandatory = $true)][string]$OperationId
)

$ScriptVersion = "1.0.0"
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Import-Module (Join-Path $PSScriptRoot "../../../../../scripts/common/Common.psm1") -Force

$operationKey = "jira.permissions.update"
$target = "$SchemeId:$HolderType:$HolderParameter:$PermissionKey"
$approval = Test-ApprovalToken -OperationId $OperationId -System "jira" `
    -Target $target -Operation $operationKey -ExpectedApprovalType "APPROVE PERMISSION CHANGE"

if (-not $approval.Valid) {
    Write-AuditLog -OperationId $OperationId -User $User -System "jira" `
        -SystemVersion "cloud" -Resource "permission_scheme" -Operation "UPDATE" -Target $target `
        -ExecutionMechanism "rest-api" -Skill "jira-permissions" `
        -Script "grant-permission.ps1" -ScriptVersion $ScriptVersion `
        -Risk "SECURITY_SENSITIVE" -ApprovalRequired $true -ApprovalStatus "DENIED" `
        -Result "DENIED" -Verification "NOT_APPLICABLE" -Error $approval.Reason
    Write-Error "Approval check failed: $($approval.Reason)"
    exit ([int][DevOpsExitCode]::ApprovalDenied)
}

$uri = "$SiteUrl/rest/api/3/permissionscheme/$SchemeId/permission"

try {
    $plainToken = ConvertFrom-SecureStringPlain -Secure $ApiToken
    $basic = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes("$Email`:$plainToken"))
    $plainToken = $null
    $secureBasic = ConvertTo-SecureString -String $basic -AsPlainText -Force

    $body = @{
        holder     = @{ type = $HolderType; parameter = $HolderParameter }
        permission = $PermissionKey
    }

    if ($PSCmdlet.ShouldProcess($target, "GRANT permission '$PermissionKey' in scheme '$SchemeId'")) {
        Invoke-SecureRestMethod -Uri $uri -Method POST -Token $secureBasic -AuthScheme "Basic" -Body $body | Out-Null
        Set-ApprovalConsumed -OperationId $OperationId

        $verification = "UNKNOWN"; $result = "UNKNOWN"
        try {
            $schemeUri = "$SiteUrl/rest/api/3/permissionscheme/$SchemeId"
            $scheme = Invoke-SecureRestMethod -Uri $schemeUri -Method GET -Token $secureBasic -AuthScheme "Basic"
            $match = $scheme.permissions | Where-Object {
                $_.holder.type -eq $HolderType -and $_.holder.parameter -eq $HolderParameter -and $_.permission -eq $PermissionKey
            }
            if ($match) { $verification = "CONFIRMED"; $result = "SUCCESS" }
            else { $verification = "FAILED" }
        }
        catch { $verification = "FAILED" }

        Write-AuditLog -OperationId $OperationId -User $User -System "jira" `
            -SystemVersion "cloud" -Resource "permission_scheme" -Operation "UPDATE" -Target $target `
            -ExecutionMechanism "rest-api" -Skill "jira-permissions" `
            -Script "grant-permission.ps1" -ScriptVersion $ScriptVersion `
            -Risk "SECURITY_SENSITIVE" -ApprovalRequired $true -ApprovalStatus "APPROVED" `
            -Result $result -Verification $verification

        [pscustomobject]@{ operationId = $OperationId; target = $target; result = $result; verification = $verification } | ConvertTo-Json
        if ($verification -ne "CONFIRMED") { exit ([int][DevOpsExitCode]::VerificationFailure) }
        exit ([int][DevOpsExitCode]::Success)
    }
    else {
        Write-Host "(WhatIf) Would GRANT permission '$PermissionKey' to '$HolderType:$HolderParameter' in scheme '$SchemeId'. No change made."
        exit ([int][DevOpsExitCode]::Success)
    }
}
catch {
    Write-AuditLog -OperationId $OperationId -User $User -System "jira" `
        -SystemVersion "cloud" -Resource "permission_scheme" -Operation "UPDATE" -Target $target `
        -ExecutionMechanism "rest-api" -Skill "jira-permissions" `
        -Script "grant-permission.ps1" -ScriptVersion $ScriptVersion `
        -Risk "SECURITY_SENSITIVE" -ApprovalRequired $true -ApprovalStatus "APPROVED" `
        -Result "FAILURE" -Verification "UNKNOWN" -Error $_.Exception.Message
    Write-Error "Failed to grant permission '$PermissionKey' in scheme '$SchemeId': $($_.Exception.Message)"
    exit ([int][DevOpsExitCode]::GeneralFailure)
}
