<#
.SYNOPSIS
    READ-ONLY: Discover the running SonarQube Server/Community Build
    version at runtime. Applies to the Server (self-managed) deployment
    only -- SonarQube Cloud is continuously deployed and has no server
    version to discover (same reasoning as Jira/Confluence Cloud). The
    framework MUST NOT hard-code a SonarQube Server version.

.DESCRIPTION
    Purpose:        Mandatory version discovery (Section 38) for the
                    Server deployment, mirroring scripts/jfrog/get-version.ps1.
    Supported OS:   Windows, Linux, macOS (PowerShell 7+).
    Dependencies:   PowerShell 7+.
    Authentication: SonarQube user token, Bearer auth.
    Approval requirements: None (READ_ONLY).
    API/MCP dependency: REST fallback -- GET /api/system/status
    Exit codes:     0 success, 1 general failure, 3 auth failure,
                    10 configuration error.
    Output:         JSON: { version, status, id, referenceVersion, matchesReference }
    Security:       TLS validation always on.

.EXAMPLE
    ./get-version.ps1 -BaseUrl "https://sonarqube.example.internal"
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$BaseUrl,
    [string]$TokenFile = (Join-Path (Resolve-Path "$PSScriptRoot/../..").Path ".github/local-secrets/sonarqube-token.txt"),
    [string]$RepoRoot = (Resolve-Path "$PSScriptRoot/../..").Path
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12

# Single source of truth: policies/versions-and-sources.yaml#sonarqube.server.reference_version_at_generation_time
# ALL SonarQube Server/Community Build versions are supported; this is
# only a last-verified reference baseline for informational
# drift-tracking, never a restriction.
$ReferenceVersion = '26.9.0.129388'
$versionsFile = Join-Path $RepoRoot 'policies/versions-and-sources.yaml'
if (Test-Path $versionsFile) {
    $yamlText = Get-Content $versionsFile -Raw
    $sectionMatch = [regex]::Match($yamlText, '(?ms)^sonarqube:.*?(?=^\S|\z)')
    if ($sectionMatch.Success) {
        $m = [regex]::Match($sectionMatch.Value, 'reference_version_at_generation_time:\s*"([^"]+)"')
        if ($m.Success) { $ReferenceVersion = $m.Groups[1].Value }
    }
}

try {
    if (-not (Test-Path $TokenFile)) { Write-Error "Token file not found: $TokenFile"; exit 3 }
    $token = (Get-Content $TokenFile -Raw).Trim()
    if ([string]::IsNullOrWhiteSpace($token) -or $token -eq 'REPLACE_WITH_REAL_SONARQUBE_TOKEN') {
        Write-Error "SonarQube token file is a placeholder or empty."; exit 3
    }

    $headers = @{ Authorization = "Bearer $token"; Accept = 'application/json' }
    $response = Invoke-RestMethod -Method Get -Uri "$BaseUrl/api/system/status" -Headers $headers -ErrorAction Stop

    $matchesReference = $response.version -eq $ReferenceVersion
    if (-not $matchesReference) {
        Write-Warning "Detected SonarQube Server version '$($response.version)' differs from the documented reference '$ReferenceVersion' (recorded at framework-generation time). All SonarQube Server/Community Build versions are supported -- this is informational only; re-verify Web API compatibility against official_docs for this specific version before relying on $ReferenceVersion-specific behavior."
    }

    [ordered]@{
        version          = $response.version
        status           = $response.status
        id               = $response.id
        referenceVersion = $ReferenceVersion
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
