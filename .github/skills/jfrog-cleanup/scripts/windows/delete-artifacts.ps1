#Requires -Version 7.0
<#
.SYNOPSIS
    DESTRUCTIVE: Deletes a batch of previously-proposed candidate
    artifacts from one Artifactory repository. Requires a single
    pre-issued "APPROVE DELETE" approval bound to this exact repository,
    covering exactly the candidate set the agent showed the human in
    the PROPOSED OPERATION (Section 20's find -> summarize -> approve
    -> delete pipeline). The caller (the agent) MUST pass the identical
    CandidatePaths list that was shown and approved -- this script does
    not independently re-derive "which artifacts were approved" beyond
    trusting that list, so the calling Skill/agent is the trust boundary
    for batch-membership; per-repository binding still prevents an
    approval for repository A being used against repository B.

.DESCRIPTION
    Purpose: Execute the DELETE stage for a batch cleanup operation.
    Supported OS: Windows (PowerShell 7+).
    Dependencies: scripts/common/Common.psm1
    Parameters: BaseUrl, Repository, CandidatePaths (string[]), User, OperationId
    Authentication: JFrog access token (POC: local-secrets).
    Required permissions: Delete permission on the target repository.
    Approval requirements: MANDATORY "APPROVE DELETE" bound to this
        exact Repository.
    Dry-run: -WhatIf supported.
    API/MCP dependency: REST fallback
        (DELETE /artifactory/{repo-key}/{item-path}, once per path).
    Exit codes: 0 success, 6 approval denied, 7 verification failure
        (any path not confirmed deleted), 1 general failure.
    Output: JSON result summary (per-path + overall).
    Verification: GET after each DELETE; expect HTTP 404 for every path.
    Audit: writes one DESTRUCTIVE audit record per deleted path.
    Security: TLS enforced; approval re-checked immediately before the
        batch executes; path values validated against traversal.

.EXAMPLE
    ./delete-artifacts.ps1 -BaseUrl "https://jfrog.example.com" `
        -Repository releases-local -CandidatePaths @("com/example/app/1.0/app.jar") `
        -User jdoe -OperationId op-123
#>

[CmdletBinding(SupportsShouldAction = $true)]
param(
    [Parameter(Mandatory = $true)][string]$BaseUrl,
    [Parameter(Mandatory = $true)][ValidatePattern('^[A-Za-z0-9_.-]+$')][string]$Repository,
    [Parameter(Mandatory = $true)][string[]]$CandidatePaths,
    [Parameter(Mandatory = $true)][string]$User,
    [Parameter(Mandatory = $true)][string]$OperationId
)

$ScriptVersion = "1.0.0"
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Import-Module (Join-Path $PSScriptRoot "../../../../../scripts/common/Common.psm1") -Force

foreach ($p in $CandidatePaths) {
    if ($p -match '\.\.') {
        Write-Error "Path traversal detected in candidate path '$p'. Refusing to proceed."
        exit ([int][DevOpsExitCode]::InvalidParameters)
    }
}

$operationKey = "jfrog.artifact.delete"
$approval = Test-ApprovalToken -OperationId $OperationId -System "jfrog" `
    -Target $Repository -Operation $operationKey -ExpectedApprovalType "APPROVE DELETE"

if (-not $approval.Valid) {
    Write-AuditLog -OperationId $OperationId -User $User -System "jfrog" `
        -SystemVersion "runtime-detected" -Resource "artifact" -Operation "DELETE" -Target $Repository `
        -ExecutionMechanism "rest-api" -Skill "jfrog-cleanup" `
        -Script "delete-artifacts.ps1" -ScriptVersion $ScriptVersion `
        -Risk "DESTRUCTIVE" -ApprovalRequired $true -ApprovalStatus "DENIED" `
        -Result "DENIED" -Verification "NOT_APPLICABLE" -Error $approval.Reason
    Write-Error "Approval check failed: $($approval.Reason)"
    exit ([int][DevOpsExitCode]::ApprovalDenied)
}

try {
    $token = Read-LocalSecret -System jfrog
    $results = @()
    $allConfirmed = $true

    if ($PSCmdlet.ShouldProcess("$Repository (x$($CandidatePaths.Count) artifacts)", "DELETE batch")) {
        foreach ($path in $CandidatePaths) {
            $target = "$Repository/$path"
            $uri = "$BaseUrl/artifactory/$Repository/$path"
            $verification = "UNKNOWN"; $result = "UNKNOWN"; $errorMsg = $null

            try {
                Invoke-SecureRestMethod -Uri $uri -Method DELETE -Token $token | Out-Null
                try {
                    Invoke-SecureRestMethod -Uri $uri -Method GET -Token $token | Out-Null
                    $verification = "FAILED"
                }
                catch {
                    $verification = "CONFIRMED"; $result = "SUCCESS"
                }
            }
            catch {
                $errorMsg = $_.Exception.Message
                $verification = "UNKNOWN"
            }

            if ($verification -ne "CONFIRMED") { $allConfirmed = $false }

            Write-AuditLog -OperationId $OperationId -User $User -System "jfrog" `
                -SystemVersion "runtime-detected" -Resource "artifact" -Operation "DELETE" -Target $target `
                -ExecutionMechanism "rest-api" -Skill "jfrog-cleanup" `
                -Script "delete-artifacts.ps1" -ScriptVersion $ScriptVersion `
                -Risk "DESTRUCTIVE" -ApprovalRequired $true -ApprovalStatus "APPROVED" `
                -Result $result -Verification $verification -Error $errorMsg

            $results += [ordered]@{ target = $target; result = $result; verification = $verification }
        }

        Set-ApprovalConsumed -OperationId $OperationId

        [ordered]@{ repository = $Repository; count = $CandidatePaths.Count; results = $results; overallResult = $(if ($allConfirmed) {"SUCCESS"} else {"UNKNOWN"}) } | ConvertTo-Json -Depth 6
        if (-not $allConfirmed) { exit ([int][DevOpsExitCode]::VerificationFailure) }
        exit ([int][DevOpsExitCode]::Success)
    }
    else {
        Write-Host "(WhatIf) Would DELETE $($CandidatePaths.Count) artifact(s) from repository '$Repository'. No change made."
        exit ([int][DevOpsExitCode]::Success)
    }
}
catch {
    Write-Error "delete-artifacts failed: $($_.Exception.Message)"
    exit ([int][DevOpsExitCode]::GeneralFailure)
}
