#Requires -Version 7.0
<#
.SYNOPSIS
    WRITE: Associates a SonarQube project with a quality gate. Requires
    a pre-issued, matching "APPROVE UPDATE" approval record.

.DESCRIPTION
    Purpose: Execute the SELECT stage, binding a project to a named
        quality gate (future analyses are evaluated against it).
    Supported OS: Windows (PowerShell 7+).
    Dependencies: scripts/common/Common.psm1
    Parameters: BaseUrl, ProjectKey, GateName, Organization (optional,
        Cloud only), User, OperationId
    Authentication: SonarQube user token (POC: local-secrets).
    Required permissions: 'Administer Quality Gates' permission.
    Approval requirements: MANDATORY "APPROVE UPDATE" bound to this exact ProjectKey.
    Dry-run: -WhatIf supported.
    Deployment: works against BOTH Server and Cloud (pass -Organization for Cloud).
    API/MCP dependency: REST fallback (POST api/qualitygates/select).
    Exit codes: 0 success, 6 approval denied, 7 verification failure, 1 general failure.
    Output: JSON result.
    Verification: api/qualitygates/select has no read-back response body
        (the project_status endpoint does not echo the gate name either)
        -- verification here means "the POST returned 2xx", reported as
        CONFIRMED on success. This is a narrower guarantee than other
        Skills' GET-after-write checks; documented honestly rather than
        over-claiming a richer verification that the API does not support.
    Audit: writes one WRITE audit record.
    Security: TLS enforced; approval re-checked immediately before POST.

.EXAMPLE
    ./select-quality-gate.ps1 -BaseUrl "https://sonarqube.example.internal" `
        -ProjectKey my-app -GateName "Sonar way" -User jdoe -OperationId op-aaa111
#>

[CmdletBinding(SupportsShouldAction = $true)]
param(
    [Parameter(Mandatory = $true)][string]$BaseUrl,
    [Parameter(Mandatory = $true)][string]$ProjectKey,
    [Parameter(Mandatory = $true)][string]$GateName,
    [string]$Organization = $null,
    [Parameter(Mandatory = $true)][string]$User,
    [Parameter(Mandatory = $true)][string]$OperationId
)

$ScriptVersion = "1.0.0"
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Import-Module (Join-Path $PSScriptRoot "../../../../../scripts/common/Common.psm1") -Force

$target = $ProjectKey
$operationKey = "sonarqube.quality_gate.select"

$approval = Test-ApprovalToken -OperationId $OperationId -System "sonarqube" `
    -Target $target -Operation $operationKey -ExpectedApprovalType "APPROVE UPDATE"

if (-not $approval.Valid) {
    Write-AuditLog -OperationId $OperationId -User $User -System "sonarqube" `
        -SystemVersion "runtime-detected" -Resource "quality_gate" -Operation "SELECT" -Target $target `
        -ExecutionMechanism "rest-api" -Skill "sonarqube-quality-gates" `
        -Script "select-quality-gate.ps1" -ScriptVersion $ScriptVersion `
        -Risk "WRITE" -ApprovalRequired $true -ApprovalStatus "DENIED" `
        -Result "DENIED" -Verification "NOT_APPLICABLE" -Error $approval.Reason

    Write-Error "Approval check failed: $($approval.Reason)"
    exit ([int][DevOpsExitCode]::ApprovalDenied)
}

$selectUri = "$BaseUrl/api/qualitygates/select"
if ($Organization) { $selectUri += "?organization=$Organization" }

try {
    $token = Read-LocalSecret -System sonarqube

    if ($PSCmdlet.ShouldProcess($target, "SELECT quality gate '$GateName' for SonarQube project")) {
        Invoke-SecureRestMethod -Uri $selectUri -Method POST -Token $token `
            -Body @{ projectKey = $ProjectKey; gateName = $GateName } -BodyEncoding Form | Out-Null
        Set-ApprovalConsumed -OperationId $OperationId

        # api/qualitygates/select has no read-back body; a non-throwing
        # POST is the only confirmation this API offers (see .SYNOPSIS).
        $verification = "CONFIRMED"
        $result = "SUCCESS"

        Write-AuditLog -OperationId $OperationId -User $User -System "sonarqube" `
            -SystemVersion "runtime-detected" -Resource "quality_gate" -Operation "SELECT" -Target $target `
            -ExecutionMechanism "rest-api" -Skill "sonarqube-quality-gates" `
            -Script "select-quality-gate.ps1" -ScriptVersion $ScriptVersion `
            -Risk "WRITE" -ApprovalRequired $true -ApprovalStatus "APPROVED" `
            -Result $result -Verification $verification

        [pscustomobject]@{ operationId = $OperationId; target = $target; gateName = $GateName; result = $result; verification = $verification } | ConvertTo-Json
        exit ([int][DevOpsExitCode]::Success)
    }
    else {
        Write-Host "(WhatIf) Would SELECT quality gate '$GateName' for SonarQube project '$target'. No change made."
        exit ([int][DevOpsExitCode]::Success)
    }
}
catch {
    Write-AuditLog -OperationId $OperationId -User $User -System "sonarqube" `
        -SystemVersion "runtime-detected" -Resource "quality_gate" -Operation "SELECT" -Target $target `
        -ExecutionMechanism "rest-api" -Skill "sonarqube-quality-gates" `
        -Script "select-quality-gate.ps1" -ScriptVersion $ScriptVersion `
        -Risk "WRITE" -ApprovalRequired $true -ApprovalStatus "APPROVED" `
        -Result "FAILURE" -Verification "UNKNOWN" -Error $_.Exception.Message

    Write-Error "Failed to select quality gate for '$target': $($_.Exception.Message)"
    exit ([int][DevOpsExitCode]::GeneralFailure)
}
