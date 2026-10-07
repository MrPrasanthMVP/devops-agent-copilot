#!/usr/bin/env bash
#
# Purpose:        Validate every .github/skills/*/SKILL.md has required
#                 YAML frontmatter and required documentation sections.
# Supported OS:   Linux, macOS (Bash).
# Dependencies:   bash, grep.
# Exit codes:     0 = all skills valid, 1 = one or more invalid,
#                 10 = configuration error.
# Security:       Read-only; no network calls.
#
# Example:
#   ./validate-skills.sh

set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SKILLS_DIR="$REPO_ROOT/.github/skills"

[[ -d "$SKILLS_DIR" ]] || { echo "ERROR: skills directory not found: $SKILLS_DIR" >&2; exit 10; }

REQUIRED_SECTIONS=(
    "## Purpose" "## Scope" "## When to use" "## When not to use"
    "## MCP dependency" "## API fallback" "## Authentication"
    "## Read operations" "## Write operations" "## Approval rules"
    "## Security" "## Verification" "## Audit" "## Examples"
)

failures=0
count=0

for dir in "$SKILLS_DIR"/*/; do
    name=$(basename "$dir")
    count=$((count + 1))
    skill_md="$dir/SKILL.md"

    if [[ ! -f "$skill_md" ]]; then
        echo "FAIL  $name: missing SKILL.md"
        failures=$((failures + 1))
        continue
    fi

    problems=""

    if ! grep -q '^name:' "$skill_md"; then
        problems="$problems frontmatter-missing-name;"
    fi
    if ! grep -q '^description:' "$skill_md"; then
        problems="$problems frontmatter-missing-description;"
    fi

    for section in "${REQUIRED_SECTIONS[@]}"; do
        if ! grep -qF "$section" "$skill_md"; then
            problems="$problems missing-section:[$section];"
        fi
    done

    if [[ -z "$problems" ]]; then
        echo "OK    $name"
    else
        echo "FAIL  $name: $problems"
        failures=$((failures + 1))
    fi
done

echo
if [[ "$failures" -eq 0 ]]; then
    echo "validate-skills: PASS ($count skills checked)"
    exit 0
else
    echo "validate-skills: FAIL ($failures of $count skills invalid)"
    exit 1
fi
