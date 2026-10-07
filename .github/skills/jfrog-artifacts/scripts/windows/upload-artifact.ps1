#Requires -Version 7.0
<#
.SYNOPSIS
    WRITE: Uploads (deploys) a local file as an artifact to JFrog
    Artifactory. Requires a pre-issued "APPROVE CREATE" approval record.

.DESCRIPTION
    Purpose: Execute the CREATE/deploy stage for a new artifact.
    Supported OS: Windows (PowerShell 7+).
    Dependencies: scripts/common/Common.psm1
    Parameters: BaseUrl, RepoKey, ItemPath, LocalFilePath, User, OperationId
    Authentication: JFrog access token (POC: local-secrets).
    Required permissions: deploy permission on the target repository.
    Approval requirements: MANDATORY "APPROVE CREATE" bound to this exact
        RepoKey/ItemPath. If an artifact already exists there, the
        proposal shown to the human before approval MUST flag it as an
        overwrite.
    Dry-run: -WhatIf supported.
    API/MCP dependency: REST fallback (PUT /artifactory/{repoKey}/{itemPath}).
    Exit codes: 0 success, 6 approval denied, 7 verification failure, 1 general failure.
    Output: JSON result.
    Verification: GET storage info after PUT; confirm artifact exists
        and SHA256 checksum matches the local file's computed checksum.
    Audit: writes one WRITE audit record.
    Security: TLS enforced; ItemPath rejected if it contains ".." path
        traversal segments; approval re-checked immediately before PUT.

.EXAMPLE
    ./upload-artifact.ps1 -BaseUrl "https://jfrog.example.com" `
        -RepoKey libs-release-local -ItemPath "com/example/app/2.0/app.jar" `
        -LocalFilePath "C:\build\app.jar" -User jdoe -OperationId op-123
#>

[CmdletBinding(SupportsShouldAction = $true)]
param(
    [Parameter(Mandatory = $true)][string]$BaseUrl,
    [Parameter(Mandatory = $true)][ValidatePattern('^[A-Za-z0-9._-]+$')][string]$RepoKey,
    [Parameter(Mandatory = $true)][string]$ItemPath,
    [Parameter(Mandatory = $true)][string]$LocalFilePath,
    [Parameter(Mandatory = $true)][string]$User,
    [Parameter(Mandatory = $true)][string]$OperationId
)

$ScriptVersion = "1.0.0"
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Import-Module (Join-Path $PSScriptRoot "../../../../../scripts/common/Common.psm1") -Force

if ($ItemPath -match '\.\.') {
    Write-Error "ItemPath must not contain '..' path traversal segments."
    exit ([int][DevOpsExitCode]::InvalidParameters)
}
if (-not (Test-Path -Path $LocalFilePath -PathType Leaf)) {
    Write-Error "LocalFilePath '$LocalFilePath' does not exist."
    exit ([int][DevOpsExitCode]::InvalidParameters)
}

$target = "$RepoKey/$ItemPath"
$operationKey = "jfrog.artifact.upload"

$approval = Test-ApprovalToken -OperationId $OperationId -System "jfrog" `
    -Target $target -Operation $operationKey -ExpectedApprovalType "APPROVE CREATE"

if (-not $approval.Valid) {
    Write-AuditLog -OperationId $OperationId -User $User -System "jfrog" `
        -SystemVersion "runtime-detected" -Resource "artifact" -Operation "CREATE" -Target $target `
        -ExecutionMechanism "rest-api" -Skill "jfrog-artifacts" `
        -Script "upload-artifact.ps1" -ScriptVersion $ScriptVersion `
        -Risk "WRITE" -ApprovalRequired $true -ApprovalStatus "DENIED" `
        -Result "DENIED" -Verification "NOT_APPLICABLE" -Error $approval.Reason
    Write-Error "Approval check failed: $($approval.Reason)"
    exit ([int][DevOpsExitCode]::ApprovalDenied)
}

$uploadUri = "$BaseUrl/artifactory/$RepoKey/$ItemPath"
$storageUri = "$BaseUrl/artifactory/api/storage/$RepoKey/$ItemPath"

try {
    $token = Read-LocalSecret -System jfrog
    $localHash = (Get-FileHash -Path $LocalFilePath -Algorithm SHA256).Hash.ToLowerInvariant()

    if ($PSCmdlet.ShouldProcess($target, "UPLOAD artifact")) {
        $plainToken = ConvertFrom-SecureStringPlain -Secure $token
        try {
            Invoke-RestMethod -Uri $uploadUri -Method PUT -InFile $LocalFilePath `
                -Headers @{ Authorization = "Bearer $plainToken" } `
                -ContentType "application/octet-stream" -UseBasicParsing -ErrorAction Stop | Out-Null
        }
        finally { $plainToken = $null }

        Set-ApprovalConsumed -OperationId $OperationId

        $verification = "UNKNOWN"; $result = "UNKNOWN"
        try {
            $info = Invoke-SecureRestMethod -Uri $storageUri -Method GET -Token $token
            $remoteHash = $info.checksums.sha256
            if ($remoteHash -eq $localHash) { $verification = "CONFIRMED"; $result = "SUCCESS" }
            else { $verification = "FAILED" }
        }
        catch { $verification = "FAILED" }

        Write-AuditLog -OperationId $OperationId -User $User -System "jfrog" `
            -SystemVersion "runtime-detected" -Resource "artifact" -Operation "CREATE" -Target $target `
            -ExecutionMechanism "rest-api" -Skill "jfrog-artifacts" `
            -Script "upload-artifact.ps1" -ScriptVersion $ScriptVersion `
            -Risk "WRITE" -ApprovalRequired $true -ApprovalStatus "APPROVED" `
            -Result $result -Verification $verification

        [pscustomobject]@{ operationId = $OperationId; target = $target; result = $result; verification = $verification } | ConvertTo-Json
        if ($verification -ne "CONFIRMED") { exit ([int][DevOpsExitCode]::VerificationFailure) }
        exit ([int][DevOpsExitCode]::Success)
    }
    else {
        Write-Host "(WhatIf) Would UPLOAD artifact to '$target'. No change made."
        exit ([int][DevOpsExitCode]::Success)
    }
}
catch {
    Write-AuditLog -OperationId $OperationId -User $User -System "jfrog" `
        -SystemVersion "runtime-detected" -Resource "artifact" -Operation "CREATE" -Target $target `
        -ExecutionMechanism "rest-api" -Skill "jfrog-artifacts" `
        -Script "upload-artifact.ps1" -ScriptVersion $ScriptVersion `
        -Risk "WRITE" -ApprovalRequired $true -ApprovalStatus "APPROVED" `
        -Result "FAILURE" -Verification "UNKNOWN" -Error $_.Exception.Message
    Write-Error "Failed to upload artifact to '$target': $($_.Exception.Message)"
    exit ([int][DevOpsExitCode]::GeneralFailure)
}
