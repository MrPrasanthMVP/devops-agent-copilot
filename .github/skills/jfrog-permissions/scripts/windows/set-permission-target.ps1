#Requires -Version 7.0
<#
.SYNOPSIS
    SECURITY_SENSITIVE: Creates or replaces a JFrog permission target.
    Requires a pre-issued "APPROVE PERMISSION CHANGE" approval record.

.DESCRIPTION
    Purpose: Execute the create/replace stage for a permission target.
    Supported OS: Windows (PowerShell 7+).
    Dependencies: scripts/common/Common.psm1
    Parameters: BaseUrl, PermissionTargetName, BodyJson (full permission
        target JSON body - repositories, includes/excludes, principals),
        User, OperationId
    Authentication: JFrog access token (POC: local-secrets).
    Required permissions: Artifactory admin permission.
    Approval requirements: MANDATORY "APPROVE PERMISSION CHANGE" bound to
        this exact PermissionTargetName.
    Dry-run: -WhatIf supported.
    API/MCP dependency: REST fallback
        (POST /artifactory/api/v2/security/permissions/{name}).
    Exit codes: 0 success, 6 approval denied, 7 verification failure, 1 general failure.
    Output: JSON result.
    Verification: GET after POST; confirm returned principals/repositories
        match the submitted body.
    Audit: writes one SECURITY_SENSITIVE audit record.
    Security: TLS enforced; approval re-checked immediately before POST;
        principal names are never derived from untrusted retrieved content.

.EXAMPLE
    ./set-permission-target.ps1 -BaseUrl "https://jfrog.example.com" `
        -PermissionTargetName releases-local-perm `
        -BodyJson '{"name":"releases-local-perm","repo":{"repositories":["releases-local"],"actions":{"groups":{"team-platform":["read","deploy"]}}}}' `
        -User jdoe -OperationId op-123
#>

[CmdletBinding(SupportsShouldAction = $true)]
param(
    [Parameter(Mandatory = $true)][string]$BaseUrl,
    [Parameter(Mandatory = $true)][string]$PermissionTargetName,
    [Parameter(Mandatory = $true)][string]$BodyJson,
    [Parameter(Mandatory = $true)][string]$User,
    [Parameter(Mandatory = $true)][string]$OperationId
)

$ScriptVersion = "1.0.0"
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Import-Module (Join-Path $PSScriptRoot "../../../../../scripts/common/Common.psm1") -Force

$operationKey = "jfrog.permissions.update"
$approval = Test-ApprovalToken -OperationId $OperationId -System "jfrog" `
    -Target $PermissionTargetName -Operation $operationKey -ExpectedApprovalType "APPROVE PERMISSION CHANGE"

if (-not $approval.Valid) {
    Write-AuditLog -OperationId $OperationId -User $User -System "jfrog" `
        -SystemVersion "runtime-detected" -Resource "permission_target" -Operation "UPDATE" -Target $PermissionTargetName `
        -ExecutionMechanism "rest-api" -Skill "jfrog-permissions" `
        -Script "set-permission-target.ps1" -ScriptVersion $ScriptVersion `
        -Risk "SECURITY_SENSITIVE" -ApprovalRequired $true -ApprovalStatus "DENIED" `
        -Result "DENIED" -Verification "NOT_APPLICABLE" -Error $approval.Reason
    Write-Error "Approval check failed: $($approval.Reason)"
    exit ([int][DevOpsExitCode]::ApprovalDenied)
}

$uri = "$BaseUrl/artifactory/api/v2/security/permissions/$PermissionTargetName"

try {
    $token = Read-LocalSecret -System jfrog
    $body = $BodyJson | ConvertFrom-Json

    if ($PSCmdlet.ShouldProcess($PermissionTargetName, "SET permission target")) {
        Invoke-SecureRestMethod -Uri $uri -Method POST -Token $token -Body $body | Out-Null
        Set-ApprovalConsumed -OperationId $OperationId

        $verification = "UNKNOWN"; $result = "UNKNOWN"
        try {
            $current = Invoke-SecureRestMethod -Uri $uri -Method GET -Token $token
            $currentJson = $current | ConvertTo-Json -Compress -Depth 10
            $expectedJson = $body | ConvertTo-Json -Compress -Depth 10
            if ($currentJson -eq $expectedJson) { $verification = "CONFIRMED"; $result = "SUCCESS" }
            else { $verification = "FAILED" }
        }
        catch { $verification = "FAILED" }

        Write-AuditLog -OperationId $OperationId -User $User -System "jfrog" `
            -SystemVersion "runtime-detected" -Resource "permission_target" -Operation "UPDATE" -Target $PermissionTargetName `
            -ExecutionMechanism "rest-api" -Skill "jfrog-permissions" `
            -Script "set-permission-target.ps1" -ScriptVersion $ScriptVersion `
            -Risk "SECURITY_SENSITIVE" -ApprovalRequired $true -ApprovalStatus "APPROVED" `
            -Result $result -Verification $verification

        [pscustomobject]@{ operationId = $OperationId; target = $PermissionTargetName; result = $result; verification = $verification } | ConvertTo-Json
        if ($verification -ne "CONFIRMED") { exit ([int][DevOpsExitCode]::VerificationFailure) }
        exit ([int][DevOpsExitCode]::Success)
    }
    else {
        Write-Host "(WhatIf) Would SET permission target '$PermissionTargetName'. No change made."
        exit ([int][DevOpsExitCode]::Success)
    }
}
catch {
    Write-AuditLog -OperationId $OperationId -User $User -System "jfrog" `
        -SystemVersion "runtime-detected" -Resource "permission_target" -Operation "UPDATE" -Target $PermissionTargetName `
        -ExecutionMechanism "rest-api" -Skill "jfrog-permissions" `
        -Script "set-permission-target.ps1" -ScriptVersion $ScriptVersion `
        -Risk "SECURITY_SENSITIVE" -ApprovalRequired $true -ApprovalStatus "APPROVED" `
        -Result "FAILURE" -Verification "UNKNOWN" -Error $_.Exception.Message
    Write-Error "Failed to set permission target '$PermissionTargetName': $($_.Exception.Message)"
    exit ([int][DevOpsExitCode]::GeneralFailure)
}
