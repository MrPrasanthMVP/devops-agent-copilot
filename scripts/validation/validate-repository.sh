#!/usr/bin/env bash
#
# Purpose:        Validate that the enterprise-devops-copilot repository
#                 contains the required structure (Section 42).
# Supported OS:   Linux, macOS (Bash).
# Dependencies:   bash.
# Exit codes:     0 = all required paths present, 1 = one or more missing,
#                 10 = configuration error.
# Output:         Human-readable list of OK/MISSING per required path.
# Security:       Read-only; no network calls.
#
# Example:
#   ./validate-repository.sh

set -euo pipefail
SCRIPT_VERSION="1.0.0"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

REQUIRED_PATHS=(
    ".github/agents/enterprise-devops.agent.md"
    ".github/copilot-instructions.md"
    ".github/local-secrets/bitbucket-token.txt.example"
    ".github/local-secrets/jfrog-token.txt.example"
    ".github/local-secrets/github-token.txt.example"
    ".vscode/mcp.json"
    ".mcp.json"
    "policies/approval-policy.yaml"
    "policies/operation-classification.yaml"
    "policies/security-policy.yaml"
    "policies/system-policy.yaml"
    "policies/audit-policy.yaml"
    "policies/versions-and-sources.yaml"
    "scripts/validation/validate-repository.ps1"
    "scripts/validation/validate-repository.sh"
    "scripts/validation/validate-skills.ps1"
    "scripts/validation/validate-skills.sh"
    "scripts/validation/validate-security.ps1"
    "scripts/validation/validate-security.sh"
    "scripts/validation/validate-versions.ps1"
    "scripts/validation/validate-versions.sh"
    "tests/approval"
    "tests/bitbucket"
    "tests/jira"
    "tests/confluence"
    "tests/jfrog"
    "tests/github"
    "logs/.gitkeep"
    "README.md"
    "how_to_use.md"
    "features.md"
    "SECURITY.md"
    "CONTRIBUTING.md"
    ".gitignore"
)

REQUIRED_SKILLS=(
    human-approval
    bitbucket-admin bitbucket-project-admin bitbucket-repository-admin bitbucket-permissions
    bitbucket-branch-permissions bitbucket-hooks bitbucket-webhooks bitbucket-merge-settings
    bitbucket-merge-checks bitbucket-pull-requests bitbucket-file-management
    jira-admin jira-issues jira-permissions jira-workflows
    confluence-admin confluence-pages confluence-permissions
    jfrog-admin jfrog-repositories jfrog-artifacts jfrog-permissions jfrog-users
    jfrog-groups jfrog-projects jfrog-xray jfrog-build-info jfrog-cleanup
    github-enterprise-admin github-organizations github-repositories github-teams
    github-permissions github-branches github-branch-protection github-rulesets
    github-pull-requests github-actions github-runners github-webhooks github-security
)

missing=0

for p in "${REQUIRED_PATHS[@]}"; do
    if [[ -e "$REPO_ROOT/$p" ]]; then
        echo "OK      $p"
    else
        echo "MISSING $p"
        missing=$((missing + 1))
    fi
done

for skill in "${REQUIRED_SKILLS[@]}"; do
    p=".github/skills/$skill/SKILL.md"
    if [[ -f "$REPO_ROOT/$p" ]]; then
        echo "OK      $p"
    else
        echo "MISSING $p"
        missing=$((missing + 1))
    fi
done

echo
if [[ "$missing" -eq 0 ]]; then
    echo "validate-repository: PASS"
    exit 0
else
    echo "validate-repository: FAIL ($missing missing path(s))"
    exit 1
fi
