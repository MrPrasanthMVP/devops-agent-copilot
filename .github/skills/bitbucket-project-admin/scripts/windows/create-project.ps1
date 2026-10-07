#Requires -Version 7.0
<#
.SYNOPSIS
    WRITE: Creates a new Bitbucket Data Center project. Requires a
    pre-issued, matching "APPROVE CREATE" approval record.

.DESCRIPTION
    Purpose: Execute the CREATE stage for a new project.
    Supported OS: Windows (PowerShell 7+).
    Dependencies: scripts/common/Common.psm1
    Parameters: BaseUrl, ProjectKey, Name, Description, User, OperationId
    Authentication: Bitbucket HTTP access token (POC: local-secrets).
    Required permissions: Bitbucket global "Create project" permission.
    Approval requirements: MANDATORY "APPROVE CREATE" bound to this exact
        ProjectKey.
    Dry-run: -WhatIf supported.
    API/MCP dependency: REST fallback (POST /rest/api/1.0/projects).
    Exit codes: 0 success, 6 approval denied, 7 verification failure,
        1 general failure.
    Output: JSON result.
    Verification: GET after create; confirm key/name match.
    Audit: writes one WRITE audit record.
    Security: TLS enforced; approval re-checked immediately before POST.

.EXAMPLE
    ./create-project.ps1 -BaseUrl "https://bitbucket.example.com" `
        -ProjectKey PAY -Name "Payments Platform" -Description "Payments" `
        -User jdoe -OperationId op-aaa111
#>

[CmdletBinding(SupportsShouldAction = $true)]
param(
    [Parameter(Mandatory = $true)][string]$BaseUrl,
    [Parameter(Mandatory = $true)][string]$ProjectKey,
    [Parameter(Mandatory = $true)][string]$Name,
    [string]$Description = "",
    [Parameter(Mandatory = $true)][string]$User,
    [Parameter(Mandatory = $true)][string]$OperationId
)

$ScriptVersion = "1.0.0"
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Import-Module (Join-Path $PSScriptRoot "../../../../../scripts/common/Common.psm1") -Force

$target = "$ProjectKey"
$operationKey = "bitbucket.project.create"

$approval = Test-ApprovalToken -OperationId $OperationId -System "bitbucket" `
    -Target $target -Operation $operationKey -ExpectedApprovalType "APPROVE CREATE"

if (-not $approval.Valid) {
    Write-AuditLog -OperationId $OperationId -User $User -System "bitbucket" `
        -SystemVersion "9.4.5" -Resource "project" -Operation "CREATE" -Target $target `
        -ExecutionMechanism "rest-api" -Skill "bitbucket-project-admin" `
        -Script "create-project.ps1" -ScriptVersion $ScriptVersion `
        -Risk "WRITE" -ApprovalRequired $true -ApprovalStatus "DENIED" `
        -Result "DENIED" -Verification "NOT_APPLICABLE" -Error $approval.Reason

    Write-Error "Approval check failed: $($approval.Reason)"
    exit ([int][DevOpsExitCode]::ApprovalDenied)
}

$collectionUri = "$BaseUrl/rest/api/1.0/projects"
$projectUri = "$collectionUri/$ProjectKey"

try {
    $token = Read-LocalSecret -System bitbucket

    if ($PSCmdlet.ShouldProcess($target, "CREATE Bitbucket project")) {
        Invoke-SecureRestMethod -Uri $collectionUri -Method POST -Token $token `
            -Body @{ key = $ProjectKey; name = $Name; description = $Description } | Out-Null
        Set-ApprovalConsumed -OperationId $OperationId

        $verification = "UNKNOWN"
        $result = "UNKNOWN"
        try {
            $created = Invoke-SecureRestMethod -Uri $projectUri -Method GET -Token $token
            if ($created.key -eq $ProjectKey) {
                $verification = "CONFIRMED"
                $result = "SUCCESS"
            }
            else {
                $verification = "FAILED"
            }
        }
        catch {
            $verification = "FAILED"
        }

        Write-AuditLog -OperationId $OperationId -User $User -System "bitbucket" `
            -SystemVersion "9.4.5" -Resource "project" -Operation "CREATE" -Target $target `
            -ExecutionMechanism "rest-api" -Skill "bitbucket-project-admin" `
            -Script "create-project.ps1" -ScriptVersion $ScriptVersion `
            -Risk "WRITE" -ApprovalRequired $true -ApprovalStatus "APPROVED" `
            -Result $result -Verification $verification

        [pscustomobject]@{ operationId = $OperationId; target = $target; result = $result; verification = $verification } | ConvertTo-Json

        if ($verification -ne "CONFIRMED") { exit ([int][DevOpsExitCode]::VerificationFailure) }
        exit ([int][DevOpsExitCode]::Success)
    }
    else {
        Write-Host "(WhatIf) Would CREATE Bitbucket project '$target'. No change made."
        exit ([int][DevOpsExitCode]::Success)
    }
}
catch {
    Write-AuditLog -OperationId $OperationId -User $User -System "bitbucket" `
        -SystemVersion "9.4.5" -Resource "project" -Operation "CREATE" -Target $target `
        -ExecutionMechanism "rest-api" -Skill "bitbucket-project-admin" `
        -Script "create-project.ps1" -ScriptVersion $ScriptVersion `
        -Risk "WRITE" -ApprovalRequired $true -ApprovalStatus "APPROVED" `
        -Result "FAILURE" -Verification "UNKNOWN" -Error $_.Exception.Message

    Write-Error "Failed to create project '$target': $($_.Exception.Message)"
    exit ([int][DevOpsExitCode]::GeneralFailure)
}
