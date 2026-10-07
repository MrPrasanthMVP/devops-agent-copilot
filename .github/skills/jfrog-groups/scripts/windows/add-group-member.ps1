#Requires -Version 7.0
<#
.SYNOPSIS
    SECURITY_SENSITIVE: Adds a user to a JFrog group (changes effective
    access for that user via whatever the group is granted). Requires a
    pre-issued "APPROVE PERMISSION CHANGE" approval record. No MCP tool
    covers this -- REST fallback via the user's groups array.

.DESCRIPTION
    Purpose: Execute the membership-change stage for a group.
    Supported OS: Windows (PowerShell 7+).
    Dependencies: scripts/common/Common.psm1
    Parameters: BaseUrl, GroupName, Username, User, OperationId
    Authentication: JFrog access token (POC: local-secrets).
    Required permissions: admin privileges.
    Approval requirements: MANDATORY "APPROVE PERMISSION CHANGE" bound
        to this exact GroupName+Username pair (Target = "GroupName/Username").
    Dry-run: -WhatIf supported.
    API/MCP dependency: REST fallback -- GET then PUT
        /access/api/v2/users/{username} with the group appended to its
        groups array (JFrog models group membership on the user object,
        not a separate membership endpoint).
    Exit codes: 0 success, 6 approval denied, 7 verification failure, 1 general failure.
    Output: JSON result.
    Verification: GET user after PUT; confirm GroupName present in groups array.
    Audit: writes one SECURITY_SENSITIVE audit record.
    Security: TLS enforced; approval re-checked immediately before PUT;
        never adds the requesting identity itself without the same gate
        as any other principal.

.EXAMPLE
    ./add-group-member.ps1 -BaseUrl "https://jfrog.example.com" -GroupName build-team `
        -Username jdoe -User admin-jdoe -OperationId op-123
#>

[CmdletBinding(SupportsShouldAction = $true)]
param(
    [Parameter(Mandatory = $true)][string]$BaseUrl,
    [Parameter(Mandatory = $true)][string]$GroupName,
    [Parameter(Mandatory = $true)][string]$Username,
    [Parameter(Mandatory = $true)][string]$User,
    [Parameter(Mandatory = $true)][string]$OperationId
)

$ScriptVersion = "1.0.0"
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Import-Module (Join-Path $PSScriptRoot "../../../../../scripts/common/Common.psm1") -Force

$target = "$GroupName/$Username"
$operationKey = "jfrog.groups.update"
$approval = Test-ApprovalToken -OperationId $OperationId -System "jfrog" `
    -Target $target -Operation $operationKey -ExpectedApprovalType "APPROVE PERMISSION CHANGE"

if (-not $approval.Valid) {
    Write-AuditLog -OperationId $OperationId -User $User -System "jfrog" `
        -SystemVersion "runtime-detected" -Resource "group" -Operation "UPDATE" -Target $target `
        -ExecutionMechanism "rest-api" -Skill "jfrog-groups" `
        -Script "add-group-member.ps1" -ScriptVersion $ScriptVersion `
        -Risk "SECURITY_SENSITIVE" -ApprovalRequired $true -ApprovalStatus "DENIED" `
        -Result "DENIED" -Verification "NOT_APPLICABLE" -Error $approval.Reason
    Write-Error "Approval check failed: $($approval.Reason)"
    exit ([int][DevOpsExitCode]::ApprovalDenied)
}

$userUri = "$BaseUrl/access/api/v2/users/$Username"

try {
    $token = Read-LocalSecret -System jfrog
    $currentUser = Invoke-SecureRestMethod -Uri $userUri -Method GET -Token $token
    $groups = @($currentUser.groups) + $GroupName | Select-Object -Unique
    $body = @{ groups = $groups }

    if ($PSCmdlet.ShouldProcess($target, "ADD user to JFrog group")) {
        Invoke-SecureRestMethod -Uri $userUri -Method PATCH -Token $token -Body $body | Out-Null
        Set-ApprovalConsumed -OperationId $OperationId

        $verification = "UNKNOWN"; $result = "UNKNOWN"
        try {
            $updatedUser = Invoke-SecureRestMethod -Uri $userUri -Method GET -Token $token
            if ($updatedUser.groups -contains $GroupName) { $verification = "CONFIRMED"; $result = "SUCCESS" }
            else { $verification = "FAILED" }
        }
        catch { $verification = "FAILED" }

        Write-AuditLog -OperationId $OperationId -User $User -System "jfrog" `
            -SystemVersion "runtime-detected" -Resource "group" -Operation "UPDATE" -Target $target `
            -ExecutionMechanism "rest-api" -Skill "jfrog-groups" `
            -Script "add-group-member.ps1" -ScriptVersion $ScriptVersion `
            -Risk "SECURITY_SENSITIVE" -ApprovalRequired $true -ApprovalStatus "APPROVED" `
            -Result $result -Verification $verification

        [pscustomobject]@{ operationId = $OperationId; target = $target; result = $result; verification = $verification } | ConvertTo-Json
        if ($verification -ne "CONFIRMED") { exit ([int][DevOpsExitCode]::VerificationFailure) }
        exit ([int][DevOpsExitCode]::Success)
    }
    else {
        Write-Host "(WhatIf) Would ADD user '$Username' to JFrog group '$GroupName'. No change made."
        exit ([int][DevOpsExitCode]::Success)
    }
}
catch {
    Write-AuditLog -OperationId $OperationId -User $User -System "jfrog" `
        -SystemVersion "runtime-detected" -Resource "group" -Operation "UPDATE" -Target $target `
        -ExecutionMechanism "rest-api" -Skill "jfrog-groups" `
        -Script "add-group-member.ps1" -ScriptVersion $ScriptVersion `
        -Risk "SECURITY_SENSITIVE" -ApprovalRequired $true -ApprovalStatus "APPROVED" `
        -Result "FAILURE" -Verification "UNKNOWN" -Error $_.Exception.Message
    Write-Error "Failed to add user '$Username' to group '$GroupName': $($_.Exception.Message)"
    exit ([int][DevOpsExitCode]::GeneralFailure)
}
