#Requires -Version 7.0
<#
.SYNOPSIS
    WRITE: Changes a SonarQube security hotspot's review status. Requires
    a pre-issued, matching "APPROVE UPDATE" approval record.

.DESCRIPTION
    Purpose: Execute the CHANGE_STATUS stage for one hotspot.
    Supported OS: Windows (PowerShell 7+).
    Dependencies: scripts/common/Common.psm1
    Parameters: BaseUrl, HotspotKey, Status (TO_REVIEW|REVIEWED),
        Resolution (optional, required when Status=REVIEWED: FIXED|SAFE),
        Comment (optional), Organization (optional, Cloud only), User, OperationId
    Authentication: SonarQube user token (POC: local-secrets).
    Required permissions: 'Administer Security Hotspot' on the project.
    Approval requirements: MANDATORY "APPROVE UPDATE" bound to this exact HotspotKey.
    Dry-run: -WhatIf supported.
    Deployment: works against BOTH Server and Cloud (pass -Organization for Cloud).
    API/MCP dependency: REST fallback (POST api/hotspots/change_status).
    Exit codes: 0 success, 6 approval denied, 7 verification failure, 1 general failure.
    Output: JSON result.
    Verification: show-after-change; confirm the hotspot's status (and
        resolution, when applicable) matches.
    Audit: writes one WRITE audit record.
    Security: TLS enforced; approval re-checked immediately before POST.

.EXAMPLE
    ./change-hotspot-status.ps1 -BaseUrl "https://sonarqube.example.internal" `
        -HotspotKey AbCd1234 -Status REVIEWED -Resolution SAFE -User jdoe -OperationId op-aaa111
#>

[CmdletBinding(SupportsShouldAction = $true)]
param(
    [Parameter(Mandatory = $true)][string]$BaseUrl,
    [Parameter(Mandatory = $true)][string]$HotspotKey,
    [Parameter(Mandatory = $true)][ValidateSet('TO_REVIEW', 'REVIEWED')][string]$Status,
    [ValidateSet('FIXED', 'SAFE')][string]$Resolution = $null,
    [string]$Comment = $null,
    [string]$Organization = $null,
    [Parameter(Mandatory = $true)][string]$User,
    [Parameter(Mandatory = $true)][string]$OperationId
)

$ScriptVersion = "1.0.0"
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if ($Status -eq 'REVIEWED' -and -not $Resolution) {
    Write-Error "-Resolution (FIXED or SAFE) is required when -Status is REVIEWED."
    exit 2
}

Import-Module (Join-Path $PSScriptRoot "../../../../../scripts/common/Common.psm1") -Force

$target = $HotspotKey
$operationKey = "sonarqube.hotspot.change_status"

$approval = Test-ApprovalToken -OperationId $OperationId -System "sonarqube" `
    -Target $target -Operation $operationKey -ExpectedApprovalType "APPROVE UPDATE"

if (-not $approval.Valid) {
    Write-AuditLog -OperationId $OperationId -User $User -System "sonarqube" `
        -SystemVersion "runtime-detected" -Resource "hotspot" -Operation "CHANGE_STATUS" -Target $target `
        -ExecutionMechanism "rest-api" -Skill "sonarqube-hotspots" `
        -Script "change-hotspot-status.ps1" -ScriptVersion $ScriptVersion `
        -Risk "WRITE" -ApprovalRequired $true -ApprovalStatus "DENIED" `
        -Result "DENIED" -Verification "NOT_APPLICABLE" -Error $approval.Reason

    Write-Error "Approval check failed: $($approval.Reason)"
    exit ([int][DevOpsExitCode]::ApprovalDenied)
}

$changeUri = "$BaseUrl/api/hotspots/change_status"
$showUri = "$BaseUrl/api/hotspots/show?hotspot=$HotspotKey"
if ($Organization) {
    $changeUri += "?organization=$Organization"
    $showUri += "&organization=$Organization"
}

try {
    $token = Read-LocalSecret -System sonarqube

    if ($PSCmdlet.ShouldProcess($target, "CHANGE_STATUS ($Status) SonarQube hotspot")) {
        $body = @{ hotspot = $HotspotKey; status = $Status }
        if ($Resolution) { $body["resolution"] = $Resolution }
        if ($Comment) { $body["comment"] = $Comment }

        Invoke-SecureRestMethod -Uri $changeUri -Method POST -Token $token -Body $body -BodyEncoding Form | Out-Null
        Set-ApprovalConsumed -OperationId $OperationId

        $verification = "UNKNOWN"
        $result = "UNKNOWN"
        try {
            $hotspot = Invoke-SecureRestMethod -Uri $showUri -Method GET -Token $token
            $statusMatches = $hotspot.status -eq $Status
            $resolutionMatches = (-not $Resolution) -or ($hotspot.resolution -eq $Resolution)
            if ($statusMatches -and $resolutionMatches) {
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
            -SystemVersion "runtime-detected" -Resource "hotspot" -Operation "CHANGE_STATUS" -Target $target `
            -ExecutionMechanism "rest-api" -Skill "sonarqube-hotspots" `
            -Script "change-hotspot-status.ps1" -ScriptVersion $ScriptVersion `
            -Risk "WRITE" -ApprovalRequired $true -ApprovalStatus "APPROVED" `
            -Result $result -Verification $verification

        [pscustomobject]@{ operationId = $OperationId; target = $target; status = $Status; resolution = $Resolution; result = $result; verification = $verification } | ConvertTo-Json

        if ($verification -ne "CONFIRMED") { exit ([int][DevOpsExitCode]::VerificationFailure) }
        exit ([int][DevOpsExitCode]::Success)
    }
    else {
        Write-Host "(WhatIf) Would CHANGE_STATUS ($Status) SonarQube hotspot '$target'. No change made."
        exit ([int][DevOpsExitCode]::Success)
    }
}
catch {
    Write-AuditLog -OperationId $OperationId -User $User -System "sonarqube" `
        -SystemVersion "runtime-detected" -Resource "hotspot" -Operation "CHANGE_STATUS" -Target $target `
        -ExecutionMechanism "rest-api" -Skill "sonarqube-hotspots" `
        -Script "change-hotspot-status.ps1" -ScriptVersion $ScriptVersion `
        -Risk "WRITE" -ApprovalRequired $true -ApprovalStatus "APPROVED" `
        -Result "FAILURE" -Verification "UNKNOWN" -Error $_.Exception.Message

    Write-Error "Failed to change hotspot status '$target': $($_.Exception.Message)"
    exit ([int][DevOpsExitCode]::GeneralFailure)
}
