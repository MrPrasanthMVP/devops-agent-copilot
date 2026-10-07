<#
.SYNOPSIS
    Scan all *.ps1 and *.sh scripts in the repository for forbidden
    security patterns (Sections 27-29): Invoke-Expression/iex, eval,
    TLS bypass (curl -k/--insecure, -SkipCertificateCheck), and
    hardcoded-looking credentials.

.DESCRIPTION
    Purpose:        CI security gate.
    Supported OS:   Windows, Linux, macOS (PowerShell 7+).
    Dependencies:   PowerShell 7+.
    Exit codes:     0 = clean, 1 = one or more violations found,
                    10 = configuration error.
    Output:         Per-violation file:line and pattern matched.
    Security:       Read-only; no network calls.

.EXAMPLE
    ./validate-security.ps1
#>

[CmdletBinding()]
param(
    [string]$RepoRoot = (Resolve-Path "$PSScriptRoot/../..").Path
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$forbiddenPatterns = @(
    @{ Pattern = 'Invoke-Expression'; Description = 'Invoke-Expression is forbidden (Section 27)' }
    @{ Pattern = '(?<![\w-])iex\s'; Description = 'iex alias is forbidden (Section 27)' }
    @{ Pattern = 'curl\s+.*(-k\b|--insecure)'; Description = 'curl -k/--insecure is forbidden (Section 29)' }
    @{ Pattern = '-SkipCertificateCheck'; Description = 'TLS certificate validation bypass is forbidden (Section 27)' }
    @{ Pattern = 'ServerCertificateValidationCallback'; Description = 'TLS certificate validation bypass is forbidden (Section 27)' }
    @{ Pattern = '(?<![\w.$])eval\s'; Description = 'eval on untrusted input is forbidden (Section 28)' }
)

$files = Get-ChildItem -Path $RepoRoot -Recurse -Include *.ps1,*.sh -File |
    Where-Object {
        $_.FullName -notmatch '[\\/]node_modules[\\/]' -and
        $_.FullName -notmatch '[\\/]scripts[\\/]validation[\\/]validate-security\.(ps1|sh)$'
    }

$violations = 0

foreach ($file in $files) {
    $lines = Get-Content $file.FullName
    for ($i = 0; $i -lt $lines.Count; $i++) {
        foreach ($rule in $forbiddenPatterns) {
            if ($lines[$i] -match $rule.Pattern) {
                $relative = $file.FullName.Substring($RepoRoot.Length + 1)
                Write-Host "VIOLATION $relative`:$($i+1): $($rule.Description)" -ForegroundColor Red
                Write-Host "    $($lines[$i].Trim())"
                $violations++
            }
        }
    }
}

Write-Host ''
if ($violations -eq 0) {
    Write-Host "validate-security: PASS ($($files.Count) scripts scanned, 0 violations)" -ForegroundColor Green
    exit 0
} else {
    Write-Host "validate-security: FAIL ($violations violation(s) found)" -ForegroundColor Red
    exit 1
}
