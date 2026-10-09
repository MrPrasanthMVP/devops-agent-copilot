#!/usr/bin/env bash
#
# Purpose:        READ-ONLY: Discover the running SonarQube
#                 Server/Community Build version at runtime. Applies to
#                 the Server (self-managed) deployment only -- SonarQube
#                 Cloud is continuously deployed and has no server
#                 version to discover (same reasoning as Jira/Confluence
#                 Cloud). Mandatory version discovery per Section 38;
#                 mirrors scripts/jfrog/get-version.sh.
# Supported OS:   Linux, macOS (Bash).
# Dependencies:   bash, curl, jq.
# Authentication: SonarQube user token (Bearer).
# Approval requirements: None (READ_ONLY).
# API/MCP dependency: REST fallback -- GET /api/system/status
# Exit codes:     0 success, 1 general failure, 3 auth failure,
#                 10 configuration error.
# Output:         JSON: {version, status, id, referenceVersion, matchesReference}
# Security:       TLS validation always on (no disabled certificate verification).
#
# Example:
#   ./get-version.sh --base-url "https://sonarqube.example.internal"

set -euo pipefail
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
TOKEN_FILE="$REPO_ROOT/.github/local-secrets/sonarqube-token.txt"

# Single source of truth: policies/versions-and-sources.yaml#sonarqube.server.reference_version_at_generation_time
# ALL SonarQube Server/Community Build versions are supported; this is
# only a last-verified reference baseline for informational
# drift-tracking, never a restriction.
REFERENCE_VERSION="26.9.0.129388"
VERSIONS_FILE="$REPO_ROOT/policies/versions-and-sources.yaml"
if [[ -f "$VERSIONS_FILE" ]]; then
    EXTRACTED=$(awk '/^sonarqube:/{f=1;next} f && /^[^[:space:]]/{f=0} f' "$VERSIONS_FILE" \
        | grep -oP 'reference_version_at_generation_time:\s*"\K[^"]+' 2>/dev/null | head -1 || true)
    [[ -n "$EXTRACTED" ]] && REFERENCE_VERSION="$EXTRACTED"
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
[[ -n "$TOKEN" && "$TOKEN" != "REPLACE_WITH_REAL_SONARQUBE_TOKEN" ]] || { echo "ERROR: SonarQube token file is a placeholder or empty." >&2; exit 3; }

RESP_FILE=$(mktemp)
trap 'rm -f "$RESP_FILE"' EXIT
HTTP_CODE=$(curl --silent --show-error --tlsv1.2 -o "$RESP_FILE" -w "%{http_code}" \
    -X GET "$BASE_URL/api/system/status" -H "Authorization: Bearer $TOKEN" -H "Accept: application/json") || true

if [[ "$HTTP_CODE" == "401" ]]; then echo "ERROR: Authentication failure." >&2; exit 3; fi
[[ "$HTTP_CODE" == "200" ]] || { echo "ERROR: get-version failed with HTTP $HTTP_CODE" >&2; exit 1; }

VERSION=$(jq -r '.version' "$RESP_FILE")
STATUS_FIELD=$(jq -r '.status' "$RESP_FILE")
ID_FIELD=$(jq -r '.id' "$RESP_FILE")
MATCHES="false"
[[ "$VERSION" == "$REFERENCE_VERSION" ]] && MATCHES="true"

if [[ "$MATCHES" == "false" ]]; then
    echo "WARNING: Detected SonarQube Server version '$VERSION' differs from the documented reference '$REFERENCE_VERSION'. All SonarQube Server/Community Build versions are supported -- this is informational only; re-verify Web API compatibility before relying on $REFERENCE_VERSION-specific behavior." >&2
fi

jq -n --arg version "$VERSION" --arg status "$STATUS_FIELD" --arg id "$ID_FIELD" --arg referenceVersion "$REFERENCE_VERSION" --argjson matchesReference "$MATCHES" \
    '{version:$version, status:$status, id:$id, referenceVersion:$referenceVersion, matchesReference:$matchesReference}'
exit 0
