#!/usr/bin/env bash
#
# Purpose:        READ-ONLY: Discover the running JFrog Artifactory
#                 version at runtime (Section 4/38 mandatory discovery
#                 -- never hard-code an Artifactory version).
# Supported OS:   Linux, macOS (Bash).
# Dependencies:   bash, curl, jq.
# Authentication: JFrog access token (Bearer).
# Approval requirements: None (READ_ONLY).
# API/MCP dependency: REST fallback -- GET /artifactory/api/system/version
# Exit codes:     0 success, 1 general failure, 3 auth failure,
#                 10 configuration error.
# Output:         JSON: {version, revision, referenceVersion, matchesReference}
# Security:       TLS validation always on (no disabled certificate verification).
#
# Example:
#   ./get-version.sh --base-url "https://artifactory.example.internal"

set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TOKEN_FILE="$REPO_ROOT/.github/local-secrets/jfrog-token.txt"
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
[[ -n "$TOKEN" && "$TOKEN" != "REPLACE_WITH_REAL_JFROG_TOKEN" ]] || { echo "ERROR: JFrog token file is a placeholder or empty." >&2; exit 3; }

# Single source of truth: policies/versions-and-sources.yaml#jfrog.reference_version_at_generation_time
REFERENCE_VERSION="7.161.32"
VERSIONS_FILE="$REPO_ROOT/policies/versions-and-sources.yaml"
if [[ -f "$VERSIONS_FILE" ]]; then
    EXTRACTED=$(grep -oP 'reference_version_at_generation_time:\s*"\K[^"]+' "$VERSIONS_FILE" 2>/dev/null || true)
    [[ -n "$EXTRACTED" ]] && REFERENCE_VERSION="$EXTRACTED"
fi

RESP_FILE=$(mktemp)
trap 'rm -f "$RESP_FILE"' EXIT
HTTP_CODE=$(curl --silent --show-error --tlsv1.2 -o "$RESP_FILE" -w "%{http_code}" \
    -X GET "$BASE_URL/artifactory/api/system/version" -H "Authorization: Bearer $TOKEN" -H "Accept: application/json") || true

if [[ "$HTTP_CODE" == "401" ]]; then echo "ERROR: Authentication failure." >&2; exit 3; fi
[[ "$HTTP_CODE" == "200" ]] || { echo "ERROR: get-version failed with HTTP $HTTP_CODE" >&2; exit 1; }

VERSION=$(jq -r '.version' "$RESP_FILE")
REVISION=$(jq -r '.revision' "$RESP_FILE")
MATCHES="false"
[[ "$VERSION" == "$REFERENCE_VERSION" ]] && MATCHES="true"

if [[ "$MATCHES" == "false" ]]; then
    echo "WARNING: Detected Artifactory version '$VERSION' differs from the documented reference '$REFERENCE_VERSION'. Re-verify against https://docs.jfrog.com/releases/docs/artifactory-release-notes if relying on version-specific behavior." >&2
fi

jq -n --arg version "$VERSION" --arg revision "$REVISION" --arg referenceVersion "$REFERENCE_VERSION" --argjson matchesReference "$MATCHES" \
    '{version:$version, revision:$revision, referenceVersion:$referenceVersion, matchesReference:$matchesReference}'
exit 0
