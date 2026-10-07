<#
.SYNOPSIS
    Validate that the enterprise-devops-copilot repository contains the
    required structure defined in Section 42 of the governing spec.

.DESCRIPTION
    Purpose:        Structural CI gate -- fails if required top-level
                    files/directories are missing.
    Supported OS:   Windows, Linux, macOS (PowerShell 7+).
    Dependencies:   PowerShell 7+.
    Authentication: None.
    Required permissions: Read access to the repository.
    Approval requirements: None (read-only validation).
    Dry-run:        N/A (already read-only).
    API/MCP dependency: None.
    Exit codes:     0 = all required paths present, 1 = one or more missing,
                    10 = configuration error (repo root not found).
    Output:         Human-readable list of OK/MISSING per required path.
    Verification:   N/A.
    Audit:          None (CI-time structural check, not a runtime operation).
    Security:       Read-only; no network calls.

.EXAMPLE
    ./validate-repository.ps1
#>

[CmdletBinding()]
param(
    [string]$RepoRoot = (Resolve-Path "$PSScriptRoot/../..").Path
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$ScriptVersion = '1.0.0'

$requiredPaths = @(
    '.github/agents/enterprise-devops.agent.md'
    '.github/copilot-instructions.md'
    '.github/local-secrets/bitbucket-token.txt.example'
    '.github/local-secrets/jfrog-token.txt.example'
    '.github/local-secrets/github-token.txt.example'
    '.vscode/mcp.json'
    '.mcp.json'
    'policies/approval-policy.yaml'
    'policies/operation-classification.yaml'
    'policies/security-policy.yaml'
    'policies/system-policy.yaml'
    'policies/audit-policy.yaml'
    'policies/versions-and-sources.yaml'
    'scripts/validation/validate-repository.ps1'
    'scripts/validation/validate-repository.sh'
    'scripts/validation/validate-skills.ps1'
    'scripts/validation/validate-skills.sh'
    'scripts/validation/validate-security.ps1'
    'scripts/validation/validate-security.sh'
    'scripts/validation/validate-versions.ps1'
    'scripts/validation/validate-versions.sh'
    'tests/approval'
    'tests/bitbucket'
    'tests/jira'
    'tests/confluence'
    'tests/jfrog'
    'tests/github'
    'logs/.gitkeep'
    'README.md'
    'how_to_use.md'
    'features.md'
    'SECURITY.md'
    'CONTRIBUTING.md'
    '.gitignore'
)

$requiredSkillDirs = @(
    'human-approval'
    'bitbucket-admin','bitbucket-project-admin','bitbucket-repository-admin','bitbucket-permissions'
    'bitbucket-branch-permissions','bitbucket-hooks','bitbucket-webhooks','bitbucket-merge-settings'
    'bitbucket-merge-checks','bitbucket-pull-requests','bitbucket-file-management'
    'jira-admin','jira-issues','jira-permissions','jira-workflows'
    'confluence-admin','confluence-pages','confluence-permissions'
    'jfrog-admin','jfrog-repositories','jfrog-artifacts','jfrog-permissions','jfrog-users'
    'jfrog-groups','jfrog-projects','jfrog-xray','jfrog-build-info','jfrog-cleanup'
    'github-enterprise-admin','github-organizations','github-repositories','github-teams'
    'github-permissions','github-branches','github-branch-protection','github-rulesets'
    'github-pull-requests','github-actions','github-runners','github-webhooks','github-security'
)

$missing = @()

foreach ($p in $requiredPaths) {
    $full = Join-Path $RepoRoot $p
    if (Test-Path $full) {
        Write-Host "OK      $p"
    } else {
        Write-Host "MISSING $p" -ForegroundColor Red
        $missing += $p
    }
}

foreach ($skill in $requiredSkillDirs) {
    $skillMd = Join-Path $RepoRoot ".github/skills/$skill/SKILL.md"
    if (Test-Path $skillMd) {
        Write-Host "OK      .github/skills/$skill/SKILL.md"
    } else {
        Write-Host "MISSING .github/skills/$skill/SKILL.md" -ForegroundColor Red
        $missing += ".github/skills/$skill/SKILL.md"
    }
}

Write-Host ''
if ($missing.Count -eq 0) {
    Write-Host "validate-repository: PASS (all $($requiredPaths.Count + $requiredSkillDirs.Count) required paths present)" -ForegroundColor Green
    exit 0
} else {
    Write-Host "validate-repository: FAIL ($($missing.Count) missing path(s))" -ForegroundColor Red
    exit 1
}
