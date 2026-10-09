#Requires -Version 7.0
<#
.SYNOPSIS
    WRITE: Performs a workflow transition on a SonarQube issue (e.g.
    confirm, resolve, reopen). Requires a pre-issued, matching
    "APPROVE UPDATE" approval record.

.DESCRIPTION
    Purpose: Execute the TRANSITION stage for one issue.
    Supported OS: Windows (PowerShell 7+).
    Dependencies: scripts/common/Common.psm1
    Parameters: BaseUrl, IssueKey, Transition (one of: confirm, unconfirm,
        reopen, resolve, falsepositive, wontfix), Organization (optional,
        Cloud only), User, OperationId
    Authentication: SonarQube user token (POC: local-secrets).
    Required permissions: 'confirm'/'falsepositive'/'wontfix' require
        'Administer Issues' on the project; other transitions require
        only 'Browse'.
    Approval requirements: MANDATORY "APPROVE UPDATE" bound to this exact IssueKey.
    Dry-run: -WhatIf supported.
    Deployment: works against BOTH Server and Cloud (pass -Organization for Cloud).
    API/MCP dependency: REST fallback (POST api/issues/do_transition).
        The MCP server's change_sonar_issue_status tool exposes a
        NARROWER vocabulary (accept/falsepositive/reopen) than this REST
        endpoint's full state machine (confirm/unconfirm/reopen/resolve/
        falsepositive/wontfix) -- this script always uses the REST
        endpoint directly so every transition value is available.
    Exit codes: 0 success, 6 approval denied, 7 verification failure, 1 general failure.
    Output: JSON result.
    Verification: search-after-transition; confirm the issue's status
        matches the expected post-transition value (only the top-level
        `status` is checked, not the `resolution` sub-field -- see the
        $expectedStatus map below for exactly what is and isn't verified).
    Audit: writes one WRITE audit record.
    Security: TLS enforced; approval re-checked immediately before POST.

.EXAMPLE
    ./transition-issue.ps1 -BaseUrl "https://sonarqube.example.internal" `
        -IssueKey AbCd1234 -Transition resolve -User jdoe -OperationId op-aaa111
#>

[CmdletBinding(SupportsShouldAction = $true)]
param(
    [Parameter(Mandatory = $true)][string]$BaseUrl,
    [Parameter(Mandatory = $true)][string]$IssueKey,
    [Parameter(Mandatory = $true)]
    [ValidateSet('confirm', 'unconfirm', 'reopen', 'resolve', 'falsepositive', 'wontfix')]
    [string]$Transition,
    [string]$Organization = $null,
    [Parameter(Mandatory = $true)][string]$User,
    [Parameter(Mandatory = $true)][string]$OperationId
)

$ScriptVersion = "1.0.0"
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Import-Module (Join-Path $PSScriptRoot "../../../../../scripts/common/Common.psm1") -Force

$target = $IssueKey
$operationKey = "sonarqube.issue.transition"

# Expected top-level `status` after each transition (resolution sub-field,
# e.g. FALSE-POSITIVE/WONTFIX, is not separately re-verified here).
$expectedStatus = @{
    confirm       = 'CONFIRMED'
    unconfirm     = 'REOPENED'
    reopen        = 'REOPENED'
    resolve       = 'RESOLVED'
    falsepositive = 'RESOLVED'
    wontfix       = 'RESOLVED'
}

$approval = Test-ApprovalToken -OperationId $OperationId -System "sonarqube" `
    -Target $target -Operation $operationKey -ExpectedApprovalType "APPROVE UPDATE"

if (-not $approval.Valid) {
    Write-AuditLog -OperationId $OperationId -User $User -System "sonarqube" `
        -SystemVersion "runtime-detected" -Resource "issue" -Operation "TRANSITION" -Target $target `
        -ExecutionMechanism "rest-api" -Skill "sonarqube-issues" `
        -Script "transition-issue.ps1" -ScriptVersion $ScriptVersion `
        -Risk "WRITE" -ApprovalRequired $true -ApprovalStatus "DENIED" `
        -Result "DENIED" -Verification "NOT_APPLICABLE" -Error $approval.Reason

    Write-Error "Approval check failed: $($approval.Reason)"
    exit ([int][DevOpsExitCode]::ApprovalDenied)
}

$transitionUri = "$BaseUrl/api/issues/do_transition"
$searchUri = "$BaseUrl/api/issues/search?issues=$IssueKey"
if ($Organization) {
    $transitionUri += "?organization=$Organization"
    $searchUri += "&organization=$Organization"
}

try {
    $token = Read-LocalSecret -System sonarqube

    if ($PSCmdlet.ShouldProcess($target, "TRANSITION ($Transition) SonarQube issue")) {
        Invoke-SecureRestMethod -Uri $transitionUri -Method POST -Token $token `
            -Body @{ issue = $IssueKey; transition = $Transition } -BodyEncoding Form | Out-Null
        Set-ApprovalConsumed -OperationId $OperationId

        $verification = "UNKNOWN"
        $result = "UNKNOWN"
        try {
            $found = Invoke-SecureRestMethod -Uri $searchUri -Method GET -Token $token
            $issue = $found.issues | Where-Object { $_.key -eq $IssueKey } | Select-Object -First 1
            if ($issue -and $issue.status -eq $expectedStatus[$Transition]) {
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
            -SystemVersion "runtime-detected" -Resource "issue" -Operation "TRANSITION" -Target $target `
            -ExecutionMechanism "rest-api" -Skill "sonarqube-issues" `
            -Script "transition-issue.ps1" -ScriptVersion $ScriptVersion `
            -Risk "WRITE" -ApprovalRequired $true -ApprovalStatus "APPROVED" `
            -Result $result -Verification $verification

        [pscustomobject]@{ operationId = $OperationId; target = $target; transition = $Transition; result = $result; verification = $verification } | ConvertTo-Json

        if ($verification -ne "CONFIRMED") { exit ([int][DevOpsExitCode]::VerificationFailure) }
        exit ([int][DevOpsExitCode]::Success)
    }
    else {
        Write-Host "(WhatIf) Would TRANSITION ($Transition) SonarQube issue '$target'. No change made."
        exit ([int][DevOpsExitCode]::Success)
    }
}
catch {
    Write-AuditLog -OperationId $OperationId -User $User -System "sonarqube" `
        -SystemVersion "runtime-detected" -Resource "issue" -Operation "TRANSITION" -Target $target `
        -ExecutionMechanism "rest-api" -Skill "sonarqube-issues" `
        -Script "transition-issue.ps1" -ScriptVersion $ScriptVersion `
        -Risk "WRITE" -ApprovalRequired $true -ApprovalStatus "APPROVED" `
        -Result "FAILURE" -Verification "UNKNOWN" -Error $_.Exception.Message

    Write-Error "Failed to transition issue '$target': $($_.Exception.Message)"
    exit ([int][DevOpsExitCode]::GeneralFailure)
}
