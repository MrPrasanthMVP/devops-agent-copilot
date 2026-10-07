#Requires -Version 7.0
<#
.SYNOPSIS
    ADMINISTRATIVE: Updates branch protection settings for a GitHub
    Enterprise (Cloud or Server) repository branch. Requires a
    pre-issued, matching "APPROVE BRANCH PROTECTION" approval record.

.DESCRIPTION
    Purpose: Execute the UPDATE stage for branch protection.
    Supported OS: Windows (PowerShell 7+).
    Dependencies: scripts/common/Common.psm1
    Parameters: ApiBaseUrl, Owner, Repo, Branch,
        RequiredApprovingReviewCount, EnforceAdmins, User, OperationId
    Authentication: GitHub token (POC: local-secrets).
    Required permissions: repository admin permission.
    Approval requirements: MANDATORY "APPROVE BRANCH PROTECTION" bound
        to this exact Owner/Repo/Branch.
    Dry-run: -WhatIf supported.
    API/MCP dependency: REST fallback
        (PUT /repos/{owner}/{repo}/branches/{branch}/protection).
    Exit codes: 0 success, 6 approval denied, 7 verification failure,
        1 general failure.
    Output: JSON result.
    Verification: GET after PUT; compare
        required_pull_request_reviews.required_approving_review_count
        and enforce_admins.enabled against the proposed values.
    Audit: writes one ADMINISTRATIVE audit record.
    Security: TLS enforced; approval re-checked immediately before PUT.
        A reduction in protection strength is treated identically to an
        increase - both require this same approval path.

.EXAMPLE
    ./update-branch-protection.ps1 -ApiBaseUrl "https://api.github.com" `
        -Owner myorg -Repo myrepo -Branch main -RequiredApprovingReviewCount 2 `
        -EnforceAdmins $true -User jdoe -OperationId op-123
#>

[CmdletBinding(SupportsShouldAction = $true)]
param(
    [Parameter(Mandatory = $true)][string]$ApiBaseUrl,
    [Parameter(Mandatory = $true)][string]$Owner,
    [Parameter(Mandatory = $true)][string]$Repo,
    [Parameter(Mandatory = $true)][string]$Branch,
    [Parameter(Mandatory = $true)][ValidateRange(0, 6)][int]$RequiredApprovingReviewCount,
    [Parameter(Mandatory = $true)][bool]$EnforceAdmins,
    [Parameter(Mandatory = $true)][string]$User,
    [Parameter(Mandatory = $true)][string]$OperationId
)

$ScriptVersion = "1.0.0"
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Import-Module (Join-Path $PSScriptRoot "../../../../../scripts/common/Common.psm1") -Force

$target = "$Owner/$Repo@$Branch"
$operationKey = "github.branch_protection.update"

$approval = Test-ApprovalToken -OperationId $OperationId -System "github" `
    -Target $target -Operation $operationKey -ExpectedApprovalType "APPROVE BRANCH PROTECTION"

if (-not $approval.Valid) {
    Write-AuditLog -OperationId $OperationId -User $User -System "github" `
        -SystemVersion "runtime-detected" -Resource "branch_protection" -Operation "UPDATE" -Target $target `
        -ExecutionMechanism "rest-api" -Skill "github-branch-protection" `
        -Script "update-branch-protection.ps1" -ScriptVersion $ScriptVersion `
        -Risk "ADMINISTRATIVE" -ApprovalRequired $true -ApprovalStatus "DENIED" `
        -Result "DENIED" -Verification "NOT_APPLICABLE" -Error $approval.Reason
    Write-Error "Approval check failed: $($approval.Reason)"
    exit ([int][DevOpsExitCode]::ApprovalDenied)
}

$uri = "$ApiBaseUrl/repos/$Owner/$Repo/branches/$Branch/protection"

try {
    $token = Read-LocalSecret -System github

    $body = @{
        required_status_checks        = $null
        enforce_admins                 = $EnforceAdmins
        required_pull_request_reviews  = @{ required_approving_review_count = $RequiredApprovingReviewCount }
        restrictions                    = $null
    }

    if ($PSCmdlet.ShouldProcess($target, "UPDATE branch protection")) {
        Invoke-SecureRestMethod -Uri $uri -Method PUT -Token $token -Body $body | Out-Null
        Set-ApprovalConsumed -OperationId $OperationId

        $verification = "UNKNOWN"; $result = "UNKNOWN"
        try {
            $current = Invoke-SecureRestMethod -Uri $uri -Method GET -Token $token
            $currentCount = $current.required_pull_request_reviews.required_approving_review_count
            $currentEnforce = $current.enforce_admins.enabled
            if ($currentCount -eq $RequiredApprovingReviewCount -and $currentEnforce -eq $EnforceAdmins) {
                $verification = "CONFIRMED"; $result = "SUCCESS"
            }
            else { $verification = "FAILED" }
        }
        catch { $verification = "FAILED" }

        Write-AuditLog -OperationId $OperationId -User $User -System "github" `
            -SystemVersion "runtime-detected" -Resource "branch_protection" -Operation "UPDATE" -Target $target `
            -ExecutionMechanism "rest-api" -Skill "github-branch-protection" `
            -Script "update-branch-protection.ps1" -ScriptVersion $ScriptVersion `
            -Risk "ADMINISTRATIVE" -ApprovalRequired $true -ApprovalStatus "APPROVED" `
            -Result $result -Verification $verification

        [pscustomobject]@{ operationId = $OperationId; target = $target; result = $result; verification = $verification } | ConvertTo-Json
        if ($verification -ne "CONFIRMED") { exit ([int][DevOpsExitCode]::VerificationFailure) }
        exit ([int][DevOpsExitCode]::Success)
    }
    else {
        Write-Host "(WhatIf) Would UPDATE branch protection for '$target'. No change made."
        exit ([int][DevOpsExitCode]::Success)
    }
}
catch {
    Write-AuditLog -OperationId $OperationId -User $User -System "github" `
        -SystemVersion "runtime-detected" -Resource "branch_protection" -Operation "UPDATE" -Target $target `
        -ExecutionMechanism "rest-api" -Skill "github-branch-protection" `
        -Script "update-branch-protection.ps1" -ScriptVersion $ScriptVersion `
        -Risk "ADMINISTRATIVE" -ApprovalRequired $true -ApprovalStatus "APPROVED" `
        -Result "FAILURE" -Verification "UNKNOWN" -Error $_.Exception.Message
    Write-Error "Failed to update branch protection for '$target': $($_.Exception.Message)"
    exit ([int][DevOpsExitCode]::GeneralFailure)
}
