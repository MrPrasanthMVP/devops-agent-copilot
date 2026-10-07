#Requires -Version 7.0
<#
.SYNOPSIS
    Validates the human's literal response against the staged proposal's
    expected approval phrase, and, if (and only if) it matches exactly,
    mints the canonical HMAC-signed approval token via Common.psm1's
    New-ApprovalToken -- the record every execution script's
    Test-ApprovalToken call will accept.

.DESCRIPTION
    Purpose:        Second half of the approval gate: turns a human
                    utterance into a bound, signed APPROVED token, or a
                    recorded denial.
    Supported OS:   Windows (PowerShell 7+).
    Dependencies:   scripts/common/Common.psm1
    Authentication: None (local bookkeeping only).
    Approval requirements: N/A (this IS the approval mechanism).
    Exit codes:     0 approved, 1 general failure, 2 invalid parameters,
                    6 approval denied / phrase did not match,
                    7 proposal expired, 8 operationId not found.
    Output:         JSON object describing the outcome.
    Verification:   Re-run with verify-approval.ps1 (or any script's
                    Test-ApprovalToken call) before executing.
    Audit:          Appends a CONFIRM_APPROVAL audit record.
    Security:       Rejects generic affirmations ("yes","ok","sure",
                    "do it","go ahead","proceed","fine","confirm",
                    "approved") as insufficient for anything other than
                    an exact phrase match.

.EXAMPLE
    ./confirm-approval.ps1 -OperationId "op-xxxx" -ApprovalPhraseReceived "APPROVE DELETE" -ApprovedBy "jdoe"
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$OperationId,
    [Parameter(Mandatory = $true)][string]$ApprovalPhraseReceived,
    [string]$ApprovedBy = $env:USERNAME
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ScriptVersion = '1.0.0'

Import-Module (Join-Path $PSScriptRoot "../../../../../scripts/common/Common.psm1") -Force

$InsufficientTokens = @('yes', 'ok', 'okay', 'sure', 'do it', 'go ahead', 'proceed', 'fine', 'confirm', 'approved')

try {
    $repoRoot = Get-RepoRoot
    $proposalPath = Join-Path $repoRoot ".proposals/$OperationId.json"
    if (-not (Test-Path $proposalPath)) {
        Write-Error "Unknown or already-confirmed operationId: $OperationId"
        exit ([int][DevOpsExitCode]::TargetNotFound)
    }

    $proposal = Get-Content $proposalPath -Raw | ConvertFrom-Json

    $requestedAt = [datetime]::Parse($proposal.requestedAt).ToUniversalTime()
    $ageSeconds = ((Get-Date).ToUniversalTime() - $requestedAt).TotalSeconds
    if ($ageSeconds -gt $proposal.expiresAfterSeconds) {
        Remove-Item $proposalPath -Force
        Write-Error "Proposal $OperationId has EXPIRED ($([int]$ageSeconds)s old, limit $($proposal.expiresAfterSeconds)s). Re-propose the operation."
        exit ([int][DevOpsExitCode]::VerificationFailure)
    }

    $normalizedReceived = $ApprovalPhraseReceived.Trim()
    $expected = $proposal.approvalType
    $status = 'DENIED'

    if ($normalizedReceived -ceq $expected) {
        $status = 'APPROVED'
    }
    elseif ($InsufficientTokens -contains $normalizedReceived.ToLowerInvariant()) {
        Write-Warning "Generic affirmation '$normalizedReceived' is not sufficient. Exact phrase required: '$expected'"
    }

    if ($status -eq 'APPROVED') {
        $token = New-ApprovalToken -OperationId $OperationId -User $ApprovedBy -System $proposal.system `
            -Target $proposal.target -Operation $proposal.operationKey -Risk $proposal.risk -ApprovalType $expected
        Remove-Item $proposalPath -Force

        Write-AuditLog -OperationId $OperationId -User $ApprovedBy -System $proposal.system `
            -SystemVersion 'n/a' -Resource 'proposal' -Operation 'CONFIRM_APPROVAL' -Target $proposal.target `
            -ExecutionMechanism 'none' -Skill 'human-approval' -Script 'scripts/windows/confirm-approval.ps1' `
            -ScriptVersion $ScriptVersion -Risk $proposal.risk -ApprovalRequired $true -ApprovalStatus 'APPROVED' `
            -Result 'SUCCESS' -Verification 'NOT_APPLICABLE'

        $token | ConvertTo-Json -Compress
        exit ([int][DevOpsExitCode]::Success)
    }
    else {
        Write-AuditLog -OperationId $OperationId -User $ApprovedBy -System $proposal.system `
            -SystemVersion 'n/a' -Resource 'proposal' -Operation 'CONFIRM_APPROVAL' -Target $proposal.target `
            -ExecutionMechanism 'none' -Skill 'human-approval' -Script 'scripts/windows/confirm-approval.ps1' `
            -ScriptVersion $ScriptVersion -Risk $proposal.risk -ApprovalRequired $true -ApprovalStatus 'DENIED' `
            -Result 'DENIED' -Verification 'NOT_APPLICABLE'

        [ordered]@{ operationId = $OperationId; status = 'DENIED'; receivedPhrase = $normalizedReceived; expectedPhrase = $expected } | ConvertTo-Json -Compress
        exit ([int][DevOpsExitCode]::ApprovalDenied)
    }
}
catch {
    Write-Error "confirm-approval failed: $($_.Exception.Message)"
    exit ([int][DevOpsExitCode]::GeneralFailure)
}
