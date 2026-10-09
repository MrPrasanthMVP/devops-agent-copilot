#Requires -Version 7.0
<#
.SYNOPSIS
    WRITE: Assigns (or unassigns) a SonarQube issue. Requires a
    pre-issued, matching "APPROVE UPDATE" approval record.

.DESCRIPTION
    Purpose: Execute the ASSIGN stage for one issue.
    Supported OS: Windows (PowerShell 7+).
    Dependencies: scripts/common/Common.psm1
    Parameters: BaseUrl, IssueKey, Assignee (optional - omit/empty to
        unassign), Organization (optional, Cloud only), User, OperationId
    Authentication: SonarQube user token (POC: local-secrets).
    Required permissions: 'Browse' + 'Administer Issues' (or assignment
        rights) on the issue's project.
    Approval requirements: MANDATORY "APPROVE UPDATE" bound to this exact IssueKey.
    Dry-run: -WhatIf supported.
    Deployment: works against BOTH Server and Cloud (pass -Organization for Cloud).
    API/MCP dependency: REST fallback (POST api/issues/assign). There is
        no MCP assign-issue tool in the verified catalog (see SKILL.md) --
        this operation is REST-fallback-only, always.
    Exit codes: 0 success, 6 approval denied, 7 verification failure, 1 general failure.
    Output: JSON result.
    Verification: search-after-assign; confirm the issue's assignee matches.
    Audit: writes one WRITE audit record.
    Security: TLS enforced; approval re-checked immediately before POST.

.EXAMPLE
    ./assign-issue.ps1 -BaseUrl "https://sonarqube.example.internal" `
        -IssueKey AbCd1234 -Assignee jdoe -User jdoe -OperationId op-aaa111
#>

[CmdletBinding(SupportsShouldAction = $true)]
param(
    [Parameter(Mandatory = $true)][string]$BaseUrl,
    [Parameter(Mandatory = $true)][string]$IssueKey,
    [string]$Assignee = $null,
    [string]$Organization = $null,
    [Parameter(Mandatory = $true)][string]$User,
    [Parameter(Mandatory = $true)][string]$OperationId
)

$ScriptVersion = "1.0.0"
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Import-Module (Join-Path $PSScriptRoot "../../../../../scripts/common/Common.psm1") -Force

$target = $IssueKey
$operationKey = "sonarqube.issue.assign"

$approval = Test-ApprovalToken -OperationId $OperationId -System "sonarqube" `
    -Target $target -Operation $operationKey -ExpectedApprovalType "APPROVE UPDATE"

if (-not $approval.Valid) {
    Write-AuditLog -OperationId $OperationId -User $User -System "sonarqube" `
        -SystemVersion "runtime-detected" -Resource "issue" -Operation "ASSIGN" -Target $target `
        -ExecutionMechanism "rest-api" -Skill "sonarqube-issues" `
        -Script "assign-issue.ps1" -ScriptVersion $ScriptVersion `
        -Risk "WRITE" -ApprovalRequired $true -ApprovalStatus "DENIED" `
        -Result "DENIED" -Verification "NOT_APPLICABLE" -Error $approval.Reason

    Write-Error "Approval check failed: $($approval.Reason)"
    exit ([int][DevOpsExitCode]::ApprovalDenied)
}

$assignUri = "$BaseUrl/api/issues/assign"
$searchUri = "$BaseUrl/api/issues/search?issues=$IssueKey"
if ($Organization) {
    $assignUri += "?organization=$Organization"
    $searchUri += "&organization=$Organization"
}

try {
    $token = Read-LocalSecret -System sonarqube

    if ($PSCmdlet.ShouldProcess($target, "ASSIGN SonarQube issue")) {
        $body = @{ issue = $IssueKey }
        if ($Assignee) { $body["assignee"] = $Assignee }

        Invoke-SecureRestMethod -Uri $assignUri -Method POST -Token $token -Body $body -BodyEncoding Form | Out-Null
        Set-ApprovalConsumed -OperationId $OperationId

        $verification = "UNKNOWN"
        $result = "UNKNOWN"
        try {
            $found = Invoke-SecureRestMethod -Uri $searchUri -Method GET -Token $token
            $issue = $found.issues | Where-Object { $_.key -eq $IssueKey } | Select-Object -First 1
            $actualAssignee = if ($issue) { $issue.assignee } else { $null }
            if ($actualAssignee -eq $Assignee -or (-not $Assignee -and -not $actualAssignee)) {
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
            -SystemVersion "runtime-detected" -Resource "issue" -Operation "ASSIGN" -Target $target `
            -ExecutionMechanism "rest-api" -Skill "sonarqube-issues" `
            -Script "assign-issue.ps1" -ScriptVersion $ScriptVersion `
            -Risk "WRITE" -ApprovalRequired $true -ApprovalStatus "APPROVED" `
            -Result $result -Verification $verification

        [pscustomobject]@{ operationId = $OperationId; target = $target; assignee = $Assignee; result = $result; verification = $verification } | ConvertTo-Json

        if ($verification -ne "CONFIRMED") { exit ([int][DevOpsExitCode]::VerificationFailure) }
        exit ([int][DevOpsExitCode]::Success)
    }
    else {
        Write-Host "(WhatIf) Would ASSIGN SonarQube issue '$target' to '$Assignee'. No change made."
        exit ([int][DevOpsExitCode]::Success)
    }
}
catch {
    Write-AuditLog -OperationId $OperationId -User $User -System "sonarqube" `
        -SystemVersion "runtime-detected" -Resource "issue" -Operation "ASSIGN" -Target $target `
        -ExecutionMechanism "rest-api" -Skill "sonarqube-issues" `
        -Script "assign-issue.ps1" -ScriptVersion $ScriptVersion `
        -Risk "WRITE" -ApprovalRequired $true -ApprovalStatus "APPROVED" `
        -Result "FAILURE" -Verification "UNKNOWN" -Error $_.Exception.Message

    Write-Error "Failed to assign issue '$target': $($_.Exception.Message)"
    exit ([int][DevOpsExitCode]::GeneralFailure)
}
