#!/usr/bin/env bash
#
# Purpose:        READ-ONLY: Find artifacts older than N days in a given
#                 Artifactory repository via AQL; summarize count/size.
# Supported OS:   Linux, macOS (Bash).
# Dependencies:   bash, curl, jq.
# Authentication: JFrog access token (Bearer), from --token-file.
# Required permissions: Read access to the target repository.
# Approval requirements: None (READ_ONLY).
# API/MCP dependency: REST fallback -- POST /artifactory/api/search/aql
# Exit codes:     0 success, 1 general failure, 2 invalid parameters,
#                 3 auth failure, 4 authorization failure,
#                 8 repository not found, 10 configuration error.
# Output:         JSON: {candidates:[...], count, totalSizeBytes, criteria}
# Audit:          Appends a FIND audit record (READ_ONLY).
# Security:       TLS validation always on (no disabled certificate verification).
#
# Example:
#   ./find-old-artifacts.sh --base-url "https://artifactory.example.internal" \
#       --repository "releases-local" --older-than-days 180

set -euo pipefail
SCRIPT_VERSION="1.0.0"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../../../.." && pwd)"
TOKEN_FILE="$REPO_ROOT/.github/local-secrets/jfrog-token.txt"

BASE_URL=""; REPOSITORY=""; OLDER_THAN_DAYS=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --base-url) BASE_URL="$2"; shift 2 ;;
        --repository) REPOSITORY="$2"; shift 2 ;;
        --older-than-days) OLDER_THAN_DAYS="$2"; shift 2 ;;
        --token-file) TOKEN_FILE="$2"; shift 2 ;;
        *) echo "Unknown argument: $1" >&2; exit 2 ;;
    esac
done

command -v curl >/dev/null 2>&1 || { echo "ERROR: curl is required." >&2; exit 10; }
command -v jq >/dev/null 2>&1 || { echo "ERROR: jq is required." >&2; exit 10; }
for v in BASE_URL REPOSITORY OLDER_THAN_DAYS; do
    [[ -n "${!v}" ]] || { echo "ERROR: missing required argument for $v." >&2; exit 2; }
done
[[ "$REPOSITORY" =~ ^[A-Za-z0-9_][A-Za-z0-9_.-]*$ ]] || { echo "ERROR: invalid repository key." >&2; exit 2; }

[[ -f "$TOKEN_FILE" ]] || { echo "ERROR: token file not found: $TOKEN_FILE" >&2; exit 3; }
TOKEN="$(tr -d '\n\r' < "$TOKEN_FILE")"
[[ -n "$TOKEN" && "$TOKEN" != "REPLACE_WITH_REAL_JFROG_TOKEN" ]] || { echo "ERROR: JFrog token file is a placeholder or empty." >&2; exit 3; }

CUTOFF=$(date -u -d "-${OLDER_THAN_DAYS} days" +%Y-%m-%dT%H:%M:%S.000Z 2>/dev/null || date -u -v-"${OLDER_THAN_DAYS}"d +%Y-%m-%dT%H:%M:%S.000Z)
AQL="items.find({\"repo\":\"$REPOSITORY\",\"created\":{\"\$before\":\"$CUTOFF\"}})"

RESP_FILE=$(mktemp)
trap 'rm -f "$RESP_FILE"' EXIT
HTTP_CODE=$(curl --silent --show-error --tlsv1.2 -o "$RESP_FILE" -w "%{http_code}" \
    -X POST "$BASE_URL/artifactory/api/search/aql" \
    -H "Authorization: Bearer $TOKEN" -H "Content-Type: text/plain" --data "$AQL") || true

case "$HTTP_CODE" in
    200) ;;
    401) echo "ERROR: Authentication failure." >&2; exit 3 ;;
    403) echo "ERROR: Authorization failure." >&2; exit 4 ;;
    404) echo "ERROR: Repository not found: $REPOSITORY" >&2; exit 8 ;;
    *) echo "ERROR: AQL search failed with HTTP $HTTP_CODE" >&2; exit 1 ;;
esac

COUNT=$(jq '.results | length' "$RESP_FILE")
TOTAL_SIZE=$(jq '[.results[].size // 0] | add // 0' "$RESP_FILE")
CANDIDATES=$(jq -c '[.results[] | {repo, path, name, size, created}]' "$RESP_FILE")

TIMESTAMP="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
AUDIT_LINE=$(jq -n \
    --arg timestamp "$TIMESTAMP" --arg user "${USER:-unknown}" --arg target "$REPOSITORY" --arg scriptVersion "$SCRIPT_VERSION" \
    '{timestamp:$timestamp, operationId:null, user:$user, system:"jfrog", systemVersion:"detect-at-runtime",
      resource:"artifact", operation:"FIND", target:$target, executionMechanism:"rest-api",
      skill:"jfrog-cleanup", script:"scripts/unix/find-old-artifacts.sh", scriptVersion:$scriptVersion,
      risk:"READ_ONLY", approvalRequired:false, approvalStatus:"NOT_REQUIRED", result:"SUCCESS",
      verification:"NOT_APPLICABLE", error:null}')
echo "$AUDIT_LINE" >> "$REPO_ROOT/logs/enterprise-devops-audit.jsonl" || true

jq -n --argjson candidates "$CANDIDATES" --argjson count "$COUNT" --argjson totalSizeBytes "$TOTAL_SIZE" \
    --arg criteria "created before $CUTOFF (older than $OLDER_THAN_DAYS days) in repository '$REPOSITORY'" \
    '{candidates:$candidates, count:$count, totalSizeBytes:$totalSizeBytes, criteria:$criteria}'

exit 0
