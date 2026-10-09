#Requires -Version 7.0
<#
.SYNOPSIS
    WRITE: Creates a new SonarQube project. Requires a pre-issued,
    matching "APPROVE CREATE" approval record.

.DESCRIPTION
    Purpose: Execute the CREATE stage for a new project.
    Supported OS: Windows (PowerShell 7+).
    Dependencies: scripts/common/Common.psm1
    Parameters: BaseUrl, ProjectKey, ProjectName, Organization (optional,
        Cloud only), Visibility (optional), User, OperationId
    Authentication: SonarQube user token (POC: local-secrets).
    Required permissions: 'Create Projects' permission.
    Approval requirements: MANDATORY "APPROVE CREATE" bound to this exact
        ProjectKey.
    Dry-run: -WhatIf supported.
    Deployment: works against BOTH Server and Cloud (pass -Organization for Cloud).
    API/MCP dependency: REST fallback (POST api/projects/create).
    Exit codes: 0 success, 6 approval denied, 7 verification failure,
        1 general failure.
    Output: JSON result.
    Verification: search-after-create; confirm the project key is present.
    Audit: writes one WRITE audit record.
    Security: TLS enforced; approval re-checked immediately before POST.

.EXAMPLE
    ./create-project.ps1 -BaseUrl "https://sonarqube.example.internal" `
        -ProjectKey my-app -ProjectName "My App" -User jdoe -OperationId op-aaa111
#>

[CmdletBinding(SupportsShouldAction = $true)]
param(
    [Parameter(Mandatory = $true)][string]$BaseUrl,
    [Parameter(Mandatory = $true)][string]$ProjectKey,
    [Parameter(Mandatory = $true)][string]$ProjectName,
    [string]$Organization = $null,
    [ValidateSet('public', 'private')][string]$Visibility = $null,
    [Parameter(Mandatory = $true)][string]$User,
    [Parameter(Mandatory = $true)][string]$OperationId
)

$ScriptVersion = "1.0.0"
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Import-Module (Join-Path $PSScriptRoot "../../../../../scripts/common/Common.psm1") -Force

$target = $ProjectKey
$operationKey = "sonarqube.project.create"

$approval = Test-ApprovalToken -OperationId $OperationId -System "sonarqube" `
    -Target $target -Operation $operationKey -ExpectedApprovalType "APPROVE CREATE"

if (-not $approval.Valid) {
    Write-AuditLog -OperationId $OperationId -User $User -System "sonarqube" `
        -SystemVersion "runtime-detected" -Resource "project" -Operation "CREATE" -Target $target `
        -ExecutionMechanism "rest-api" -Skill "sonarqube-projects" `
        -Script "create-project.ps1" -ScriptVersion $ScriptVersion `
        -Risk "WRITE" -ApprovalRequired $true -ApprovalStatus "DENIED" `
        -Result "DENIED" -Verification "NOT_APPLICABLE" -Error $approval.Reason

    Write-Error "Approval check failed: $($approval.Reason)"
    exit ([int][DevOpsExitCode]::ApprovalDenied)
}

$createUri = "$BaseUrl/api/projects/create"
$searchUri = "$BaseUrl/api/projects/search?projects=$ProjectKey"
if ($Organization) {
    $createUri += "?organization=$Organization"
    $searchUri += "&organization=$Organization"
}

try {
    $token = Read-LocalSecret -System sonarqube

    if ($PSCmdlet.ShouldProcess($target, "CREATE SonarQube project")) {
        $body = @{ project = $ProjectKey; name = $ProjectName }
        if ($Visibility) { $body["visibility"] = $Visibility }

        Invoke-SecureRestMethod -Uri $createUri -Method POST -Token $token -Body $body -BodyEncoding Form | Out-Null
        Set-ApprovalConsumed -OperationId $OperationId

        $verification = "UNKNOWN"
        $result = "UNKNOWN"
        try {
            $found = Invoke-SecureRestMethod -Uri $searchUri -Method GET -Token $token
            if ($found.components -and $found.components.Count -gt 0) {
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

        Write-AuditLog -OperationId $OperationId -User $User -System "sonarqube" `
            -SystemVersion "runtime-detected" -Resource "project" -Operation "CREATE" -Target $target `
            -ExecutionMechanism "rest-api" -Skill "sonarqube-projects" `
            -Script "create-project.ps1" -ScriptVersion $ScriptVersion `
            -Risk "WRITE" -ApprovalRequired $true -ApprovalStatus "APPROVED" `
            -Result $result -Verification $verification

        [pscustomobject]@{ operationId = $OperationId; target = $target; result = $result; verification = $verification } | ConvertTo-Json

        if ($verification -ne "CONFIRMED") { exit ([int][DevOpsExitCode]::VerificationFailure) }
        exit ([int][DevOpsExitCode]::Success)
    }
    else {
        Write-Host "(WhatIf) Would CREATE SonarQube project '$target'. No change made."
        exit ([int][DevOpsExitCode]::Success)
    }
}
catch {
    Write-AuditLog -OperationId $OperationId -User $User -System "sonarqube" `
        -SystemVersion "runtime-detected" -Resource "project" -Operation "CREATE" -Target $target `
        -ExecutionMechanism "rest-api" -Skill "sonarqube-projects" `
        -Script "create-project.ps1" -ScriptVersion $ScriptVersion `
        -Risk "WRITE" -ApprovalRequired $true -ApprovalStatus "APPROVED" `
        -Result "FAILURE" -Verification "UNKNOWN" -Error $_.Exception.Message

    Write-Error "Failed to create project '$target': $($_.Exception.Message)"
    exit ([int][DevOpsExitCode]::GeneralFailure)
}
