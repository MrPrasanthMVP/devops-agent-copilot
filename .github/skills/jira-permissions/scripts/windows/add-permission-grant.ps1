#Requires -Version 7.0
<#
.SYNOPSIS
    SECURITY_SENSITIVE: Adds a permission grant to a Jira Cloud
    permission scheme. Requires a pre-issued, matching
    "APPROVE PERMISSION CHANGE" approval record.

.DESCRIPTION
    Purpose: Execute the WRITE stage for adding one permission grant.
    Supported OS: Windows (PowerShell 7+). Dependencies: scripts/common/Common.psm1
    Parameters: SiteUrl, SchemeId, PermissionKey, HolderType, HolderParameter,
        Email, ApiToken, User, OperationId
        (HolderType e.g. "group"; HolderParameter e.g. the group name)
    Authentication: Jira Cloud basic auth (email + API token).
    Required permissions: "Administer Jira" global permission.
    Approval requirements: MANDATORY "APPROVE PERMISSION CHANGE" bound
        to this exact SchemeId target.
    Dry-run: -WhatIf supported.
    API/MCP dependency: REST fallback
        (POST /rest/api/3/permissionscheme/{schemeId}/permission).
    Exit codes: 0 success, 6 approval denied, 7 verification failure, 1 general failure.
    Output: JSON result.
    Verification: GET the scheme after write; confirm the new grant
        (holder type/parameter + permission key) appears in permissions[].
    Audit: writes one SECURITY_SENSITIVE audit record.
    Security: TLS enforced; approval re-checked immediately before POST.

.EXAMPLE
    ./add-permission-grant.ps1 -SiteUrl "https://example.atlassian.net" -SchemeId 10000 `
        -PermissionKey "ADMINISTER_PROJECTS" -HolderType group -HolderParameter "platform-eng" `
        -Email jdoe@example.com -ApiToken $token -User jdoe -OperationId op-123
#>

[CmdletBinding(SupportsShouldAction = $true)]
param(
    [Parameter(Mandatory = $true)][string]$SiteUrl,
    [Parameter(Mandatory = $true)][string]$SchemeId,
    [Parameter(Mandatory = $true)][string]$PermissionKey,
    [Parameter(Mandatory = $true)][string]$HolderType,
    [Parameter(Mandatory = $true)][string]$HolderParameter,
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
$approval = Test-ApprovalToken -OperationId $OperationId -System "jira" `
    -Target $SchemeId -Operation $operationKey -ExpectedApprovalType "APPROVE PERMISSION CHANGE"

if (-not $approval.Valid) {
    Write-AuditLog -OperationId $OperationId -User $User -System "jira" `
        -SystemVersion "cloud" -Resource "permission_scheme" -Operation "UPDATE" -Target $SchemeId `
        -ExecutionMechanism "rest-api" -Skill "jira-permissions" `
        -Script "add-permission-grant.ps1" -ScriptVersion $ScriptVersion `
        -Risk "SECURITY_SENSITIVE" -ApprovalRequired $true -ApprovalStatus "DENIED" `
        -Result "DENIED" -Verification "NOT_APPLICABLE" -Error $approval.Reason
    Write-Error "Approval check failed: $($approval.Reason)"
    exit ([int][DevOpsExitCode]::ApprovalDenied)
}

$uri = "$SiteUrl/rest/api/3/permissionscheme/$SchemeId/permission"
$getUri = "$SiteUrl/rest/api/3/permissionscheme/$SchemeId"

try {
    $plainToken = ConvertFrom-SecureStringPlain -Secure $ApiToken
    $basic = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes("$Email`:$plainToken"))
    $plainToken = $null
    $secureBasic = ConvertTo-SecureString -String $basic -AsPlainText -Force

    $body = @{
        permission = $PermissionKey
        holder     = @{ type = $HolderType; parameter = $HolderParameter }
    }

    if ($PSCmdlet.ShouldProcess($SchemeId, "ADD permission grant '$PermissionKey' to $HolderType '$HolderParameter'")) {
        Invoke-SecureRestMethod -Uri $uri -Method POST -Token $secureBasic -AuthScheme "Basic" -Body $body | Out-Null
        Set-ApprovalConsumed -OperationId $OperationId

        $verification = "UNKNOWN"; $result = "UNKNOWN"
        try {
            $scheme = Invoke-SecureRestMethod -Uri $getUri -Method GET -Token $secureBasic -AuthScheme "Basic"
            $match = $scheme.permissions | Where-Object {
                $_.permission -eq $PermissionKey -and $_.holder.type -eq $HolderType -and $_.holder.parameter -eq $HolderParameter
            }
            if ($match) { $verification = "CONFIRMED"; $result = "SUCCESS" } else { $verification = "FAILED" }
        }
        catch { $verification = "FAILED" }

        Write-AuditLog -OperationId $OperationId -User $User -System "jira" `
            -SystemVersion "cloud" -Resource "permission_scheme" -Operation "UPDATE" -Target $SchemeId `
            -ExecutionMechanism "rest-api" -Skill "jira-permissions" `
            -Script "add-permission-grant.ps1" -ScriptVersion $ScriptVersion `
            -Risk "SECURITY_SENSITIVE" -ApprovalRequired $true -ApprovalStatus "APPROVED" `
            -Result $result -Verification $verification

        [pscustomobject]@{ operationId = $OperationId; target = $SchemeId; result = $result; verification = $verification } | ConvertTo-Json
        if ($verification -ne "CONFIRMED") { exit ([int][DevOpsExitCode]::VerificationFailure) }
        exit ([int][DevOpsExitCode]::Success)
    }
    else {
        Write-Host "(WhatIf) Would ADD permission grant '$PermissionKey' to $HolderType '$HolderParameter' on scheme '$SchemeId'. No change made."
        exit ([int][DevOpsExitCode]::Success)
    }
}
catch {
    Write-AuditLog -OperationId $OperationId -User $User -System "jira" `
        -SystemVersion "cloud" -Resource "permission_scheme" -Operation "UPDATE" -Target $SchemeId `
        -ExecutionMechanism "rest-api" -Skill "jira-permissions" `
        -Script "add-permission-grant.ps1" -ScriptVersion $ScriptVersion `
        -Risk "SECURITY_SENSITIVE" -ApprovalRequired $true -ApprovalStatus "APPROVED" `
        -Result "FAILURE" -Verification "UNKNOWN" -Error $_.Exception.Message
    Write-Error "Failed to add permission grant on scheme '$SchemeId': $($_.Exception.Message)"
    exit ([int][DevOpsExitCode]::GeneralFailure)
}
