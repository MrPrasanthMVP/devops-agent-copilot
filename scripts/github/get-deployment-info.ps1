<#
.SYNOPSIS
    READ-ONLY: Determine whether the configured GitHub target is
    Enterprise Cloud or Enterprise Server, and report the Server
    version if applicable. Implements the Section 5/38 Cloud-vs-Server
    discovery contract that every GitHub Skill depends on before
    choosing an MCP endpoint or REST API version.

.DESCRIPTION
    Purpose:        Mandatory deployment-type + version discovery.
    Supported OS:   Windows, Linux, macOS (PowerShell 7+).
    Dependencies:   PowerShell 7+.
    Authentication: GitHub token, Bearer auth.
    Approval requirements: None (READ_ONLY).
    API/MCP dependency: REST fallback -- GET {ApiBaseUrl}/meta
    Exit codes:     0 success, 1 general failure, 3 auth failure,
                    10 configuration error.
    Output:         JSON: { deployment, hostname, installedVersion }
                    installedVersion is null for Cloud (continuously deployed).
    Security:       TLS validation always on.

.EXAMPLE
    ./get-deployment-info.ps1 -ApiBaseUrl "https://api.github.com"
    ./get-deployment-info.ps1 -ApiBaseUrl "https://github.example.internal/api/v3"
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$ApiBaseUrl,
    [string]$TokenFile = (Join-Path (Resolve-Path "$PSScriptRoot/../..").Path ".github/local-secrets/github-token.txt")
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12

try {
    if (-not (Test-Path $TokenFile)) { Write-Error "Token file not found: $TokenFile"; exit 3 }
    $token = (Get-Content $TokenFile -Raw).Trim()
    if ([string]::IsNullOrWhiteSpace($token) -or $token -eq 'REPLACE_WITH_REAL_GITHUB_TOKEN') {
        Write-Error "GitHub token file is a placeholder or empty."; exit 3
    }

    $headers = @{
        Authorization        = "Bearer $token"
        Accept                = 'application/vnd.github+json'
        'X-GitHub-Api-Version' = '2022-11-28'
    }

    $isCloud = $ApiBaseUrl.TrimEnd('/') -eq 'https://api.github.com'
    $deployment = if ($isCloud) { 'cloud' } else { 'server' }
    $installedVersion = $null

    if (-not $isCloud) {
        try {
            $meta = Invoke-RestMethod -Method Get -Uri "$ApiBaseUrl/meta" -Headers $headers -ErrorAction Stop
            if ($meta.installed_version) { $installedVersion = $meta.installed_version }
        }
        catch {
            Write-Warning "Could not retrieve /meta installed_version from Enterprise Server -- verify the endpoint against your installed release's REST reference."
        }
    }

    $hostname = ([Uri]$ApiBaseUrl).Host

    [ordered]@{ deployment = $deployment; hostname = $hostname; installedVersion = $installedVersion } | ConvertTo-Json -Compress
    exit 0
}
catch {
    $status = $_.Exception.Response.StatusCode.value__
    if ($status -eq 401) { Write-Error 'Authentication failure.'; exit 3 }
    Write-Error "get-deployment-info failed: $($_.Exception.Message)"
    exit 1
}
