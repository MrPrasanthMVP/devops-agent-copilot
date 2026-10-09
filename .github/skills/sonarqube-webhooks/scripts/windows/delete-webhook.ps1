#Requires -Version 7.0
<#
.SYNOPSIS
    DESTRUCTIVE: Permanently deletes a SonarQube webhook. Requires a
    pre-issued, matching "APPROVE DELETE" approval record.

.DESCRIPTION
    Purpose: Execute the DELETE stage for a webhook.
    Supported OS: Windows (PowerShell 7+).
    Dependencies: scripts/common/Common.psm1
    Parameters: BaseUrl, WebhookKey, ProjectKey (optional - only used to
        scope the post-delete list-and-confirm check), Organization
        (optional, Cloud only), User, OperationId
    Authentication: SonarQube user token (POC: local-secrets).
    Required permissions: 'Administer System' (global) or 'Administer'
        on the project (project-scoped).
    Approval requirements: MANDATORY "APPROVE DELETE" bound to this exact WebhookKey.
    Dry-run: -WhatIf supported.
    Deployment: works against BOTH Server and Cloud (pass -Organization for Cloud).
    API/MCP dependency: REST fallback (POST api/webhooks/delete). There
        is no MCP delete-webhook tool in the verified catalog (see
        SKILL.md) -- this operation is REST-fallback-only, always.
    Exit codes: 0 success, 6 approval denied, 7 verification failure, 1 general failure.
    Output: JSON result.
    Verification: list-after-delete; confirm the webhook key is absent.
    Audit: writes one DESTRUCTIVE audit record.
    Security: TLS enforced; approval re-checked immediately before POST.

.EXAMPLE
    ./delete-webhook.ps1 -BaseUrl "https://sonarqube.example.internal" `
        -WebhookKey AbCd1234 -User jdoe -OperationId op-aaa111
#>

[CmdletBinding(SupportsShouldAction = $true)]
param(
    [Parameter(Mandatory = $true)][string]$BaseUrl,
    [Parameter(Mandatory = $true)][string]$WebhookKey,
    [string]$ProjectKey = $null,
    [string]$Organization = $null,
    [Parameter(Mandatory = $true)][string]$User,
    [Parameter(Mandatory = $true)][string]$OperationId
)

$ScriptVersion = "1.0.0"
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Import-Module (Join-Path $PSScriptRoot "../../../../../scripts/common/Common.psm1") -Force

$target = $WebhookKey
$operationKey = "sonarqube.webhook.delete"

$approval = Test-ApprovalToken -OperationId $OperationId -System "sonarqube" `
    -Target $target -Operation $operationKey -ExpectedApprovalType "APPROVE DELETE"

if (-not $approval.Valid) {
    Write-AuditLog -OperationId $OperationId -User $User -System "sonarqube" `
        -SystemVersion "runtime-detected" -Resource "webhook" -Operation "DELETE" -Target $target `
        -ExecutionMechanism "rest-api" -Skill "sonarqube-webhooks" `
        -Script "delete-webhook.ps1" -ScriptVersion $ScriptVersion `
        -Risk "DESTRUCTIVE" -ApprovalRequired $true -ApprovalStatus "DENIED" `
        -Result "DENIED" -Verification "NOT_APPLICABLE" -Error $approval.Reason

    Write-Error "Approval check failed: $($approval.Reason)"
    exit ([int][DevOpsExitCode]::ApprovalDenied)
}

$deleteUri = "$BaseUrl/api/webhooks/delete"
$listUri = "$BaseUrl/api/webhooks/list"
$listQs = @()
if ($ProjectKey) { $listQs += "project=$ProjectKey" }
if ($Organization) {
    $deleteUri += "?organization=$Organization"
    $listQs += "organization=$Organization"
}
if ($listQs.Count -gt 0) { $listUri += "?" + ($listQs -join "&") }

try {
    $token = Read-LocalSecret -System sonarqube

    if ($PSCmdlet.ShouldProcess($target, "DELETE SonarQube webhook")) {
        Invoke-SecureRestMethod -Uri $deleteUri -Method POST -Token $token -Body @{ webhook = $WebhookKey } -BodyEncoding Form | Out-Null
        Set-ApprovalConsumed -OperationId $OperationId

        $verification = "UNKNOWN"
        $result = "UNKNOWN"
        try {
            $found = Invoke-SecureRestMethod -Uri $listUri -Method GET -Token $token
            $stillPresent = $found.webhooks | Where-Object { $_.key -eq $WebhookKey }
            if (-not $stillPresent) {
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
            -SystemVersion "runtime-detected" -Resource "webhook" -Operation "DELETE" -Target $target `
            -ExecutionMechanism "rest-api" -Skill "sonarqube-webhooks" `
            -Script "delete-webhook.ps1" -ScriptVersion $ScriptVersion `
            -Risk "DESTRUCTIVE" -ApprovalRequired $true -ApprovalStatus "APPROVED" `
            -Result $result -Verification $verification

        [pscustomobject]@{ operationId = $OperationId; target = $target; result = $result; verification = $verification } | ConvertTo-Json

        if ($verification -ne "CONFIRMED") { exit ([int][DevOpsExitCode]::VerificationFailure) }
        exit ([int][DevOpsExitCode]::Success)
    }
    else {
        Write-Host "(WhatIf) Would DELETE SonarQube webhook '$target'. No change made."
        exit ([int][DevOpsExitCode]::Success)
    }
}
catch {
    Write-AuditLog -OperationId $OperationId -User $User -System "sonarqube" `
        -SystemVersion "runtime-detected" -Resource "webhook" -Operation "DELETE" -Target $target `
        -ExecutionMechanism "rest-api" -Skill "sonarqube-webhooks" `
        -Script "delete-webhook.ps1" -ScriptVersion $ScriptVersion `
        -Risk "DESTRUCTIVE" -ApprovalRequired $true -ApprovalStatus "APPROVED" `
        -Result "FAILURE" -Verification "UNKNOWN" -Error $_.Exception.Message

    Write-Error "Failed to delete webhook '$target': $($_.Exception.Message)"
    exit ([int][DevOpsExitCode]::GeneralFailure)
}
