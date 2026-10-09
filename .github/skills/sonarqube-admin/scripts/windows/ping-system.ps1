#Requires -Version 7.0
<#
.SYNOPSIS
    READ_ONLY: Verifies a SonarQube Server instance is operational.
    Server/Community Build ONLY -- SonarQube Cloud has no equivalent
    self-reported ping endpoint (it is a managed SaaS instance).

.DESCRIPTION
    Purpose: Liveness check (GET, no mutation, no authentication required
        by the endpoint itself -- a token is still passed for parity
        with every other script in this framework and to avoid an
        unauthenticated-call code path).
    Supported OS: Windows (PowerShell 7+), cross-platform compatible.
    Dependencies: scripts/common/Common.psm1 (Invoke-SecureRestMethod, Write-AuditLog)
    Parameters: BaseUrl, User
    Authentication: SonarQube user token, read via Read-LocalSecret (POC).
    Required permissions: None (public liveness endpoint).
    Approval requirements: NONE - READ_ONLY operations execute immediately.
    Deployment: Server/Community Build ONLY. Do not call this against
        SonarQube Cloud.
    API/MCP dependency: REST fallback used here; prefer the SonarQube MCP
        server's ping_system tool when available (see SKILL.md).
    Exit codes: 0 success, 1 general failure.
    Output: { "ping": "pong" } JSON object on stdout (the raw endpoint
        response is the plain-text string "pong"; wrapped here for
        output consistency with every other script in this framework).
    Verification: N/A (this script IS a read, not something to verify).
    Audit: writes one READ audit record.
    Security: TLS verification enforced; token never logged or printed.

.EXAMPLE
    ./ping-system.ps1 -BaseUrl "https://sonarqube.example.internal" -User jdoe
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$BaseUrl,
    [Parameter(Mandatory = $true)][string]$User
)

$ScriptVersion = "1.0.0"
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Import-Module (Join-Path $PSScriptRoot "../../../../../scripts/common/Common.psm1") -Force

$operationId = New-OperationId
$target = "server-ping"
$uri = "$BaseUrl/api/system/ping"

try {
    $token = Read-LocalSecret -System sonarqube
    $pong = Invoke-SecureRestMethod -Uri $uri -Method GET -Token $token

    Write-AuditLog -OperationId $operationId -User $User -System "sonarqube" `
        -SystemVersion "runtime-detected" -Resource "system" -Operation "PING" -Target $target `
        -ExecutionMechanism "rest-api" -Skill "sonarqube-admin" `
        -Script "ping-system.ps1" -ScriptVersion $ScriptVersion `
        -Risk "READ_ONLY" -ApprovalRequired $false -ApprovalStatus "NOT_REQUIRED" `
        -Result "SUCCESS" -Verification "NOT_APPLICABLE"

    [pscustomobject]@{ ping = [string]$pong } | ConvertTo-Json
    exit ([int][DevOpsExitCode]::Success)
}
catch {
    Write-AuditLog -OperationId $operationId -User $User -System "sonarqube" `
        -SystemVersion "runtime-detected" -Resource "system" -Operation "PING" -Target $target `
        -ExecutionMechanism "rest-api" -Skill "sonarqube-admin" `
        -Script "ping-system.ps1" -ScriptVersion $ScriptVersion `
        -Risk "READ_ONLY" -ApprovalRequired $false -ApprovalStatus "NOT_REQUIRED" `
        -Result "FAILURE" -Verification "NOT_APPLICABLE" -Error $_.Exception.Message

    Write-Error "Failed to ping SonarQube server: $($_.Exception.Message)"
    exit ([int][DevOpsExitCode]::GeneralFailure)
}
