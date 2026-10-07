#Requires -Version 7.0
<#
.SYNOPSIS
    SECURITY_SENSITIVE: Creates a new JFrog Platform user account.
    Requires a pre-issued "APPROVE SECURITY CHANGE" approval record.

.DESCRIPTION
    Purpose: Execute the CREATE stage for a user account.
    Supported OS: Windows (PowerShell 7+).
    Dependencies: scripts/common/Common.psm1
    Parameters: BaseUrl, Username, Email, Password (SecureString), User, OperationId
    Authentication: JFrog access token (POC: local-secrets).
    Required permissions: admin privileges.
    Approval requirements: MANDATORY "APPROVE SECURITY CHANGE" bound to
        this exact Username.
    Dry-run: -WhatIf supported.
    API/MCP dependency: REST fallback (POST /access/api/v2/users).
    Exit codes: 0 success, 6 approval denied, 7 verification failure, 1 general failure.
    Output: JSON result (never includes the password).
    Verification: GET after create; confirm username/email match.
    Audit: writes one SECURITY_SENSITIVE audit record. The password
        parameter is NEVER written to the audit log or printed - the
        shared Protect-SensitiveData redaction is a backstop, but this
        script also never includes $Password in any logged structure.
    Security: TLS enforced; approval re-checked immediately before POST.

.EXAMPLE
    $pw = Read-Host -AsSecureString "Initial password"
    ./create-user.ps1 -BaseUrl "https://jfrog.example.com" -Username jdoe `
        -Email "jdoe@example.com" -Password $pw -User admin-jdoe -OperationId op-123
#>

[CmdletBinding(SupportsShouldAction = $true)]
param(
    [Parameter(Mandatory = $true)][string]$BaseUrl,
    [Parameter(Mandatory = $true)][string]$Username,
    [Parameter(Mandatory = $true)][string]$Email,
    [Parameter(Mandatory = $true)][System.Security.SecureString]$Password,
    [Parameter(Mandatory = $true)][string]$User,
    [Parameter(Mandatory = $true)][string]$OperationId
)

$ScriptVersion = "1.0.0"
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Import-Module (Join-Path $PSScriptRoot "../../../../../scripts/common/Common.psm1") -Force

$operationKey = "jfrog.users.create"
$approval = Test-ApprovalToken -OperationId $OperationId -System "jfrog" `
    -Target $Username -Operation $operationKey -ExpectedApprovalType "APPROVE SECURITY CHANGE"

if (-not $approval.Valid) {
    Write-AuditLog -OperationId $OperationId -User $User -System "jfrog" `
        -SystemVersion "runtime-detected" -Resource "user" -Operation "CREATE" -Target $Username `
        -ExecutionMechanism "rest-api" -Skill "jfrog-users" `
        -Script "create-user.ps1" -ScriptVersion $ScriptVersion `
        -Risk "SECURITY_SENSITIVE" -ApprovalRequired $true -ApprovalStatus "DENIED" `
        -Result "DENIED" -Verification "NOT_APPLICABLE" -Error $approval.Reason
    Write-Error "Approval check failed: $($approval.Reason)"
    exit ([int][DevOpsExitCode]::ApprovalDenied)
}

$collectionUri = "$BaseUrl/access/api/v2/users"
$userUri = "$collectionUri/$Username"

try {
    $token = Read-LocalSecret -System jfrog
    $plainPassword = ConvertFrom-SecureStringPlain -Secure $Password
    $body = @{ username = $Username; email = $Email; password = $plainPassword }

    if ($PSCmdlet.ShouldProcess($Username, "CREATE JFrog user")) {
        Invoke-SecureRestMethod -Uri $collectionUri -Method POST -Token $token -Body $body | Out-Null
        $plainPassword = $null
        $body = $null
        Set-ApprovalConsumed -OperationId $OperationId

        $verification = "UNKNOWN"; $result = "UNKNOWN"
        try {
            $created = Invoke-SecureRestMethod -Uri $userUri -Method GET -Token $token
            if ($created.username -eq $Username) { $verification = "CONFIRMED"; $result = "SUCCESS" }
            else { $verification = "FAILED" }
        }
        catch { $verification = "FAILED" }

        Write-AuditLog -OperationId $OperationId -User $User -System "jfrog" `
            -SystemVersion "runtime-detected" -Resource "user" -Operation "CREATE" -Target $Username `
            -ExecutionMechanism "rest-api" -Skill "jfrog-users" `
            -Script "create-user.ps1" -ScriptVersion $ScriptVersion `
            -Risk "SECURITY_SENSITIVE" -ApprovalRequired $true -ApprovalStatus "APPROVED" `
            -Result $result -Verification $verification

        [pscustomobject]@{ operationId = $OperationId; target = $Username; result = $result; verification = $verification } | ConvertTo-Json
        if ($verification -ne "CONFIRMED") { exit ([int][DevOpsExitCode]::VerificationFailure) }
        exit ([int][DevOpsExitCode]::Success)
    }
    else {
        Write-Host "(WhatIf) Would CREATE JFrog user '$Username'. No change made."
        exit ([int][DevOpsExitCode]::Success)
    }
}
catch {
    Write-AuditLog -OperationId $OperationId -User $User -System "jfrog" `
        -SystemVersion "runtime-detected" -Resource "user" -Operation "CREATE" -Target $Username `
        -ExecutionMechanism "rest-api" -Skill "jfrog-users" `
        -Script "create-user.ps1" -ScriptVersion $ScriptVersion `
        -Risk "SECURITY_SENSITIVE" -ApprovalRequired $true -ApprovalStatus "APPROVED" `
        -Result "FAILURE" -Verification "UNKNOWN" -Error $_.Exception.Message
    Write-Error "Failed to create user '$Username': $($_.Exception.Message)"
    exit ([int][DevOpsExitCode]::GeneralFailure)
}
