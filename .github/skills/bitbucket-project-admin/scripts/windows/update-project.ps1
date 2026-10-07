#Requires -Version 7.0
<#
.SYNOPSIS
    WRITE: Updates a Bitbucket Data Center project's name/description.
    Requires a pre-issued, matching "APPROVE UPDATE" approval record.

.DESCRIPTION
    Purpose: Execute the UPDATE stage for an existing project.
    Supported OS: Windows (PowerShell 7+).
    Dependencies: scripts/common/Common.psm1
    Parameters: BaseUrl, ProjectKey, Name, Description, User, OperationId
    Authentication: Bitbucket HTTP access token (POC: local-secrets).
    Required permissions: Bitbucket project admin permission.
    Approval requirements: MANDATORY "APPROVE UPDATE".
    Dry-run: -WhatIf supported.
    API/MCP dependency: REST fallback (PUT /rest/api/1.0/projects/{projectKey}).
    Exit codes: 0 success, 6 approval denied, 7 verification failure,
        1 general failure.
    Output: JSON result.
    Verification: GET after update; confirm name/description match.
    Audit: writes one WRITE audit record.
    Security: TLS enforced; approval re-checked immediately before PUT.

.EXAMPLE
    ./update-project.ps1 -BaseUrl "https://bitbucket.example.com" `
        -ProjectKey PAY -Name "Payments Platform v2" -User jdoe -OperationId op-123
#>

[CmdletBinding(SupportsShouldAction = $true)]
param(
    [Parameter(Mandatory = $true)][string]$BaseUrl,
    [Parameter(Mandatory = $true)][string]$ProjectKey,
    [string]$Name = $null,
    [string]$Description = $null,
    [Parameter(Mandatory = $true)][string]$User,
    [Parameter(Mandatory = $true)][string]$OperationId
)

$ScriptVersion = "1.0.0"
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Import-Module (Join-Path $PSScriptRoot "../../../../../scripts/common/Common.psm1") -Force

$target = "$ProjectKey"
$operationKey = "bitbucket.project.update"

$approval = Test-ApprovalToken -OperationId $OperationId -System "bitbucket" `
    -Target $target -Operation $operationKey -ExpectedApprovalType "APPROVE UPDATE"

if (-not $approval.Valid) {
    Write-AuditLog -OperationId $OperationId -User $User -System "bitbucket" `
        -SystemVersion "9.4.5" -Resource "project" -Operation "UPDATE" -Target $target `
        -ExecutionMechanism "rest-api" -Skill "bitbucket-project-admin" `
        -Script "update-project.ps1" -ScriptVersion $ScriptVersion `
        -Risk "WRITE" -ApprovalRequired $true -ApprovalStatus "DENIED" `
        -Result "DENIED" -Verification "NOT_APPLICABLE" -Error $approval.Reason

    Write-Error "Approval check failed: $($approval.Reason)"
    exit ([int][DevOpsExitCode]::ApprovalDenied)
}

$uri = "$BaseUrl/rest/api/1.0/projects/$ProjectKey"
$body = @{}
if ($Name) { $body["name"] = $Name }
if ($null -ne $Description) { $body["description"] = $Description }

try {
    $token = Read-LocalSecret -System bitbucket

    if ($PSCmdlet.ShouldProcess($target, "UPDATE Bitbucket project")) {
        Invoke-SecureRestMethod -Uri $uri -Method PUT -Token $token -Body $body | Out-Null
        Set-ApprovalConsumed -OperationId $OperationId

        $verification = "UNKNOWN"
        $result = "UNKNOWN"
        try {
            $current = Invoke-SecureRestMethod -Uri $uri -Method GET -Token $token
            $nameOk = (-not $Name) -or ($current.name -eq $Name)
            $descOk = ($null -eq $Description) -or ($current.description -eq $Description)
            if ($nameOk -and $descOk) { $verification = "CONFIRMED"; $result = "SUCCESS" }
            else { $verification = "FAILED" }
        }
        catch { $verification = "FAILED" }

        Write-AuditLog -OperationId $OperationId -User $User -System "bitbucket" `
            -SystemVersion "9.4.5" -Resource "project" -Operation "UPDATE" -Target $target `
            -ExecutionMechanism "rest-api" -Skill "bitbucket-project-admin" `
            -Script "update-project.ps1" -ScriptVersion $ScriptVersion `
            -Risk "WRITE" -ApprovalRequired $true -ApprovalStatus "APPROVED" `
            -Result $result -Verification $verification

        [pscustomobject]@{ operationId = $OperationId; target = $target; result = $result; verification = $verification } | ConvertTo-Json

        if ($verification -ne "CONFIRMED") { exit ([int][DevOpsExitCode]::VerificationFailure) }
        exit ([int][DevOpsExitCode]::Success)
    }
    else {
        Write-Host "(WhatIf) Would UPDATE Bitbucket project '$target'. No change made."
        exit ([int][DevOpsExitCode]::Success)
    }
}
catch {
    Write-AuditLog -OperationId $OperationId -User $User -System "bitbucket" `
        -SystemVersion "9.4.5" -Resource "project" -Operation "UPDATE" -Target $target `
        -ExecutionMechanism "rest-api" -Skill "bitbucket-project-admin" `
        -Script "update-project.ps1" -ScriptVersion $ScriptVersion `
        -Risk "WRITE" -ApprovalRequired $true -ApprovalStatus "APPROVED" `
        -Result "FAILURE" -Verification "UNKNOWN" -Error $_.Exception.Message

    Write-Error "Failed to update project '$target': $($_.Exception.Message)"
    exit ([int][DevOpsExitCode]::GeneralFailure)
}
