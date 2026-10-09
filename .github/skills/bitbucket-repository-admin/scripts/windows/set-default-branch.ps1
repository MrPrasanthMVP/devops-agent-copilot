#Requires -Version 7.0
<#
.SYNOPSIS
    ADMINISTRATIVE: Sets a Bitbucket repository's default branch.
    Requires a pre-issued, matching "APPROVE ADMIN CHANGE" approval record.

.DESCRIPTION
    Purpose: Execute the UPDATE stage for a repository's default branch.
    Supported OS: Windows (PowerShell 7+).
    Dependencies: scripts/common/Common.psm1
    Parameters: BaseUrl, ProjectKey, RepositorySlug, BranchName, User, OperationId
    Authentication: Bitbucket HTTP access token (POC: local-secrets).
    Required permissions: Bitbucket project admin permission.
    Approval requirements: MANDATORY "APPROVE ADMIN CHANGE".
    Dry-run: -WhatIf supported.
    API/MCP dependency: REST fallback
        (PUT /rest/api/1.0/projects/{projectKey}/repos/{repositorySlug}/branches/default).
    Exit codes: 0 success, 6 approval denied, 7 verification failure,
        1 general failure.
    Output: JSON result.
    Verification: GET default branch after update; confirm it matches.
    Audit: writes one ADMINISTRATIVE audit record.
    Security: TLS enforced; approval re-checked immediately before PUT.

.EXAMPLE
    ./set-default-branch.ps1 -BaseUrl "https://bitbucket.example.com" `
        -ProjectKey ABC -RepositorySlug xyz -BranchName main -User jdoe -OperationId op-123
#>

[CmdletBinding(SupportsShouldAction = $true)]
param(
    [Parameter(Mandatory = $true)][string]$BaseUrl,
    [Parameter(Mandatory = $true)][string]$ProjectKey,
    [Parameter(Mandatory = $true)][string]$RepositorySlug,
    [Parameter(Mandatory = $true)][string]$BranchName,
    [Parameter(Mandatory = $true)][string]$User,
    [Parameter(Mandatory = $true)][string]$OperationId
)

$ScriptVersion = "1.0.0"
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Import-Module (Join-Path $PSScriptRoot "../../../../../scripts/common/Common.psm1") -Force

$target = "$ProjectKey/$RepositorySlug"
$operationKey = "bitbucket.repository.default_branch.update"

$approval = Test-ApprovalToken -OperationId $OperationId -System "bitbucket" `
    -Target $target -Operation $operationKey -ExpectedApprovalType "APPROVE ADMIN CHANGE"

if (-not $approval.Valid) {
    Write-AuditLog -OperationId $OperationId -User $User -System "bitbucket" `
        -SystemVersion "runtime-detected" -Resource "repository" -Operation "UPDATE" -Target $target `
        -ExecutionMechanism "rest-api" -Skill "bitbucket-repository-admin" `
        -Script "set-default-branch.ps1" -ScriptVersion $ScriptVersion `
        -Risk "ADMINISTRATIVE" -ApprovalRequired $true -ApprovalStatus "DENIED" `
        -Result "DENIED" -Verification "NOT_APPLICABLE" -Error $approval.Reason

    Write-Error "Approval check failed: $($approval.Reason)"
    exit ([int][DevOpsExitCode]::ApprovalDenied)
}

$uri = "$BaseUrl/rest/api/1.0/projects/$ProjectKey/repos/$RepositorySlug/branches/default"
$branchRefId = "refs/heads/$BranchName"

try {
    $token = Read-LocalSecret -System bitbucket

    if ($PSCmdlet.ShouldProcess($target, "SET default branch to '$BranchName'")) {
        Invoke-SecureRestMethod -Uri $uri -Method PUT -Token $token -Body @{ id = $branchRefId } | Out-Null
        Set-ApprovalConsumed -OperationId $OperationId

        $verification = "UNKNOWN"
        $result = "UNKNOWN"
        try {
            $current = Invoke-SecureRestMethod -Uri $uri -Method GET -Token $token
            if ($current.id -eq $branchRefId -or $current.displayId -eq $BranchName) {
                $verification = "CONFIRMED"; $result = "SUCCESS"
            }
            else { $verification = "FAILED" }
        }
        catch { $verification = "FAILED" }

        Write-AuditLog -OperationId $OperationId -User $User -System "bitbucket" `
            -SystemVersion "runtime-detected" -Resource "repository" -Operation "UPDATE" -Target $target `
            -ExecutionMechanism "rest-api" -Skill "bitbucket-repository-admin" `
            -Script "set-default-branch.ps1" -ScriptVersion $ScriptVersion `
            -Risk "ADMINISTRATIVE" -ApprovalRequired $true -ApprovalStatus "APPROVED" `
            -Result $result -Verification $verification

        [pscustomobject]@{ operationId = $OperationId; target = $target; result = $result; verification = $verification } | ConvertTo-Json

        if ($verification -ne "CONFIRMED") { exit ([int][DevOpsExitCode]::VerificationFailure) }
        exit ([int][DevOpsExitCode]::Success)
    }
    else {
        Write-Host "(WhatIf) Would set default branch of '$target' to '$BranchName'. No change made."
        exit ([int][DevOpsExitCode]::Success)
    }
}
catch {
    Write-AuditLog -OperationId $OperationId -User $User -System "bitbucket" `
        -SystemVersion "runtime-detected" -Resource "repository" -Operation "UPDATE" -Target $target `
        -ExecutionMechanism "rest-api" -Skill "bitbucket-repository-admin" `
        -Script "set-default-branch.ps1" -ScriptVersion $ScriptVersion `
        -Risk "ADMINISTRATIVE" -ApprovalRequired $true -ApprovalStatus "APPROVED" `
        -Result "FAILURE" -Verification "UNKNOWN" -Error $_.Exception.Message

    Write-Error "Failed to set default branch for '$target': $($_.Exception.Message)"
    exit ([int][DevOpsExitCode]::GeneralFailure)
}
