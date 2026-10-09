#Requires -Version 7.0
<#
.SYNOPSIS
    WRITE: Creates a new SonarQube webhook (global, or project-scoped).
    Requires a pre-issued, matching "APPROVE CREATE" approval record.

.DESCRIPTION
    Purpose: Execute the CREATE stage for a new webhook.
    Supported OS: Windows (PowerShell 7+).
    Dependencies: scripts/common/Common.psm1
    Parameters: BaseUrl, Name, Url, ProjectKey (optional - omit for a
        global webhook), Secret (optional), Organization (optional,
        Cloud only), User, OperationId
    Authentication: SonarQube user token (POC: local-secrets).
    Required permissions: 'Administer System' (global) or 'Administer'
        on the project (project-scoped).
    Approval requirements: MANDATORY "APPROVE CREATE" bound to this exact
        webhook name (and project, if project-scoped).
    Dry-run: -WhatIf supported.
    Deployment: works against BOTH Server and Cloud (pass -Organization for Cloud).
    API/MCP dependency: REST fallback (POST api/webhooks/create).
    Exit codes: 0 success, 6 approval denied, 7 verification failure, 1 general failure.
    Output: JSON result (includes the created webhook's key).
    Verification: list-after-create; confirm a webhook with the returned
        key is present.
    Audit: writes one WRITE audit record.
    Security: TLS enforced; approval re-checked immediately before POST.
        The webhook secret (if supplied) is never logged, printed, or
        included in the audit record (redacted by Protect-SensitiveData).

.EXAMPLE
    ./create-webhook.ps1 -BaseUrl "https://sonarqube.example.internal" `
        -Name "CI notify" -Url "https://ci.example.internal/sonar-hook" `
        -ProjectKey my-app -User jdoe -OperationId op-aaa111
#>

[CmdletBinding(SupportsShouldAction = $true)]
param(
    [Parameter(Mandatory = $true)][string]$BaseUrl,
    [Parameter(Mandatory = $true)][string]$Name,
    [Parameter(Mandatory = $true)][string]$Url,
    [string]$ProjectKey = $null,
    [string]$Secret = $null,
    [string]$Organization = $null,
    [Parameter(Mandatory = $true)][string]$User,
    [Parameter(Mandatory = $true)][string]$OperationId
)

$ScriptVersion = "1.0.0"
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Import-Module (Join-Path $PSScriptRoot "../../../../../scripts/common/Common.psm1") -Force

$target = if ($ProjectKey) { "$ProjectKey/$Name" } else { "global/$Name" }
$operationKey = "sonarqube.webhook.create"

$approval = Test-ApprovalToken -OperationId $OperationId -System "sonarqube" `
    -Target $target -Operation $operationKey -ExpectedApprovalType "APPROVE CREATE"

if (-not $approval.Valid) {
    Write-AuditLog -OperationId $OperationId -User $User -System "sonarqube" `
        -SystemVersion "runtime-detected" -Resource "webhook" -Operation "CREATE" -Target $target `
        -ExecutionMechanism "rest-api" -Skill "sonarqube-webhooks" `
        -Script "create-webhook.ps1" -ScriptVersion $ScriptVersion `
        -Risk "WRITE" -ApprovalRequired $true -ApprovalStatus "DENIED" `
        -Result "DENIED" -Verification "NOT_APPLICABLE" -Error $approval.Reason

    Write-Error "Approval check failed: $($approval.Reason)"
    exit ([int][DevOpsExitCode]::ApprovalDenied)
}

$createUri = "$BaseUrl/api/webhooks/create"
$listUri = "$BaseUrl/api/webhooks/list"
$listQs = @()
if ($ProjectKey) { $listQs += "project=$ProjectKey" }
if ($Organization) {
    $createUri += "?organization=$Organization"
    $listQs += "organization=$Organization"
}
if ($listQs.Count -gt 0) { $listUri += "?" + ($listQs -join "&") }

try {
    $token = Read-LocalSecret -System sonarqube

    if ($PSCmdlet.ShouldProcess($target, "CREATE SonarQube webhook")) {
        $body = @{ name = $Name; url = $Url }
        if ($ProjectKey) { $body["project"] = $ProjectKey }
        if ($Secret) { $body["secret"] = $Secret }

        $created = Invoke-SecureRestMethod -Uri $createUri -Method POST -Token $token -Body $body -BodyEncoding Form
        $createdKey = $created.webhook.key
        Set-ApprovalConsumed -OperationId $OperationId

        $verification = "UNKNOWN"
        $result = "UNKNOWN"
        try {
            $found = Invoke-SecureRestMethod -Uri $listUri -Method GET -Token $token
            $match = $found.webhooks | Where-Object { $_.key -eq $createdKey } | Select-Object -First 1
            if ($match) {
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
            -SystemVersion "runtime-detected" -Resource "webhook" -Operation "CREATE" -Target $target `
            -ExecutionMechanism "rest-api" -Skill "sonarqube-webhooks" `
            -Script "create-webhook.ps1" -ScriptVersion $ScriptVersion `
            -Risk "WRITE" -ApprovalRequired $true -ApprovalStatus "APPROVED" `
            -Result $result -Verification $verification

        [pscustomobject]@{ operationId = $OperationId; target = $target; webhookKey = $createdKey; result = $result; verification = $verification } | ConvertTo-Json

        if ($verification -ne "CONFIRMED") { exit ([int][DevOpsExitCode]::VerificationFailure) }
        exit ([int][DevOpsExitCode]::Success)
    }
    else {
        Write-Host "(WhatIf) Would CREATE SonarQube webhook '$target'. No change made."
        exit ([int][DevOpsExitCode]::Success)
    }
}
catch {
    Write-AuditLog -OperationId $OperationId -User $User -System "sonarqube" `
        -SystemVersion "runtime-detected" -Resource "webhook" -Operation "CREATE" -Target $target `
        -ExecutionMechanism "rest-api" -Skill "sonarqube-webhooks" `
        -Script "create-webhook.ps1" -ScriptVersion $ScriptVersion `
        -Risk "WRITE" -ApprovalRequired $true -ApprovalStatus "APPROVED" `
        -Result "FAILURE" -Verification "UNKNOWN" -Error $_.Exception.Message

    Write-Error "Failed to create webhook '$target': $($_.Exception.Message)"
    exit ([int][DevOpsExitCode]::GeneralFailure)
}
