#Requires -Version 7.0
<#
.SYNOPSIS
    DESTRUCTIVE: Permanently deletes a SonarQube project. Requires a
    pre-issued, matching "APPROVE DELETE" approval record.

.DESCRIPTION
    Purpose: Execute the DELETE stage for a project, including all its
        analyses, issues, and history.
    Supported OS: Windows (PowerShell 7+).
    Dependencies: scripts/common/Common.psm1
    Parameters: BaseUrl, ProjectKey, Organization (optional, Cloud only), User, OperationId
    Authentication: SonarQube user token (POC: local-secrets).
    Required permissions: 'Administer System' or project 'Administer' permission.
    Approval requirements: MANDATORY "APPROVE DELETE" bound to this exact ProjectKey.
    Dry-run: -WhatIf supported.
    Deployment: works against BOTH Server and Cloud (pass -Organization for Cloud).
    API/MCP dependency: REST fallback (POST api/projects/delete).
    Exit codes: 0 success, 6 approval denied, 7 verification failure, 1 general failure.
    Output: JSON result.
    Verification: search-after-delete; expect the project key absent from
        results (SonarQube has no single-object GET to check for 404 on,
        so absence-from-search is the verification signal).
    Audit: writes one DESTRUCTIVE audit record.
    Security: TLS enforced; approval re-checked immediately before DELETE.

.EXAMPLE
    ./delete-project.ps1 -BaseUrl "https://sonarqube.example.internal" `
        -ProjectKey my-app -User jdoe -OperationId op-aaa111
#>

[CmdletBinding(SupportsShouldAction = $true)]
param(
    [Parameter(Mandatory = $true)][string]$BaseUrl,
    [Parameter(Mandatory = $true)][string]$ProjectKey,
    [string]$Organization = $null,
    [Parameter(Mandatory = $true)][string]$User,
    [Parameter(Mandatory = $true)][string]$OperationId
)

$ScriptVersion = "1.0.0"
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Import-Module (Join-Path $PSScriptRoot "../../../../../scripts/common/Common.psm1") -Force

if ($ProjectKey -notmatch '^[A-Za-z0-9_.:-]+$') {
    Write-Error "Invalid project key."
    exit ([int][DevOpsExitCode]::InvalidParameters)
}

$target = $ProjectKey
$operationKey = "sonarqube.project.delete"

$approval = Test-ApprovalToken -OperationId $OperationId -System "sonarqube" `
    -Target $target -Operation $operationKey -ExpectedApprovalType "APPROVE DELETE"

if (-not $approval.Valid) {
    Write-AuditLog -OperationId $OperationId -User $User -System "sonarqube" `
        -SystemVersion "runtime-detected" -Resource "project" -Operation "DELETE" -Target $target `
        -ExecutionMechanism "rest-api" -Skill "sonarqube-projects" `
        -Script "delete-project.ps1" -ScriptVersion $ScriptVersion `
        -Risk "DESTRUCTIVE" -ApprovalRequired $true -ApprovalStatus "DENIED" `
        -Result "DENIED" -Verification "NOT_APPLICABLE" -Error $approval.Reason

    Write-Error "Approval check failed: $($approval.Reason)"
    exit ([int][DevOpsExitCode]::ApprovalDenied)
}

$deleteUri = "$BaseUrl/api/projects/delete"
$searchUri = "$BaseUrl/api/projects/search?projects=$ProjectKey"
if ($Organization) {
    $deleteUri += "?organization=$Organization"
    $searchUri += "&organization=$Organization"
}

try {
    $token = Read-LocalSecret -System sonarqube

    if ($PSCmdlet.ShouldProcess($target, "DELETE SonarQube project")) {
        Invoke-SecureRestMethod -Uri $deleteUri -Method POST -Token $token -Body @{ project = $ProjectKey } -BodyEncoding Form | Out-Null
        Set-ApprovalConsumed -OperationId $OperationId

        $verification = "UNKNOWN"
        $result = "UNKNOWN"
        try {
            $found = Invoke-SecureRestMethod -Uri $searchUri -Method GET -Token $token
            if (-not $found.components -or $found.components.Count -eq 0) {
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
            -SystemVersion "runtime-detected" -Resource "project" -Operation "DELETE" -Target $target `
            -ExecutionMechanism "rest-api" -Skill "sonarqube-projects" `
            -Script "delete-project.ps1" -ScriptVersion $ScriptVersion `
            -Risk "DESTRUCTIVE" -ApprovalRequired $true -ApprovalStatus "APPROVED" `
            -Result $result -Verification $verification

        [pscustomobject]@{ operationId = $OperationId; target = $target; result = $result; verification = $verification } | ConvertTo-Json

        if ($verification -ne "CONFIRMED") { exit ([int][DevOpsExitCode]::VerificationFailure) }
        exit ([int][DevOpsExitCode]::Success)
    }
    else {
        Write-Host "(WhatIf) Would DELETE SonarQube project '$target'. No change made."
        exit ([int][DevOpsExitCode]::Success)
    }
}
catch {
    Write-AuditLog -OperationId $OperationId -User $User -System "sonarqube" `
        -SystemVersion "runtime-detected" -Resource "project" -Operation "DELETE" -Target $target `
        -ExecutionMechanism "rest-api" -Skill "sonarqube-projects" `
        -Script "delete-project.ps1" -ScriptVersion $ScriptVersion `
        -Risk "DESTRUCTIVE" -ApprovalRequired $true -ApprovalStatus "APPROVED" `
        -Result "FAILURE" -Verification "UNKNOWN" -Error $_.Exception.Message

    Write-Error "Failed to delete project '$target': $($_.Exception.Message)"
    exit ([int][DevOpsExitCode]::GeneralFailure)
}
