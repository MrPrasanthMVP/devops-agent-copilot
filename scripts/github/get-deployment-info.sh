#!/usr/bin/env bash
#
# Purpose:        READ-ONLY: Determine whether the configured GitHub
#                 target is Enterprise Cloud or Enterprise Server, and
#                 report the Server version if applicable (Section 5/38).
# Supported OS:   Linux, macOS (Bash).
# Dependencies:   bash, curl, jq.
# Authentication: GitHub token (Bearer).
# Approval requirements: None (READ_ONLY).
# API/MCP dependency: REST fallback -- GET {api-base-url}/meta
# Exit codes:     0 success, 1 general failure, 3 auth failure,
#                 10 configuration error.
# Output:         JSON: {deployment, hostname, installedVersion}
# Security:       TLS validation always on (no disabled certificate verification).
#
# Example:
#   ./get-deployment-info.sh --api-base-url "https://api.github.com"
#   ./get-deployment-info.sh --api-base-url "https://github.example.internal/api/v3"

set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TOKEN_FILE="$REPO_ROOT/.github/local-secrets/github-token.txt"
API_BASE_URL=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --api-base-url) API_BASE_URL="$2"; shift 2 ;;
        --token-file) TOKEN_FILE="$2"; shift 2 ;;
        *) echo "Unknown argument: $1" >&2; exit 2 ;;
    esac
done

command -v curl >/dev/null 2>&1 || { echo "ERROR: curl is required." >&2; exit 10; }
command -v jq >/dev/null 2>&1 || { echo "ERROR: jq is required." >&2; exit 10; }
[[ -n "$API_BASE_URL" ]] || { echo "ERROR: --api-base-url is required." >&2; exit 2; }
[[ -f "$TOKEN_FILE" ]] || { echo "ERROR: token file not found: $TOKEN_FILE" >&2; exit 3; }
TOKEN="$(tr -d '\n\r' < "$TOKEN_FILE")"
[[ -n "$TOKEN" && "$TOKEN" != "REPLACE_WITH_REAL_GITHUB_TOKEN" ]] || { echo "ERROR: GitHub token file is a placeholder or empty." >&2; exit 3; }

TRIMMED_URL="${API_BASE_URL%/}"
DEPLOYMENT="server"
[[ "$TRIMMED_URL" == "https://api.github.com" ]] && DEPLOYMENT="cloud"
HOSTNAME=$(echo "$TRIMMED_URL" | sed -E 's#^https?://([^/]+).*#\1#')
INSTALLED_VERSION="null"

if [[ "$DEPLOYMENT" == "server" ]]; then
    RESP_FILE=$(mktemp)
    trap 'rm -f "$RESP_FILE"' EXIT
    HTTP_CODE=$(curl --silent --show-error --tlsv1.2 -o "$RESP_FILE" -w "%{http_code}" \
        -X GET "$TRIMMED_URL/meta" -H "Authorization: Bearer $TOKEN" \
        -H "Accept: application/vnd.github+json" -H "X-GitHub-Api-Version: 2022-11-28") || true
    if [[ "$HTTP_CODE" == "401" ]]; then echo "ERROR: Authentication failure." >&2; exit 3; fi
    if [[ "$HTTP_CODE" == "200" ]]; then
        RAW_VERSION=$(jq -r '.installed_version // empty' "$RESP_FILE")
        if [[ -n "$RAW_VERSION" ]]; then INSTALLED_VERSION="\"$RAW_VERSION\""; fi
    else
        echo "WARNING: Could not retrieve /meta installed_version from Enterprise Server -- verify the endpoint against your installed release's REST reference." >&2
    fi
fi

jq -n --arg deployment "$DEPLOYMENT" --arg hostname "$HOSTNAME" --argjson installedVersion "$INSTALLED_VERSION" \
    '{deployment:$deployment, hostname:$hostname, installedVersion:$installedVersion}'
exit 0
