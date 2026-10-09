#Requires -Version 7.0
<#
    Common.psm1
    Shared PowerShell helper library for the Enterprise DevOps Copilot
    Control Framework. Every operational script under
    .github/skills/*/scripts/windows/*.ps1 dot-sources or imports this
    module so that approval verification, audit logging, exit-code
    semantics, and secure HTTP behavior are IDENTICAL across every skill.

    Do not duplicate this logic inside individual skill scripts.
    Do not weaken any security control in this file to make a single
    skill's script "work" - fix the caller instead.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$script:CommonVersion = "1.0.0"

# ----------------------------------------------------------------------------
# Section 31 - Standard exit codes (must match scripts/common/common.sh)
# ----------------------------------------------------------------------------
enum DevOpsExitCode {
    Success               = 0
    GeneralFailure        = 1
    InvalidParameters     = 2
    AuthenticationFailure = 3
    AuthorizationFailure  = 4
    ApprovalRequired      = 5
    ApprovalDenied        = 6
    VerificationFailure   = 7
    TargetNotFound        = 8
    UnsupportedOperation  = 9
    ConfigurationError    = 10
}

function Get-RepoRoot {
    <#
        Resolves the repository root by walking upward from this module's
        location until a directory containing "policies" is found.
    #>
    $dir = Split-Path -Parent $PSScriptRoot
    $dir = Split-Path -Parent $dir
    return $dir
}

# ----------------------------------------------------------------------------
# Operation identity
# ----------------------------------------------------------------------------
function New-OperationId {
    <#
        Generates a unique, non-guessable operation identifier used to bind
        a proposal, an approval, an execution, and an audit record together.
    #>
    $guid = [guid]::NewGuid().ToString("N").Substring(0, 12)
    return "op-$guid"
}

# ----------------------------------------------------------------------------
# Secret handling (Section 11 / 27 / 35 - never print, never log credentials)
# ----------------------------------------------------------------------------
$script:SensitiveKeyPattern = '(?i)(password|token|secret|authorization|cookie|private[_-]?key|client[_-]?secret|refresh[_-]?token|api[_-]?key)'

function Read-LocalSecret {
    <#
        .SYNOPSIS
        Reads a POC-only local secret file from .github/local-secrets/.

        .DESCRIPTION
        This function exists ONLY for the local proof-of-concept auth path
        described in requirement.md Section 11. Production deployments must
        replace calls to this function with an enterprise credential broker,
        secret manager, managed identity, or OAuth/OIDC token exchange
        (Section 12). The returned value is a SecureString and is never
        written to the console, a log file, or an audit record.
    #>
    param(
        [Parameter(Mandatory = $true)][ValidateSet('bitbucket', 'jfrog', 'github', 'sonarqube')]
        [string]$System
    )

    $root = Get-RepoRoot
    $path = Join-Path $root ".github/local-secrets/$System-token.txt"

    if (-not (Test-Path -Path $path -PathType Leaf)) {
        Write-Error "Local secret file not found for '$System'. Copy .github/local-secrets/$System-token.txt.example to $System-token.txt and populate it. This is a POC-only mechanism - see SECURITY.md and README.md 'Production Hardening'."
        exit ([int][DevOpsExitCode]::ConfigurationError)
    }

    $raw = (Get-Content -Path $path -Raw -ErrorAction Stop).Trim()
    if ([string]::IsNullOrWhiteSpace($raw) -or $raw -like "REPLACE_WITH_*") {
        Write-Error "Local secret file for '$System' has not been populated with a real credential."
        exit ([int][DevOpsExitCode]::ConfigurationError)
    }

    return (ConvertTo-SecureString -String $raw -AsPlainText -Force)
}

function ConvertFrom-SecureStringPlain {
    <#
        Narrow, local-only conversion back to plain text immediately before
        use in an Authorization header. The plain value must never be
        assigned to a variable that is later logged, printed, or returned.
    #>
    param([Parameter(Mandatory = $true)][System.Security.SecureString]$Secure)
    $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($Secure)
    try {
        return [System.Runtime.InteropServices.Marshal]::PtrToStringUni($bstr)
    }
    finally {
        [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
    }
}

function Protect-SensitiveData {
    <#
        Recursively redacts keys matching the sensitive-key pattern from a
        hashtable/object graph before it is ever written to an audit record
        or console. Used as a defense-in-depth backstop in addition to
        never placing secrets into these structures in the first place.
    #>
    param([Parameter(Mandatory = $true)]$InputObject)

    if ($null -eq $InputObject) { return $InputObject }

    if ($InputObject -is [System.Collections.IDictionary]) {
        $clone = @{}
        foreach ($key in $InputObject.Keys) {
            if ($key -match $script:SensitiveKeyPattern) {
                $clone[$key] = "***REDACTED***"
            }
            else {
                $clone[$key] = Protect-SensitiveData -InputObject $InputObject[$key]
            }
        }
        return $clone
    }

    if ($InputObject -is [System.Collections.IEnumerable] -and -not ($InputObject -is [string])) {
        return @($InputObject | ForEach-Object { Protect-SensitiveData -InputObject $_ })
    }

    return $InputObject
}

# ----------------------------------------------------------------------------
# Approval token binding (Section 32 - approval must bind to exact operation)
# ----------------------------------------------------------------------------
function New-ApprovalToken {
    <#
        .SYNOPSIS
        Creates a framework-issued approval record bound to one specific
        operation. This is produced by the human-approval skill after a
        human has explicitly typed an APPROVE <TYPE> response - never from
        a generic "yes"/"ok"/"proceed" and never from the original request.

        The token is an HMAC-signed JSON blob. Signing uses a POC-local key
        stored outside source control; production must use the same
        credential-broker path described for other secrets.
    #>
    param(
        [Parameter(Mandatory = $true)][string]$OperationId,
        [Parameter(Mandatory = $true)][string]$User,
        [Parameter(Mandatory = $true)][string]$System,
        [Parameter(Mandatory = $true)][string]$Target,
        [Parameter(Mandatory = $true)][string]$Operation,
        [Parameter(Mandatory = $true)][ValidateSet('READ_ONLY', 'WRITE', 'DESTRUCTIVE', 'ADMINISTRATIVE', 'SECURITY_SENSITIVE')]
        [string]$Risk,
        [Parameter(Mandatory = $true)][string]$ApprovalType
    )

    $record = [ordered]@{
        operationId  = $OperationId
        user         = $User
        system       = $System
        target       = $Target
        operation    = $Operation
        risk         = $Risk
        approvalType = $ApprovalType
        issuedAt     = (Get-Date).ToUniversalTime().ToString("o")
    }

    $json = $record | ConvertTo-Json -Compress
    $signature = Get-ApprovalSignature -Payload $json
    $record["signature"] = $signature

    $approvalDir = Join-Path (Get-RepoRoot) "logs/.approvals"
    if (-not (Test-Path $approvalDir)) { New-Item -ItemType Directory -Path $approvalDir -Force | Out-Null }
    $approvalPath = Join-Path $approvalDir "$OperationId.json"
    ($record | ConvertTo-Json) | Set-Content -Path $approvalPath -Encoding utf8

    return $record
}

function Get-ApprovalSignature {
    param([Parameter(Mandatory = $true)][string]$Payload)
    $keyPath = Join-Path (Get-RepoRoot) ".github/local-secrets/approval-signing-key.txt"
    if (-not (Test-Path $keyPath)) {
        # POC convenience: derive a deterministic local-only key if none has been
        # provisioned. Production MUST provision a real signing key via the
        # secret manager / credential broker described in README.md.
        "POC-ONLY-NON-PRODUCTION-SIGNING-KEY-$(Get-Date -Format yyyyMMdd)" | Set-Content -Path $keyPath -Encoding utf8
    }
    $key = (Get-Content -Path $keyPath -Raw).Trim()
    $hmac = New-Object System.Security.Cryptography.HMACSHA256([System.Text.Encoding]::UTF8.GetBytes($key))
    $hash = $hmac.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($Payload))
    return [Convert]::ToBase64String($hash)
}

function Test-ApprovalToken {
    <#
        .SYNOPSIS
        Verifies that a presented OperationId corresponds to a valid,
        unconsumed, signature-intact approval record that was issued for
        EXACTLY this System/Target/Operation/Risk combination.

        An approval for "DELETE artifact A" must fail this check when the
        caller is attempting "DELETE artifact B" (Section 32).
    #>
    param(
        [Parameter(Mandatory = $true)][string]$OperationId,
        [Parameter(Mandatory = $true)][string]$System,
        [Parameter(Mandatory = $true)][string]$Target,
        [Parameter(Mandatory = $true)][string]$Operation,
        [Parameter(Mandatory = $true)][string]$ExpectedApprovalType
    )

    $approvalPath = Join-Path (Get-RepoRoot) "logs/.approvals/$OperationId.json"
    if (-not (Test-Path $approvalPath)) {
        return [pscustomobject]@{ Valid = $false; Reason = "No approval record found for operationId '$OperationId'." }
    }

    $record = Get-Content -Path $approvalPath -Raw | ConvertFrom-Json
    $signature = $record.signature
    $unsigned = [ordered]@{
        operationId  = $record.operationId
        user         = $record.user
        system       = $record.system
        target       = $record.target
        operation    = $record.operation
        risk         = $record.risk
        approvalType = $record.approvalType
        issuedAt     = $record.issuedAt
    } | ConvertTo-Json -Compress

    $expectedSig = Get-ApprovalSignature -Payload $unsigned
    if ($signature -ne $expectedSig) {
        return [pscustomobject]@{ Valid = $false; Reason = "Approval signature mismatch - possible tampering." }
    }

    if ($record.system -ne $System -or $record.target -ne $Target -or $record.operation -ne $Operation) {
        return [pscustomobject]@{ Valid = $false; Reason = "Approval record does not match the requested system/target/operation. An approval for one target must never authorize another." }
    }

    if ($record.approvalType -ne $ExpectedApprovalType) {
        return [pscustomobject]@{ Valid = $false; Reason = "Approval type '$($record.approvalType)' does not satisfy required approval type '$ExpectedApprovalType'." }
    }

    $consumedPath = Join-Path (Get-RepoRoot) "logs/.approvals/$OperationId.consumed"
    if (Test-Path $consumedPath) {
        return [pscustomobject]@{ Valid = $false; Reason = "Approval has already been consumed by a prior execution." }
    }

    return [pscustomobject]@{ Valid = $true; Reason = "OK"; Record = $record }
}

function Set-ApprovalConsumed {
    param([Parameter(Mandatory = $true)][string]$OperationId)
    $consumedPath = Join-Path (Get-RepoRoot) "logs/.approvals/$OperationId.consumed"
    (Get-Date).ToUniversalTime().ToString("o") | Set-Content -Path $consumedPath -Encoding utf8
}

# ----------------------------------------------------------------------------
# Audit logging (Section 35 / 36)
# ----------------------------------------------------------------------------
function Write-AuditLog {
    param(
        [Parameter(Mandatory = $true)][string]$OperationId,
        [Parameter(Mandatory = $true)][string]$User,
        [Parameter(Mandatory = $true)][string]$System,
        [Parameter(Mandatory = $true)][string]$SystemVersion,
        [Parameter(Mandatory = $true)][string]$Resource,
        [Parameter(Mandatory = $true)][string]$Operation,
        [Parameter(Mandatory = $true)][string]$Target,
        [Parameter(Mandatory = $true)][ValidateSet('mcp', 'rest-api', 'fallback-skill', 'none')]
        [string]$ExecutionMechanism,
        [Parameter(Mandatory = $true)][string]$Skill,
        [string]$Script = $null,
        [string]$ScriptVersion = $null,
        [Parameter(Mandatory = $true)][ValidateSet('READ_ONLY', 'WRITE', 'DESTRUCTIVE', 'ADMINISTRATIVE', 'SECURITY_SENSITIVE')]
        [string]$Risk,
        [Parameter(Mandatory = $true)][bool]$ApprovalRequired,
        [ValidateSet('NOT_REQUIRED', 'PENDING', 'APPROVED', 'DENIED')]
        [string]$ApprovalStatus = 'NOT_REQUIRED',
        [Parameter(Mandatory = $true)][ValidateSet('SUCCESS', 'FAILURE', 'DENIED', 'UNKNOWN')]
        [string]$Result,
        [Parameter(Mandatory = $true)][ValidateSet('CONFIRMED', 'FAILED', 'UNKNOWN', 'NOT_APPLICABLE')]
        [string]$Verification,
        [string]$Error = $null
    )

    $logsDir = Join-Path (Get-RepoRoot) "logs"
    if (-not (Test-Path $logsDir)) { New-Item -ItemType Directory -Path $logsDir -Force | Out-Null }
    $logPath = Join-Path $logsDir "enterprise-devops-audit.jsonl"

    $record = [ordered]@{
        timestamp           = (Get-Date).ToUniversalTime().ToString("o")
        operationId         = $OperationId
        user                = $User
        system              = $System
        systemVersion       = $SystemVersion
        resource            = $Resource
        operation           = $Operation
        target              = $Target
        executionMechanism  = $ExecutionMechanism
        skill               = $Skill
        script              = $Script
        scriptVersion       = $ScriptVersion
        risk                = $Risk
        approvalRequired    = $ApprovalRequired
        approvalStatus      = $ApprovalStatus
        result              = $Result
        verification        = $Verification
        error               = $Error
    }

    $safeRecord = Protect-SensitiveData -InputObject $record
    ($safeRecord | ConvertTo-Json -Compress) | Add-Content -Path $logPath -Encoding utf8
}

# ----------------------------------------------------------------------------
# Secure HTTP (Section 27 / 29 - TLS verification must never be disabled)
# ----------------------------------------------------------------------------
function Invoke-SecureRestMethod {
    <#
        -BodyEncoding controls how $Body (a hashtable) is serialized:
        'Json' (default) -- every existing caller (Bitbucket, JFrog, Jira,
        Confluence, GitHub) expects a JSON request body and is unaffected.
        'Form' -- application/x-www-form-urlencoded, key=value pairs,
        URL-encoded. Required for SonarQube's v1 Web API (api/projects/*,
        api/issues/*, api/qualitygates/*, api/hotspots/*, api/webhooks/*),
        which -- unlike every other system in this framework -- does NOT
        accept a JSON POST body; only api/v2/* SonarQube endpoints do.
        $null/empty values in $Body are omitted from the form body.
    #>
    param(
        [Parameter(Mandatory = $true)][string]$Uri,
        [Parameter(Mandatory = $true)][ValidateSet('GET', 'POST', 'PUT', 'PATCH', 'DELETE')]
        [string]$Method,
        [System.Security.SecureString]$Token,
        [string]$AuthScheme = "Bearer",
        $Body = $null,
        [ValidateSet('Json', 'Form')][string]$BodyEncoding = 'Json',
        [int]$TimeoutSec = 30
    )

    if ($Uri -notmatch '^https://') {
        throw "Refusing to call a non-HTTPS endpoint: $Uri. TLS is mandatory for all enterprise API calls."
    }

    $headers = @{ "Accept" = "application/json" }
    if ($Token) {
        $plain = ConvertFrom-SecureStringPlain -Secure $Token
        try {
            $headers["Authorization"] = "$AuthScheme $plain"
        }
        finally {
            $plain = $null
        }
    }

    $params = @{
        Uri             = $Uri
        Method          = $Method
        Headers         = $headers
        TimeoutSec      = $TimeoutSec
        UseBasicParsing = $true
        ErrorAction     = "Stop"
        # SslProtocol / certificate validation is intentionally left at
        # PowerShell defaults. Do NOT add -SkipCertificateCheck here.
    }

    if ($null -ne $Body) {
        if ($BodyEncoding -eq 'Form') {
            $pairs = foreach ($key in $Body.Keys) {
                $value = $Body[$key]
                if ($null -ne $value -and [string]$value -ne '') {
                    "$key=$([uri]::EscapeDataString([string]$value))"
                }
            }
            $params["Body"] = ($pairs -join '&')
            $params["ContentType"] = "application/x-www-form-urlencoded"
        }
        else {
            $params["Body"] = ($Body | ConvertTo-Json -Depth 10)
            $params["ContentType"] = "application/json"
        }
    }

    try {
        return Invoke-RestMethod @params
    }
    catch {
        throw
    }
}

function Get-OperationClassification {
    <#
        Looks up the risk category for "<system>.<resource>.<operation>" from
        the machine-readable mirror of policies/operation-classification.yaml.
        The JSON mirror is generated/maintained alongside the YAML (see
        scripts/validation/validate-skills.ps1) specifically so this lookup
        uses a real JSON parser instead of ad hoc YAML regex parsing.
    #>
    param([Parameter(Mandatory = $true)][string]$OperationKey)

    $jsonPath = Join-Path (Get-RepoRoot) "policies/operation-classification.json"
    if (-not (Test-Path $jsonPath)) {
        throw "policies/operation-classification.json not found - run scripts/validation/validate-skills.ps1 or regenerate it from operation-classification.yaml."
    }
    $map = Get-Content -Path $jsonPath -Raw | ConvertFrom-Json
    $entry = $map.operations.$OperationKey
    if (-not $entry) {
        throw "Operation '$OperationKey' is not classified in policies/operation-classification.yaml. Refusing to proceed without an explicit classification (fail closed)."
    }
    return $entry
}

Export-ModuleMember -Function `
    Get-RepoRoot, New-OperationId, Read-LocalSecret, ConvertFrom-SecureStringPlain, `
    Protect-SensitiveData, New-ApprovalToken, Test-ApprovalToken, Set-ApprovalConsumed, `
    Write-AuditLog, Invoke-SecureRestMethod, Get-OperationClassification, Get-ApprovalSignature
