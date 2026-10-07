<#
.SYNOPSIS
    READ-ONLY: Discover the running Bitbucket Data Center version via
    the application-properties endpoint, and warn if it differs from
    the pinned target (9.4.5).

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
    Output:         JSON: { version, buildNumber, matchesTarget }
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

# Single source of truth: policies/versions-and-sources.yaml#bitbucket.pinned_target_version
$PinnedTarget = '9.4.5'
$versionsFile = Join-Path $RepoRoot 'policies/versions-and-sources.yaml'
if (Test-Path $versionsFile) {
    $line = Select-String -Path $versionsFile -Pattern 'pinned_target_version:\s*"([^"]+)"' -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($line) { $PinnedTarget = $line.Matches[0].Groups[1].Value }
}

try {
    if (-not (Test-Path $TokenFile)) { Write-Error "Token file not found: $TokenFile"; exit 3 }
    $token = (Get-Content $TokenFile -Raw).Trim()
    if ([string]::IsNullOrWhiteSpace($token) -or $token -eq 'REPLACE_WITH_REAL_BITBUCKET_TOKEN') {
        Write-Error "Bitbucket token file is a placeholder or empty."; exit 3
    }

    $headers = @{ Authorization = "Bearer $token"; Accept = 'application/json' }
    $response = Invoke-RestMethod -Method Get -Uri "$BaseUrl/rest/api/1.0/application-properties" -Headers $headers -ErrorAction Stop

    $matches = $response.version -eq $PinnedTarget
    if (-not $matches) {
        Write-Warning "Detected Bitbucket version '$($response.version)' differs from the pinned target '$PinnedTarget'. Re-verify REST API compatibility (Section 3/17) before relying on 9.4.5-specific behavior."
    }

    [ordered]@{ version = $response.version; buildNumber = $response.buildNumber; matchesTarget = $matches } | ConvertTo-Json -Compress
    exit 0
}
catch {
    $status = $_.Exception.Response.StatusCode.value__
    if ($status -eq 401) { Write-Error 'Authentication failure.'; exit 3 }
    Write-Error "get-version failed: $($_.Exception.Message)"
    exit 1
}
