<#
.SYNOPSIS
    READ-ONLY: Discover the running Bitbucket Data Center version via
    the application-properties endpoint. ALL Bitbucket Data Center 9.x
    and 10.x releases are supported -- this reports the detected version
    and flags it only if its major version falls outside 9.x/10.x
    (informational; never a hard restriction on the operation itself).

.DESCRIPTION
    Purpose:        Mandatory version discovery (Section 38) -- the
                    framework must never hard-code a Bitbucket version
                    into runtime logic.
    Supported OS:   Windows, Linux, macOS (PowerShell 7+).
    Dependencies:   PowerShell 7+.
    Authentication: Bitbucket HTTP access token, Bearer auth.
    Required permissions: Any authenticated user (this endpoint does not
                    require admin rights).
    Approval requirements: None (READ_ONLY).
    API/MCP dependency: REST fallback --
                    GET /rest/api/1.0/application-properties
    Exit codes:     0 success, 1 general failure, 3 auth failure,
                    10 configuration error.
    Output:         JSON: { version, buildNumber, supportedMajorRange, inSupportedRange }
    Security:       TLS validation always on.

.EXAMPLE
    ./get-version.ps1 -BaseUrl "https://bitbucket.example.internal"
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$BaseUrl,
    [string]$TokenFile = (Join-Path (Resolve-Path "$PSScriptRoot/../..").Path ".github/local-secrets/bitbucket-token.txt"),
    [string]$RepoRoot = (Resolve-Path "$PSScriptRoot/../..").Path
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12

# Single source of truth: policies/versions-and-sources.yaml#bitbucket.supported_version_range
# ALL Bitbucket Data Center 9.x and 10.x releases are supported; no single
# patch version is pinned. This script only confirms the detected major
# version falls in that supported range.
$SupportedMajorRange = @(9, 10)

try {
    if (-not (Test-Path $TokenFile)) { Write-Error "Token file not found: $TokenFile"; exit 3 }
    $token = (Get-Content $TokenFile -Raw).Trim()
    if ([string]::IsNullOrWhiteSpace($token) -or $token -eq 'REPLACE_WITH_REAL_BITBUCKET_TOKEN') {
        Write-Error "Bitbucket token file is a placeholder or empty."; exit 3
    }

    $headers = @{ Authorization = "Bearer $token"; Accept = 'application/json' }
    $response = Invoke-RestMethod -Method Get -Uri "$BaseUrl/rest/api/1.0/application-properties" -Headers $headers -ErrorAction Stop

    $majorVersion = $null
    $versionMatch = [regex]::Match([string]$response.version, '^(\d+)\.')
    if ($versionMatch.Success) { $majorVersion = [int]$versionMatch.Groups[1].Value }

    $inSupportedRange = ($null -ne $majorVersion) -and ($SupportedMajorRange -contains $majorVersion)
    if (-not $inSupportedRange) {
        Write-Warning "Detected Bitbucket version '$($response.version)' is outside the supported major-version range (9.x and 10.x). This is informational only; re-verify REST API/MCP compatibility (Section 3/17) before relying on this framework's Bitbucket integration against it."
    }

    [ordered]@{
        version             = $response.version
        buildNumber         = $response.buildNumber
        supportedMajorRange = "9.x-10.x"
        inSupportedRange    = $inSupportedRange
    } | ConvertTo-Json -Compress
    exit 0
}
catch {
    $status = $_.Exception.Response.StatusCode.value__
    if ($status -eq 401) { Write-Error 'Authentication failure.'; exit 3 }
    Write-Error "get-version failed: $($_.Exception.Message)"
    exit 1
}
