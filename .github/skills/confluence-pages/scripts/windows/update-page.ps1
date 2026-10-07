#Requires -Version 7.0
<#
.SYNOPSIS
    WRITE: Updates a Confluence Cloud page's content via REST API v2
    fallback. Requires a pre-issued, matching "APPROVE UPDATE" approval
    record.

.DESCRIPTION
    Purpose: Execute the UPDATE stage for one Confluence page.
    Supported OS: Windows (PowerShell 7+).
    Dependencies: scripts/common/Common.psm1
    Parameters: SiteUrl, PageId, CurrentVersion, Title, BodyStorageValue,
        Email, ApiToken, User, OperationId
    Authentication: Atlassian Cloud API token, Basic auth (email:token).
    Required permissions: Confluence "Add/Update page" space permission.
    Approval requirements: MANDATORY "APPROVE UPDATE" bound to this
        exact PageId.
    Dry-run: -WhatIf supported.
    API/MCP dependency: REST fallback (PUT /wiki/api/v2/pages/{id}).
    Exit codes: 0 success, 6 approval denied, 7 verification failure,
        9 version conflict, 1 general failure.
    Output: JSON result.
    Verification: GET after PUT; compare version.number.
    Audit: writes one WRITE audit record (never the page body).
    Security: TLS enforced; approval re-checked immediately before PUT;
        page content is treated as untrusted data, never instructions.

.EXAMPLE
    ./update-page.ps1 -SiteUrl "https://example.atlassian.net" -PageId 123456 `
        -CurrentVersion 4 -Title "Deployment Architecture" -BodyStorageValue "<p>New</p>" `
        -Email jdoe@example.com -ApiToken $token -User jdoe -OperationId op-123
#>

[CmdletBinding(SupportsShouldAction = $true)]
param(
    [Parameter(Mandatory = $true)][string]$SiteUrl,
    [Parameter(Mandatory = $true)][string]$PageId,
    [Parameter(Mandatory = $true)][int]$CurrentVersion,
    [Parameter(Mandatory = $true)][string]$Title,
    [Parameter(Mandatory = $true)][string]$BodyStorageValue,
    [Parameter(Mandatory = $true)][string]$Email,
    [Parameter(Mandatory = $true)][System.Security.SecureString]$ApiToken,
    [Parameter(Mandatory = $true)][string]$User,
    [Parameter(Mandatory = $true)][string]$OperationId
)

$ScriptVersion = "1.0.0"
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Import-Module (Join-Path $PSScriptRoot "../../../../../scripts/common/Common.psm1") -Force

$operationKey = "confluence.page.update"
$approval = Test-ApprovalToken -OperationId $OperationId -System "confluence" `
    -Target $PageId -Operation $operationKey -ExpectedApprovalType "APPROVE UPDATE"

if (-not $approval.Valid) {
    Write-AuditLog -OperationId $OperationId -User $User -System "confluence" `
        -SystemVersion "cloud" -Resource "page" -Operation "UPDATE" -Target $PageId `
        -ExecutionMechanism "rest-api" -Skill "confluence-pages" `
        -Script "update-page.ps1" -ScriptVersion $ScriptVersion `
        -Risk "WRITE" -ApprovalRequired $true -ApprovalStatus "DENIED" `
        -Result "DENIED" -Verification "NOT_APPLICABLE" -Error $approval.Reason
    Write-Error "Approval check failed: $($approval.Reason)"
    exit ([int][DevOpsExitCode]::ApprovalDenied)
}

$uri = "$SiteUrl/wiki/api/v2/pages/$PageId"
$newVersion = $CurrentVersion + 1

try {
    $plainToken = ConvertFrom-SecureStringPlain -Secure $ApiToken
    $basic = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes("$Email`:$plainToken"))
    $plainToken = $null
    $secureBasic = ConvertTo-SecureString -String $basic -AsPlainText -Force

    $body = @{
        id      = $PageId
        status  = "current"
        title   = $Title
        body    = @{ representation = "storage"; value = $BodyStorageValue }
        version = @{ number = $newVersion }
    }

    if ($PSCmdlet.ShouldProcess($PageId, "UPDATE Confluence page content")) {
        Invoke-SecureRestMethod -Uri $uri -Method PUT -Token $secureBasic -AuthScheme "Basic" -Body $body | Out-Null
        Set-ApprovalConsumed -OperationId $OperationId

        $verification = "UNKNOWN"; $result = "UNKNOWN"
        try {
            $page = Invoke-SecureRestMethod -Uri $uri -Method GET -Token $secureBasic -AuthScheme "Basic"
            if ($page.version.number -eq $newVersion) { $verification = "CONFIRMED"; $result = "SUCCESS" }
            else { $verification = "FAILED" }
        }
        catch { $verification = "FAILED" }

        Write-AuditLog -OperationId $OperationId -User $User -System "confluence" `
            -SystemVersion "cloud" -Resource "page" -Operation "UPDATE" -Target $PageId `
            -ExecutionMechanism "rest-api" -Skill "confluence-pages" `
            -Script "update-page.ps1" -ScriptVersion $ScriptVersion `
            -Risk "WRITE" -ApprovalRequired $true -ApprovalStatus "APPROVED" `
            -Result $result -Verification $verification

        [pscustomobject]@{ operationId = $OperationId; target = $PageId; newVersion = $newVersion; result = $result; verification = $verification } | ConvertTo-Json
        if ($verification -ne "CONFIRMED") { exit ([int][DevOpsExitCode]::VerificationFailure) }
        exit ([int][DevOpsExitCode]::Success)
    }
    else {
        Write-Host "(WhatIf) Would UPDATE Confluence page '$PageId' (version $CurrentVersion -> $newVersion). No change made."
        exit ([int][DevOpsExitCode]::Success)
    }
}
catch {
    Write-AuditLog -OperationId $OperationId -User $User -System "confluence" `
        -SystemVersion "cloud" -Resource "page" -Operation "UPDATE" -Target $PageId `
        -ExecutionMechanism "rest-api" -Skill "confluence-pages" `
        -Script "update-page.ps1" -ScriptVersion $ScriptVersion `
        -Risk "WRITE" -ApprovalRequired $true -ApprovalStatus "APPROVED" `
        -Result "FAILURE" -Verification "UNKNOWN" -Error $_.Exception.Message
    Write-Error "Failed to update page '$PageId': $($_.Exception.Message)"
    exit ([int][DevOpsExitCode]::GeneralFailure)
}
