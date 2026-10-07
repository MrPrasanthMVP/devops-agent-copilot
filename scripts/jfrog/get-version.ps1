<#
.SYNOPSIS
    READ-ONLY: Discover the running JFrog Artifactory version at
    runtime. The framework MUST NOT hard-code an Artifactory version
    (Section 4) -- this script is the mandatory discovery step and
    compares against the reference value recorded in the single source
    of truth, policies/versions-and-sources.yaml, purely for
    informational drift-warning.

.DESCRIPTION
    Purpose:        Mandatory version discovery (Section 4/38).
    Supported OS:   Windows, Linux, macOS (PowerShell 7+).
    Dependencies:   PowerShell 7+.
    Authentication: JFrog access token, Bearer auth.
    Approval requirements: None (READ_ONLY).
    API/MCP dependency: REST fallback -- GET /artifactory/api/system/version
    Exit codes:     0 success, 1 general failure, 3 auth failure,
                    10 configuration error.
    Output:         JSON: { version, revision, referenceVersion, matchesReference }
    Security:       TLS validation always on.

.EXAMPLE
    ./get-version.ps1 -BaseUrl "https://artifactory.example.internal"
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$BaseUrl,
    [string]$TokenFile = (Join-Path (Resolve-Path "$PSScriptRoot/../..").Path ".github/local-secrets/jfrog-token.txt"),
    [string]$RepoRoot = (Resolve-Path "$PSScriptRoot/../..").Path
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12

try {
    if (-not (Test-Path $TokenFile)) { Write-Error "Token file not found: $TokenFile"; exit 3 }
    $token = (Get-Content $TokenFile -Raw).Trim()
    if ([string]::IsNullOrWhiteSpace($token) -or $token -eq 'REPLACE_WITH_REAL_JFROG_TOKEN') {
        Write-Error "JFrog token file is a placeholder or empty."; exit 3
    }

    $headers = @{ Authorization = "Bearer $token"; Accept = 'application/json' }
    $response = Invoke-RestMethod -Method Get -Uri "$BaseUrl/artifactory/api/system/version" -Headers $headers -ErrorAction Stop

    $referenceVersion = '7.161.32'
    $versionsFile = Join-Path $RepoRoot 'policies/versions-and-sources.yaml'
    if (Test-Path $versionsFile) {
        $line = Select-String -Path $versionsFile -Pattern 'reference_version_at_generation_time:\s*"([^"]+)"' -ErrorAction SilentlyContinue
        if ($line) { $referenceVersion = $line.Matches[0].Groups[1].Value }
    }

    $matchesReference = $response.version -eq $referenceVersion
    if (-not $matchesReference) {
        Write-Warning "Detected Artifactory version '$($response.version)' differs from the documented reference '$referenceVersion' (recorded at framework-generation time). This is expected as JFrog ships frequent releases -- re-verify capability routing against https://docs.jfrog.com/releases/docs/artifactory-release-notes if you rely on version-specific behavior."
    }

    [ordered]@{
        version          = $response.version
        revision         = $response.revision
        referenceVersion = $referenceVersion
        matchesReference = $matchesReference
    } | ConvertTo-Json -Compress
    exit 0
}
catch {
    $status = $_.Exception.Response.StatusCode.value__
    if ($status -eq 401) { Write-Error 'Authentication failure.'; exit 3 }
    Write-Error "get-version failed: $($_.Exception.Message)"
    exit 1
}
