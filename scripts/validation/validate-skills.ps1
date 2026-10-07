<#
.SYNOPSIS
    Validate every .github/skills/*/SKILL.md has required YAML
    frontmatter (name, description) and the required documentation
    sections (Section 14).

.DESCRIPTION
    Purpose:        CI gate for Skill completeness/consistency.
    Supported OS:   Windows, Linux, macOS (PowerShell 7+).
    Dependencies:   PowerShell 7+.
    Exit codes:     0 = all skills valid, 1 = one or more invalid,
                    10 = configuration error.
    Output:         Per-skill OK/FAIL with the specific missing piece.
    Security:       Read-only; no network calls.

.EXAMPLE
    ./validate-skills.ps1
#>

[CmdletBinding()]
param(
    [string]$RepoRoot = (Resolve-Path "$PSScriptRoot/../..").Path
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$requiredSections = @(
    '## Purpose', '## Scope', '## When to use', '## When not to use',
    '## MCP dependency', '## API fallback', '## Authentication',
    '## Read operations', '## Write operations', '## Approval rules',
    '## Security', '## Verification', '## Audit', '## Examples'
)

$skillsDir = Join-Path $RepoRoot '.github/skills'
if (-not (Test-Path $skillsDir)) { Write-Error "Skills directory not found: $skillsDir"; exit 10 }

$failures = 0
$skillDirs = Get-ChildItem -Path $skillsDir -Directory | Sort-Object Name

foreach ($dir in $skillDirs) {
    $skillMd = Join-Path $dir.FullName 'SKILL.md'
    if (-not (Test-Path $skillMd)) {
        Write-Host "FAIL  $($dir.Name): missing SKILL.md" -ForegroundColor Red
        $failures++
        continue
    }

    $content = Get-Content $skillMd -Raw
    $problems = @()

    if ($content -notmatch '(?ms)^---\s*\r?\n(.*?)\r?\n---') {
        $problems += 'missing YAML frontmatter block'
    } else {
        $fm = $Matches[1]
        if ($fm -notmatch '(?m)^name:\s*\S+') { $problems += 'frontmatter missing name' }
        if ($fm -notmatch '(?m)^description:\s*\S+') { $problems += 'frontmatter missing description' }
    }

    foreach ($section in $requiredSections) {
        if ($content -notmatch [regex]::Escape($section)) {
            $problems += "missing section '$section'"
        }
    }

    if ($problems.Count -eq 0) {
        Write-Host "OK    $($dir.Name)"
    } else {
        Write-Host "FAIL  $($dir.Name): $($problems -join '; ')" -ForegroundColor Red
        $failures++
    }
}

Write-Host ''
if ($failures -eq 0) {
    Write-Host "validate-skills: PASS ($($skillDirs.Count) skills checked)" -ForegroundColor Green
    exit 0
} else {
    Write-Host "validate-skills: FAIL ($failures of $($skillDirs.Count) skills invalid)" -ForegroundColor Red
    exit 1
}
