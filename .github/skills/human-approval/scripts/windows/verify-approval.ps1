#Requires -Version 7.0
<#
.SYNOPSIS
    Verifies that a presented operationId has a valid, matching,
    unconsumed approval record before an executing skill is allowed to
    proceed. Exits non-zero (and prints nothing but the reason) if not.

.DESCRIPTION
    Purpose: Gate function for EXECUTE-stage scripts across every skill.
    Supported OS: Windows (PowerShell 7+).
    Dependencies: scripts/common/Common.psm1
    Authentication: none (local approval-record store only).
    Required permissions: read access to logs/.approvals/.
    Approval requirements: N/A - this script performs verification, not approval.
    Dry-run: not applicable (read-only).
    API/MCP dependency: none.
    Exit codes: 0 = valid approval, 6 = approval missing/invalid/denied,
        2 = invalid parameters.
    Output: "VALID" + JSON record on stdout when valid; reason to stderr
        when invalid.
    Verification: this IS the verification step.
    Audit: does not itself write an audit record (caller does).
    Security: validates HMAC signature and exact target/operation binding.

.PARAMETER OperationId
.PARAMETER System
.PARAMETER Target
.PARAMETER Operation
.PARAMETER ExpectedApprovalType

.EXAMPLE
    ./verify-approval.ps1 -OperationId op-abc123 -System bitbucket `
        -Target "ABC/TEST" -Operation "bitbucket.repository.delete" `
        -ExpectedApprovalType "APPROVE DELETE"
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$OperationId,
    [Parameter(Mandatory = $true)][string]$System,
    [Parameter(Mandatory = $true)][string]$Target,
    [Parameter(Mandatory = $true)][string]$Operation,
    [Parameter(Mandatory = $true)][string]$ExpectedApprovalType
)

$ScriptVersion = "1.0.0"
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Import-Module (Join-Path $PSScriptRoot "../../../../../scripts/common/Common.psm1") -Force

$result = Test-ApprovalToken -OperationId $OperationId -System $System -Target $Target `
    -Operation $Operation -ExpectedApprovalType $ExpectedApprovalType

if ($result.Valid) {
    Write-Output "VALID"
    $result.Record | ConvertTo-Json
    exit ([int][DevOpsExitCode]::Success)
}
else {
    Write-Error "INVALID: $($result.Reason)"
    exit ([int][DevOpsExitCode]::ApprovalDenied)
}
