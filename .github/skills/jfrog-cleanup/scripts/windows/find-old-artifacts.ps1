<#
.SYNOPSIS
    READ-ONLY: Find artifacts older than N days in a given Artifactory
    repository via AQL, and summarize candidate count and total size.

.DESCRIPTION
    Purpose:        Candidate discovery for jfrog-cleanup. Never deletes
                    anything.
    Supported OS:   Windows (PowerShell 7+).
    Dependencies:   PowerShell 7+.
    Authentication: JFrog access token, Bearer auth, from -TokenFile.
    Required permissions: Read access to the target repository.
    Approval requirements: None (READ_ONLY).
    Dry-run:        N/A (already read-only).
    API/MCP dependency: REST fallback -- POST /artifactory/api/search/aql
    Exit codes:     0 success, 1 general failure, 2 invalid parameters,
                    3 auth failure, 4 authorization failure,
                    8 repository not found, 10 configuration error.
    Output:         JSON: { candidates: [...], count, totalSizeBytes, criteria }
    Verification:   N/A (read-only).
    Audit:          Appends a FIND audit record (READ_ONLY).
    Security:       TLS validation always on. Repository key validated.

.EXAMPLE
    ./find-old-artifacts.ps1 -BaseUrl "https://artifactory.example.internal" `
        -Repository "releases-local" -OlderThanDays 180
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$BaseUrl,
    [Parameter(Mandatory = $true)][ValidatePattern('^[A-Za-z0-9_][A-Za-z0-9_.-]*$')][string]$Repository,
    [Parameter(Mandatory = $true)][int]$OlderThanDays,
    [string]$TokenFile = (Join-Path (Resolve-Path "$PSScriptRoot/../../../../../..").Path ".github/local-secrets/jfrog-token.txt"),
    [string]$RepoRoot = (Resolve-Path "$PSScriptRoot/../../../../../..").Path
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ScriptVersion = '1.0.0'
[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12

function Write-Audit([hashtable]$Record) {
    try {
        $logsDir = Join-Path $RepoRoot 'logs'
        if (-not (Test-Path $logsDir)) { New-Item -ItemType Directory -Path $logsDir -Force | Out-Null }
        ($Record | ConvertTo-Json -Compress -Depth 6) | Add-Content -Path (Join-Path $logsDir 'enterprise-devops-audit.jsonl') -Encoding utf8
    } catch { Write-Warning "Audit write failed: $($_.Exception.Message)" }
}

try {
    if (-not (Test-Path $TokenFile)) { Write-Error "Token file not found: $TokenFile"; exit 3 }
    $token = (Get-Content $TokenFile -Raw).Trim()
    if ([string]::IsNullOrWhiteSpace($token) -or $token -eq 'REPLACE_WITH_REAL_JFROG_TOKEN') {
        Write-Error "JFrog token file is a placeholder or empty."; exit 3
    }

    $cutoff = (Get-Date).ToUniversalTime().AddDays(-1 * $OlderThanDays).ToString('yyyy-MM-ddTHH:mm:ss.fffZ')
    $aql = "items.find({`"repo`":`"$Repository`",`"created`":{`"`$before`":`"$cutoff`"}})"

    $headers = @{ Authorization = "Bearer $token"; 'Content-Type' = 'text/plain' }
    $uri = "$BaseUrl/artifactory/api/search/aql"

    try {
        $response = Invoke-RestMethod -Method Post -Uri $uri -Headers $headers -Body $aql -ErrorAction Stop
    }
    catch {
        $status = $_.Exception.Response.StatusCode.value__
        if ($status -eq 401) { Write-Error 'Authentication failure.'; exit 3 }
        if ($status -eq 403) { Write-Error 'Authorization failure.'; exit 4 }
        if ($status -eq 404) { Write-Error "Repository not found: $Repository"; exit 8 }
        Write-Error "AQL search failed: $($_.Exception.Message)"
        exit 1
    }

    $results = @($response.results)
    $totalSize = ($results | ForEach-Object { [int64]($_.size) } | Measure-Object -Sum).Sum
    if (-not $totalSize) { $totalSize = 0 }

    Write-Audit @{
        timestamp = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
        operationId = $null; user = $env:USERNAME; system = 'jfrog'; systemVersion = 'detect-at-runtime'
        resource = 'artifact'; operation = 'FIND'; target = $Repository
        executionMechanism = 'rest-api'; skill = 'jfrog-cleanup'
        script = 'scripts/windows/find-old-artifacts.ps1'; scriptVersion = $ScriptVersion
        risk = 'READ_ONLY'; approvalRequired = $false; approvalStatus = 'NOT_REQUIRED'
        result = 'SUCCESS'; verification = 'NOT_APPLICABLE'; error = $null
    }

    [ordered]@{
        candidates     = $results | ForEach-Object { [ordered]@{ repo = $_.repo; path = $_.path; name = $_.name; size = $_.size; created = $_.created } }
        count          = $results.Count
        totalSizeBytes = $totalSize
        criteria       = "created before $cutoff (older than $OlderThanDays days) in repository '$Repository'"
    } | ConvertTo-Json -Depth 6

    exit 0
}
catch {
    Write-Error "find-old-artifacts failed: $($_.Exception.Message)"
    exit 1
}
