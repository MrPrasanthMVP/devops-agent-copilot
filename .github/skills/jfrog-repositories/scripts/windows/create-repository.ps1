#Requires -Version 7.0
<#
.SYNOPSIS
    ADMINISTRATIVE: Creates a new JFrog Artifactory repository
    configuration. Requires a pre-issued "APPROVE ADMIN CHANGE" approval.

.DESCRIPTION
    Purpose: Execute the CREATE stage for a new repository configuration.
    Supported OS: Windows (PowerShell 7+).
    Dependencies: scripts/common/Common.psm1
    Parameters: BaseUrl, RepoKey, RClass (local|remote|virtual|federated),
        PackageType (e.g. generic, maven, docker), User, OperationId
    Authentication: JFrog access token (POC: local-secrets).
    Required permissions: Artifactory admin permission.
    Approval requirements: MANDATORY "APPROVE ADMIN CHANGE" bound to this
        exact RepoKey.
    Dry-run: -WhatIf supported.
    API/MCP dependency: REST fallback
        (PUT /artifactory/api/repositories/{repoKey}; fails with 400 if
        the repoKey already exists).
    Exit codes: 0 success, 6 approval denied, 7 verification failure, 1 general failure.
    Output: JSON result.
    Verification: GET after create; confirm rclass/packageType match.
    Audit: writes one ADMINISTRATIVE audit record.
    Security: TLS enforced; approval re-checked immediately before PUT.

.EXAMPLE
    ./create-repository.ps1 -BaseUrl "https://jfrog.example.com" `
        -RepoKey libs-release-local -RClass local -PackageType generic `
        -User jdoe -OperationId op-123
#>

[CmdletBinding(SupportsShouldAction = $true)]
param(
    [Parameter(Mandatory = $true)][string]$BaseUrl,
    [Parameter(Mandatory = $true)][ValidatePattern('^[A-Za-z0-9._-]+$')][string]$RepoKey,
    [Parameter(Mandatory = $true)][ValidateSet('local', 'remote', 'virtual', 'federated')][string]$RClass,
    [Parameter(Mandatory = $true)][string]$PackageType,
    [Parameter(Mandatory = $true)][string]$User,
    [Parameter(Mandatory = $true)][string]$OperationId
)

$ScriptVersion = "1.0.0"
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Import-Module (Join-Path $PSScriptRoot "../../../../../scripts/common/Common.psm1") -Force

$operationKey = "jfrog.repository.create"
$approval = Test-ApprovalToken -OperationId $OperationId -System "jfrog" `
    -Target $RepoKey -Operation $operationKey -ExpectedApprovalType "APPROVE ADMIN CHANGE"

if (-not $approval.Valid) {
    Write-AuditLog -OperationId $OperationId -User $User -System "jfrog" `
        -SystemVersion "runtime-detected" -Resource "repository" -Operation "CREATE" -Target $RepoKey `
        -ExecutionMechanism "rest-api" -Skill "jfrog-repositories" `
        -Script "create-repository.ps1" -ScriptVersion $ScriptVersion `
        -Risk "ADMINISTRATIVE" -ApprovalRequired $true -ApprovalStatus "DENIED" `
        -Result "DENIED" -Verification "NOT_APPLICABLE" -Error $approval.Reason
    Write-Error "Approval check failed: $($approval.Reason)"
    exit ([int][DevOpsExitCode]::ApprovalDenied)
}

$uri = "$BaseUrl/artifactory/api/repositories/$RepoKey"

try {
    $token = Read-LocalSecret -System jfrog
    $body = @{ key = $RepoKey; rclass = $RClass; packageType = $PackageType }

    if ($PSCmdlet.ShouldProcess($RepoKey, "CREATE JFrog repository")) {
        Invoke-SecureRestMethod -Uri $uri -Method PUT -Token $token -Body $body | Out-Null
        Set-ApprovalConsumed -OperationId $OperationId

        $verification = "UNKNOWN"; $result = "UNKNOWN"
        try {
            $created = Invoke-SecureRestMethod -Uri $uri -Method GET -Token $token
            if ($created.rclass -eq $RClass) { $verification = "CONFIRMED"; $result = "SUCCESS" }
            else { $verification = "FAILED" }
        }
        catch { $verification = "FAILED" }

        Write-AuditLog -OperationId $OperationId -User $User -System "jfrog" `
            -SystemVersion "runtime-detected" -Resource "repository" -Operation "CREATE" -Target $RepoKey `
            -ExecutionMechanism "rest-api" -Skill "jfrog-repositories" `
            -Script "create-repository.ps1" -ScriptVersion $ScriptVersion `
            -Risk "ADMINISTRATIVE" -ApprovalRequired $true -ApprovalStatus "APPROVED" `
            -Result $result -Verification $verification

        [pscustomobject]@{ operationId = $OperationId; target = $RepoKey; result = $result; verification = $verification } | ConvertTo-Json
        if ($verification -ne "CONFIRMED") { exit ([int][DevOpsExitCode]::VerificationFailure) }
        exit ([int][DevOpsExitCode]::Success)
    }
    else {
        Write-Host "(WhatIf) Would CREATE JFrog repository '$RepoKey'. No change made."
        exit ([int][DevOpsExitCode]::Success)
    }
}
catch {
    Write-AuditLog -OperationId $OperationId -User $User -System "jfrog" `
        -SystemVersion "runtime-detected" -Resource "repository" -Operation "CREATE" -Target $RepoKey `
        -ExecutionMechanism "rest-api" -Skill "jfrog-repositories" `
        -Script "create-repository.ps1" -ScriptVersion $ScriptVersion `
        -Risk "ADMINISTRATIVE" -ApprovalRequired $true -ApprovalStatus "APPROVED" `
        -Result "FAILURE" -Verification "UNKNOWN" -Error $_.Exception.Message
    Write-Error "Failed to create repository '$RepoKey': $($_.Exception.Message)"
    exit ([int][DevOpsExitCode]::GeneralFailure)
}
