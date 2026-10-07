#!/usr/bin/env bash
#
# Purpose:        READ-ONLY: Discover the running Bitbucket Data Center
#                 version and warn if it differs from the pinned target
#                 (9.4.5). Mandatory version discovery per Section 38.
# Supported OS:   Linux, macOS (Bash).
# Dependencies:   bash, curl, jq.
# Authentication: Bitbucket HTTP access token (Bearer).
# Approval requirements: None (READ_ONLY).
# API/MCP dependency: REST fallback -- GET /rest/api/1.0/application-properties
# Exit codes:     0 success, 1 general failure, 3 auth failure,
#                 10 configuration error.
# Output:         JSON: {version, buildNumber, matchesTarget}
# Security:       TLS validation always on (no disabled certificate verification).
#
# Example:
#   ./get-version.sh --base-url "https://bitbucket.example.internal"

set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TOKEN_FILE="$REPO_ROOT/.github/local-secrets/bitbucket-token.txt"

# Single source of truth: policies/versions-and-sources.yaml#bitbucket.pinned_target_version
PINNED_TARGET="9.4.5"
VERSIONS_FILE="$REPO_ROOT/policies/versions-and-sources.yaml"
if [[ -f "$VERSIONS_FILE" ]]; then
    EXTRACTED=$(grep -oP 'pinned_target_version:\s*"\K[^"]+' "$VERSIONS_FILE" 2>/dev/null | head -1 || true)
    [[ -n "$EXTRACTED" ]] && PINNED_TARGET="$EXTRACTED"
fi
BASE_URL=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --base-url) BASE_URL="$2"; shift 2 ;;
        --token-file) TOKEN_FILE="$2"; shift 2 ;;
        *) echo "Unknown argument: $1" >&2; exit 2 ;;
    esac
done

command -v curl >/dev/null 2>&1 || { echo "ERROR: curl is required." >&2; exit 10; }
command -v jq >/dev/null 2>&1 || { echo "ERROR: jq is required." >&2; exit 10; }
[[ -n "$BASE_URL" ]] || { echo "ERROR: --base-url is required." >&2; exit 2; }
[[ -f "$TOKEN_FILE" ]] || { echo "ERROR: token file not found: $TOKEN_FILE" >&2; exit 3; }
TOKEN="$(tr -d '\n\r' < "$TOKEN_FILE")"
[[ -n "$TOKEN" && "$TOKEN" != "REPLACE_WITH_REAL_BITBUCKET_TOKEN" ]] || { echo "ERROR: Bitbucket token file is a placeholder or empty." >&2; exit 3; }

RESP_FILE=$(mktemp)
trap 'rm -f "$RESP_FILE"' EXIT
HTTP_CODE=$(curl --silent --show-error --tlsv1.2 -o "$RESP_FILE" -w "%{http_code}" \
    -X GET "$BASE_URL/rest/api/1.0/application-properties" -H "Authorization: Bearer $TOKEN" -H "Accept: application/json") || true

if [[ "$HTTP_CODE" == "401" ]]; then echo "ERROR: Authentication failure." >&2; exit 3; fi
[[ "$HTTP_CODE" == "200" ]] || { echo "ERROR: get-version failed with HTTP $HTTP_CODE" >&2; exit 1; }

VERSION=$(jq -r '.version' "$RESP_FILE")
BUILD=$(jq -r '.buildNumber' "$RESP_FILE")
MATCHES="false"
[[ "$VERSION" == "$PINNED_TARGET" ]] && MATCHES="true"

if [[ "$MATCHES" == "false" ]]; then
    echo "WARNING: Detected Bitbucket version '$VERSION' differs from the pinned target '$PINNED_TARGET'. Re-verify REST API compatibility before relying on 9.4.5-specific behavior." >&2
fi

jq -n --arg version "$VERSION" --arg buildNumber "$BUILD" --argjson matchesTarget "$MATCHES" \
    '{version:$version, buildNumber:$buildNumber, matchesTarget:$matchesTarget}'
exit 0
