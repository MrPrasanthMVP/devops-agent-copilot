#Requires -Version 7.0
<#
.SYNOPSIS
    Prints the PROPOSED OPERATION block and stages a PENDING proposal
    (NOT yet a valid approval -- Test-ApprovalToken will not accept it)
    so that confirm-approval.ps1 can later mint the canonical
    HMAC-signed approval token via Common.psm1's New-ApprovalToken once
    the human types the exact required phrase.

.DESCRIPTION
    Purpose:        Issue an operation-bound approval proposal.
    Supported OS:   Windows (PowerShell 7+).
    Dependencies:   scripts/common/Common.psm1
    Authentication: None (local bookkeeping only).
    Required permissions: Write access to the repository working copy
                    (creates files under .proposals/).
    Approval requirements: N/A -- this script PROPOSES; it never
                    produces a usable approval token by itself.
    Dry-run:        -WhatIf prints the block without persisting the
                    staged proposal.
    API/MCP dependency: None.
    Exit codes:     0 success, 1 general failure, 2 invalid parameters.
    Output:         JSON: { operationId, approvalType, expiresAfterSeconds }
    Verification:   N/A -- confirm-approval.ps1 is the next step.
    Audit:          Appends a REQUEST_APPROVAL audit record via Write-AuditLog.
    Security:       No credentials handled. No network calls. The
                    staged proposal is NOT a signed token and is
                    rejected by Test-ApprovalToken if presented as one.

.EXAMPLE
    ./request-approval.ps1 -System bitbucket -Target "PROJ/TEST" `
        -OperationKey "bitbucket.repository.delete" -Risk DESTRUCTIVE `
        -ApprovalType "APPROVE DELETE" -CurrentState "exists, 42 commits" `
        -ProposedState "permanently deleted" -Impact "Permanent repository deletion." `
        -RequestedBy "jdoe"
#>

[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $true)][ValidateSet('bitbucket', 'jira', 'confluence', 'jfrog', 'github')]
    [string]$System,

    [Parameter(Mandatory = $true)][string]$Target,
    [Parameter(Mandatory = $true)][string]$OperationKey,

    [Parameter(Mandatory = $true)][ValidateSet('READ_ONLY', 'WRITE', 'DESTRUCTIVE', 'ADMINISTRATIVE', 'SECURITY_SENSITIVE')]
    [string]$Risk,

    [Parameter(Mandatory = $true)][string]$ApprovalType,
    [Parameter(Mandatory = $true)][string]$CurrentState,
    [Parameter(Mandatory = $true)][string]$ProposedState,
    [Parameter(Mandatory = $true)][string]$Impact,

    [string]$RequestedBy = $env:USERNAME,
    [int]$ExpiresAfterSeconds = 900
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ScriptVersion = '1.0.0'

Import-Module (Join-Path $PSScriptRoot "../../../../../scripts/common/Common.psm1") -Force

try {
    $repoRoot = Get-RepoRoot
    $proposalsDir = Join-Path $repoRoot '.proposals'
    if (-not (Test-Path $proposalsDir)) { New-Item -ItemType Directory -Path $proposalsDir -Force | Out-Null }

    $operationId = New-OperationId
    $timestamp = (Get-Date).ToUniversalTime().ToString('o')

    $proposal = [ordered]@{
        operationId         = $operationId
        user                = $RequestedBy
        system              = $System
        target              = $Target
        operationKey        = $OperationKey
        risk                = $Risk
        approvalType        = $ApprovalType
        currentState        = $CurrentState
        proposedState       = $ProposedState
        impact              = $Impact
        requestedAt         = $timestamp
        expiresAfterSeconds = $ExpiresAfterSeconds
    }

    Write-Host ''
    Write-Host 'PROPOSED OPERATION' -ForegroundColor Yellow
    Write-Host ''
    Write-Host "System:          $System"
    Write-Host "Target:          $Target"
    Write-Host "Operation:       $OperationKey"
    Write-Host "Current state:   $CurrentState"
    Write-Host "Proposed state:  $ProposedState"
    Write-Host "Risk:            $Risk"
    Write-Host "Impact:          $Impact"
    Write-Host ''
    Write-Host "Explicit approval required. Type: $ApprovalType"
    Write-Host "(operationId: $operationId, expires in $ExpiresAfterSeconds s)"
    Write-Host ''

    if ($PSCmdlet.ShouldProcess($Target, "Stage PENDING proposal $operationId")) {
        $proposalPath = Join-Path $proposalsDir "$operationId.json"
        ($proposal | ConvertTo-Json -Depth 6) | Set-Content -Path $proposalPath -Encoding utf8

        Write-AuditLog -OperationId $operationId -User $RequestedBy -System $System `
            -SystemVersion 'n/a' -Resource 'proposal' -Operation 'REQUEST_APPROVAL' -Target $Target `
            -ExecutionMechanism 'none' -Skill 'human-approval' -Script 'scripts/windows/request-approval.ps1' `
            -ScriptVersion $ScriptVersion -Risk $Risk -ApprovalRequired $true -ApprovalStatus 'PENDING' `
            -Result 'SUCCESS' -Verification 'NOT_APPLICABLE'

        [ordered]@{
            operationId         = $operationId
            approvalType        = $ApprovalType
            expiresAfterSeconds = $ExpiresAfterSeconds
        } | ConvertTo-Json -Compress
    }
    else {
        Write-Host "(WhatIf) No proposal staged."
    }

    exit ([int][DevOpsExitCode]::Success)
}
catch {
    Write-Error "request-approval failed: $($_.Exception.Message)"
    exit ([int][DevOpsExitCode]::GeneralFailure)
}
