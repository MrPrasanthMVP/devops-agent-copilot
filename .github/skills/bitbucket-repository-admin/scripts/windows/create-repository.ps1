#Requires -Version 7.0
<#
.SYNOPSIS
    WRITE: Creates a new Bitbucket Data Center repository. Requires a
    pre-issued, matching "APPROVE CREATE" approval record.

.DESCRIPTION
    Purpose: Execute the CREATE stage for a new repository.
    Supported OS: Windows (PowerShell 7+).
    Dependencies: scripts/common/Common.psm1
    Parameters: BaseUrl, ProjectKey, RepositorySlug, User, OperationId
    Authentication: Bitbucket HTTP access token (POC: local-secrets).
    Required permissions: Bitbucket project "Write" permission.
    Approval requirements: MANDATORY "APPROVE CREATE" bound to this exact
        ProjectKey/RepositorySlug.
    Dry-run: -WhatIf supported.
    API/MCP dependency: REST fallback
        (POST /rest/api/1.0/projects/{projectKey}/repos).
    Exit codes: 0 success, 6 approval denied, 7 verification failure,
        1 general failure.
    Output: JSON result.
    Verification: GET after create; confirm slug/name match.
    Audit: writes one WRITE audit record.
    Security: TLS enforced; approval re-checked immediately before POST.

.EXAMPLE
    ./create-repository.ps1 -BaseUrl "https://bitbucket.example.com" `
        -ProjectKey ABC -RepositorySlug new-svc -User jdoe -OperationId op-aaa111
#>

[CmdletBinding(SupportsShouldAction = $true)]
param(
    [Parameter(Mandatory = $true)][string]$BaseUrl,
    [Parameter(Mandatory = $true)][string]$ProjectKey,
    [Parameter(Mandatory = $true)][string]$RepositorySlug,
    [Parameter(Mandatory = $true)][string]$User,
    [Parameter(Mandatory = $true)][string]$OperationId
)

$ScriptVersion = "1.0.0"
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Import-Module (Join-Path $PSScriptRoot "../../../../../scripts/common/Common.psm1") -Force

$target = "$ProjectKey/$RepositorySlug"
$operationKey = "bitbucket.repository.create"

$approval = Test-ApprovalToken -OperationId $OperationId -System "bitbucket" `
    -Target $target -Operation $operationKey -ExpectedApprovalType "APPROVE CREATE"

if (-not $approval.Valid) {
    Write-AuditLog -OperationId $OperationId -User $User -System "bitbucket" `
        -SystemVersion "runtime-detected" -Resource "repository" -Operation "CREATE" -Target $target `
        -ExecutionMechanism "rest-api" -Skill "bitbucket-repository-admin" `
        -Script "create-repository.ps1" -ScriptVersion $ScriptVersion `
        -Risk "WRITE" -ApprovalRequired $true -ApprovalStatus "DENIED" `
        -Result "DENIED" -Verification "NOT_APPLICABLE" -Error $approval.Reason

    Write-Error "Approval check failed: $($approval.Reason)"
    exit ([int][DevOpsExitCode]::ApprovalDenied)
}

$collectionUri = "$BaseUrl/rest/api/1.0/projects/$ProjectKey/repos"
$repoUri = "$collectionUri/$RepositorySlug"

try {
    $token = Read-LocalSecret -System bitbucket

    if ($PSCmdlet.ShouldProcess($target, "CREATE Bitbucket repository")) {
        Invoke-SecureRestMethod -Uri $collectionUri -Method POST -Token $token `
            -Body @{ name = $RepositorySlug; scmId = "git" } | Out-Null
        Set-ApprovalConsumed -OperationId $OperationId

        $verification = "UNKNOWN"
        $result = "UNKNOWN"
        try {
            $created = Invoke-SecureRestMethod -Uri $repoUri -Method GET -Token $token
            if ($created.slug -eq $RepositorySlug) {
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

        Write-AuditLog -OperationId $OperationId -User $User -System "bitbucket" `
            -SystemVersion "runtime-detected" -Resource "repository" -Operation "CREATE" -Target $target `
            -ExecutionMechanism "rest-api" -Skill "bitbucket-repository-admin" `
            -Script "create-repository.ps1" -ScriptVersion $ScriptVersion `
            -Risk "WRITE" -ApprovalRequired $true -ApprovalStatus "APPROVED" `
            -Result $result -Verification $verification

        [pscustomobject]@{ operationId = $OperationId; target = $target; result = $result; verification = $verification } | ConvertTo-Json

        if ($verification -ne "CONFIRMED") { exit ([int][DevOpsExitCode]::VerificationFailure) }
        exit ([int][DevOpsExitCode]::Success)
    }
    else {
        Write-Host "(WhatIf) Would CREATE Bitbucket repository '$target'. No change made."
        exit ([int][DevOpsExitCode]::Success)
    }
}
catch {
    Write-AuditLog -OperationId $OperationId -User $User -System "bitbucket" `
        -SystemVersion "runtime-detected" -Resource "repository" -Operation "CREATE" -Target $target `
        -ExecutionMechanism "rest-api" -Skill "bitbucket-repository-admin" `
        -Script "create-repository.ps1" -ScriptVersion $ScriptVersion `
        -Risk "WRITE" -ApprovalRequired $true -ApprovalStatus "APPROVED" `
        -Result "FAILURE" -Verification "UNKNOWN" -Error $_.Exception.Message

    Write-Error "Failed to create repository '$target': $($_.Exception.Message)"
    exit ([int][DevOpsExitCode]::GeneralFailure)
}
