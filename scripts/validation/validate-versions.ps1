<#
.SYNOPSIS
    Enforce that policies/versions-and-sources.yaml is the ONE place
    every official-documentation/MCP-endpoint URL and pinned version
    number is defined.

.DESCRIPTION
    Purpose:        Two checks:
                    1. Exhaustive URL registry check: every URL
                       belonging to a tracked vendor domain that
                       appears anywhere in the repo (*.md, *.yaml,
                       *.yml, *.json) must also appear in
                       versions-and-sources.yaml.
                    2. Literal-copy check: .mcp.json, .vscode/mcp.json,
                       and README.md must still contain the current
                       pinned versions/MCP endpoints.
    Supported OS:   Windows, Linux, macOS (PowerShell 7+).
    Dependencies:   PowerShell 7+.
    Exit codes:     0 = no drift found, 1 = one or more values out of
                    sync, 10 = configuration error.
    Output:         Human-readable PASS/FAIL per checked value.
    Security:       Read-only; no network calls.

.EXAMPLE
    ./validate-versions.ps1
#>

[CmdletBinding()]
param(
    [string]$RepoRoot = (Resolve-Path "$PSScriptRoot/../..").Path
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$versionsFile = Join-Path $RepoRoot 'policies/versions-and-sources.yaml'
if (-not (Test-Path $versionsFile)) { Write-Error "$versionsFile not found."; exit 10 }
$registryContent = Get-Content $versionsFile -Raw

$failures = 0

Write-Host "=== Check 1: every tracked-vendor URL used in the repo must be registered ==="

$vendorPattern = "https://(docs\.github\.com|developer\.atlassian\.com|confluence\.atlassian\.com|docs\.jfrog\.com|jfrog\.com|docs\.sonarsource\.com|www\.sonarsource\.com|github\.com/SonarSource/sonarqube-mcp-server|code\.visualstudio\.com|mcp\.atlassian\.com|api\.githubcopilot\.com|github\.com/github/github-mcp-server)[A-Za-z0-9._~:/?#@!$&'()*+,;=%-]*"

$files = Get-ChildItem -Path $RepoRoot -Recurse -Include *.md, *.yaml, *.yml, *.json, *.ps1, *.sh, *.bats -File |
    Where-Object { $_.FullName -notmatch '[\\/]\.git[\\/]' -and $_.FullName -notmatch '[\\/]node_modules[\\/]' }

$checked = 0
foreach ($file in $files) {
    if ($file.FullName -eq (Resolve-Path $versionsFile).Path) { continue }
    $content = Get-Content $file.FullName -Raw
    $matches = [regex]::Matches($content, $vendorPattern) | ForEach-Object { $_.Value } | Sort-Object -Unique
    foreach ($url in $matches) {
        $checked++
        if (-not $registryContent.Contains($url)) {
            $relative = $file.FullName.Substring($RepoRoot.Length + 1)
            Write-Host "FAIL  $relative uses '$url' which is NOT registered in policies/versions-and-sources.yaml" -ForegroundColor Red
            $failures++
        }
    }
}
Write-Host "($checked URL occurrence(s) checked across the repo)"
Write-Host ''
Write-Host "=== Check 2: files that must carry a literal, working copy ==="

function Extract([string]$pattern) {
    $m = [regex]::Match($registryContent, $pattern)
    if ($m.Success) { return $m.Groups[1].Value }
    return $null
}

# Section-scoped extraction: several systems (jfrog, sonarqube) share the
# same field name (e.g. reference_version_at_generation_time), so a plain
# whole-file regex would silently grab the wrong system's value. This
# extracts only the text belonging to one top-level YAML section.
function Extract-InSection([string]$section, [string]$pattern) {
    $sectionMatch = [regex]::Match($registryContent, "(?ms)^$section`:.*?(?=^\S|\z)")
    if ($sectionMatch.Success) {
        $m = [regex]::Match($sectionMatch.Value, $pattern)
        if ($m.Success) { return $m.Groups[1].Value }
    }
    return $null
}

$jfrogVersion = Extract-InSection 'jfrog' 'reference_version_at_generation_time:\s*"([^"]+)"'
$rovoEndpoint = Extract 'mcp_endpoint:\s*"([^"]+)"'
$githubHostedEndpoint = Extract 'mcp_hosted_endpoint_cloud:\s*"([^"]+)"'
$bitbucketMcpPattern = Extract 'mcp_endpoint_pattern:\s*"([^"]+)"'
$bitbucketMcpSuffix = if ($bitbucketMcpPattern) { $bitbucketMcpPattern -replace '<bitbucket-base-url>', '' } else { $null }

function Check-Contains([string]$label, [string]$relativePath, [string]$needle) {
    if ([string]::IsNullOrWhiteSpace($needle)) {
        Write-Host "SKIP  [$label] could not extract expected value from versions-and-sources.yaml"
        return
    }
    $full = Join-Path $RepoRoot $relativePath
    if (-not (Test-Path $full)) {
        Write-Host "SKIP  [$label] $relativePath not found"
        return
    }
    $fileContent = Get-Content $full -Raw
    if ($fileContent.Contains($needle)) {
        Write-Host "OK    [$label] $relativePath contains '$needle'"
    }
    else {
        Write-Host "FAIL  [$label] $relativePath does NOT contain expected value '$needle' (update it to match policies/versions-and-sources.yaml)" -ForegroundColor Red
        $script:failures++
    }
}

Check-Contains "jfrog reference version" "README.md" $jfrogVersion
Check-Contains "rovo mcp endpoint (.mcp.json)" ".mcp.json" $rovoEndpoint
Check-Contains "rovo mcp endpoint (vscode)" ".vscode/mcp.json" $rovoEndpoint
Check-Contains "github hosted mcp (.mcp.json)" ".mcp.json" $githubHostedEndpoint
Check-Contains "github hosted mcp (vscode)" ".vscode/mcp.json" $githubHostedEndpoint
Check-Contains "bitbucket mcp pattern (.mcp.json)" ".mcp.json" $bitbucketMcpSuffix
Check-Contains "bitbucket mcp pattern (vscode)" ".vscode/mcp.json" $bitbucketMcpSuffix

Write-Host ''
if ($failures -eq 0) {
    Write-Host "validate-versions: PASS (no drift detected)" -ForegroundColor Green
    exit 0
}
else {
    Write-Host "validate-versions: FAIL ($failures issue(s) -- either register the URL in policies/versions-and-sources.yaml, or fix the stale file)" -ForegroundColor Red
    exit 1
}
