#!/usr/bin/env bash
#
# Purpose:        Enforce that policies/versions-and-sources.yaml is the
#                 ONE place every official-documentation/MCP-endpoint
#                 URL and pinned version number is defined.
#
#                 Two checks:
#                 1. Exhaustive URL registry check: every URL belonging
#                    to a tracked vendor domain (docs.github.com,
#                    developer.atlassian.com, confluence.atlassian.com,
#                    docs.jfrog.com, jfrog.com, docs.sonarsource.com,
#                    www.sonarsource.com, code.visualstudio.com,
#                    mcp.atlassian.com, api.githubcopilot.com,
#                    github.com/github/github-mcp-server) that appears
#                    ANYWHERE in the repo (*.md, *.yaml, *.yml, *.json)
#                    must also appear in versions-and-sources.yaml. If
#                    it doesn't, either the URL is unapproved/unverified,
#                    or it drifted after the registry was changed and
#                    this file was not updated to match.
#                 2. Literal-copy check: the handful of files listed in
#                    versions-and-sources.yaml#must_also_update_manually
#                    (.mcp.json, .vscode/mcp.json, README.md) must still
#                    contain the current pinned versions/MCP endpoints.
#
# Supported OS:   Linux, macOS (Bash).
# Dependencies:   bash, grep.
# Exit codes:     0 = no drift found, 1 = one or more values out of sync,
#                 10 = configuration error (versions file missing).
# Output:         Human-readable PASS/FAIL per checked value.
# Security:       Read-only; no network calls.
#
# Example:
#   ./validate-versions.sh

set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
VERSIONS_FILE="$REPO_ROOT/policies/versions-and-sources.yaml"

[[ -f "$VERSIONS_FILE" ]] || { echo "ERROR: $VERSIONS_FILE not found." >&2; exit 10; }

VENDOR_PATTERN='https://(docs\.github\.com|developer\.atlassian\.com|confluence\.atlassian\.com|docs\.jfrog\.com|jfrog\.com|docs\.sonarsource\.com|www\.sonarsource\.com|github\.com/SonarSource/sonarqube-mcp-server|code\.visualstudio\.com|mcp\.atlassian\.com|api\.githubcopilot\.com|github\.com/github/github-mcp-server)[A-Za-z0-9._~:/?#@!$&'"'"'()*+,;=%-]*'

failures=0
checked=0

echo "=== Check 1: every tracked-vendor URL used in the repo must be registered ==="
while IFS= read -r -d '' file; do
    # Skip the registry itself.
    [[ "$file" == "$VERSIONS_FILE" ]] && continue
    while IFS= read -r url; do
        [[ -z "$url" ]] && continue
        checked=$((checked + 1))
        if grep -qF "$url" "$VERSIONS_FILE"; then
            :
        else
            rel="${file#"$REPO_ROOT"/}"
            echo "FAIL  $rel uses '$url' which is NOT registered in policies/versions-and-sources.yaml"
            failures=$((failures + 1))
        fi
    done < <(grep -ohE "$VENDOR_PATTERN" "$file" 2>/dev/null | sort -u)
done < <(find "$REPO_ROOT" \( -name "*.md" -o -name "*.yaml" -o -name "*.yml" -o -name "*.json" \
    -o -name "*.ps1" -o -name "*.sh" -o -name "*.bats" \) \
    -not -path "*/.git/*" -not -path "*/node_modules/*" -print0)

echo "($checked URL occurrence(s) checked across the repo)"
echo
echo "=== Check 2: files that must carry a literal, working copy ==="

extract() { grep -oP "$1" "$VERSIONS_FILE" 2>/dev/null | head -1 || true; }

# Section-scoped extraction: several systems (jfrog, sonarqube) share the
# same field name (e.g. reference_version_at_generation_time), so a plain
# whole-file grep would silently grab the wrong system's value. This
# extracts only the lines belonging to one top-level YAML section.
extract_in_section() {
  local section="$1" pattern="$2"
  awk -v s="^${section}:" 'BEGIN{f=0} $0 ~ s {f=1; next} f && /^[^[:space:]]/ {f=0} f' "$VERSIONS_FILE" \
    | grep -oP "$pattern" | head -1 || true
}

JFROG_VERSION=$(extract_in_section 'jfrog' 'reference_version_at_generation_time:\s*"\K[^"]+')
ROVO_ENDPOINT=$(extract 'mcp_endpoint:\s*"\K[^"]+')
GITHUB_HOSTED_ENDPOINT=$(extract 'mcp_hosted_endpoint_cloud:\s*"\K[^"]+')
BITBUCKET_MCP_PATTERN=$(extract 'mcp_endpoint_pattern:\s*"\K[^"]+')

check_contains() {
  local label="$1" file="$2" needle="$3"
  if [[ -z "$needle" ]]; then
    echo "SKIP  [$label] could not extract expected value from versions-and-sources.yaml"
    return
  fi
  if [[ ! -f "$REPO_ROOT/$file" ]]; then
    echo "SKIP  [$label] $file not found"
    return
  fi
  if grep -qF "$needle" "$REPO_ROOT/$file"; then
    echo "OK    [$label] $file contains '$needle'"
  else
    echo "FAIL  [$label] $file does NOT contain expected value '$needle' (update it to match policies/versions-and-sources.yaml)"
    failures=$((failures + 1))
  fi
}

check_contains "jfrog reference version"       "README.md"        "$JFROG_VERSION"
check_contains "rovo mcp endpoint (.mcp.json)" ".mcp.json"        "$ROVO_ENDPOINT"
check_contains "rovo mcp endpoint (vscode)"    ".vscode/mcp.json" "$ROVO_ENDPOINT"
check_contains "github hosted mcp (.mcp.json)" ".mcp.json"        "$GITHUB_HOSTED_ENDPOINT"
check_contains "github hosted mcp (vscode)"    ".vscode/mcp.json" "$GITHUB_HOSTED_ENDPOINT"
check_contains "bitbucket mcp pattern (.mcp.json)" ".mcp.json"    "${BITBUCKET_MCP_PATTERN//<bitbucket-base-url>/}"
check_contains "bitbucket mcp pattern (vscode)"    ".vscode/mcp.json" "${BITBUCKET_MCP_PATTERN//<bitbucket-base-url>/}"

echo
if [[ "$failures" -eq 0 ]]; then
  echo "validate-versions: PASS (no drift detected)"
  exit 0
else
  echo "validate-versions: FAIL ($failures issue(s) -- either register the URL in policies/versions-and-sources.yaml, or fix the stale file)"
  exit 1
fi
