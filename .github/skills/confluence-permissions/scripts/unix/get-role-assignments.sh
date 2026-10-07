#!/usr/bin/env bash
# get-role-assignments.sh - READ_ONLY: Retrieves role assignments for a
# Confluence Cloud space.
# Supported OS: Linux, macOS. Dependencies: scripts/common/common.sh
# Parameters: --site-url --space-id --email --api-token --user
# Authentication: Confluence Cloud basic auth. Required permissions: space "admin" role.
# Approval requirements: NONE. API/MCP dependency: REST fallback
#   (GET /wiki/api/v2/spaces/{id}/role-assignments).
# Exit codes: 0 success, 1 general failure. Output: role assignments JSON.
# Verification: N/A. Audit: one READ record. Security: TLS enforced, no logged token.
#
# Example: ./get-role-assignments.sh --site-url https://example.atlassian.net \
#   --space-id 123456 --email jdoe@example.com --api-token "$CONFLUENCE_API_TOKEN" --user jdoe

set -euo pipefail
SCRIPT_VERSION="1.0.0"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../../../../scripts/common/common.sh"

SITE_URL="" SPACE_ID="" EMAIL="" API_TOKEN="" USER_NAME=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --site-url) SITE_URL="$2"; shift 2 ;;
    --space-id) SPACE_ID="$2"; shift 2 ;;
    --email) EMAIL="$2"; shift 2 ;;
    --api-token) API_TOKEN="$2"; shift 2 ;;
    --user) USER_NAME="$2"; shift 2 ;;
    *) echo "Unknown argument: $1" >&2; exit "$EXIT_INVALID_PARAMETERS" ;;
  esac
done
[[ -z "$SITE_URL" || -z "$SPACE_ID" || -z "$EMAIL" || -z "$API_TOKEN" || -z "$USER_NAME" ]] && { echo "Missing required arguments" >&2; exit "$EXIT_INVALID_PARAMETERS"; }

OPERATION_ID="$(new_operation_id)"
URI="$SITE_URL/wiki/api/v2/spaces/$SPACE_ID/role-assignments"
BASIC="$(printf '%s:%s' "$EMAIL" "$API_TOKEN" | base64 | tr -d '\n')"

if RESPONSE="$(invoke_secure_rest GET "$URI" "$BASIC" "Basic")"; then
  write_audit_log "$OPERATION_ID" "$USER_NAME" "confluence" "cloud" "space_role" "GET" "$SPACE_ID" \
    "rest-api" "confluence-permissions" "get-role-assignments.sh" "$SCRIPT_VERSION" \
    "READ_ONLY" false "NOT_REQUIRED" "SUCCESS" "NOT_APPLICABLE" "null"
  echo "$RESPONSE"
  exit "$EXIT_SUCCESS"
else
  write_audit_log "$OPERATION_ID" "$USER_NAME" "confluence" "cloud" "space_role" "GET" "$SPACE_ID" \
    "rest-api" "confluence-permissions" "get-role-assignments.sh" "$SCRIPT_VERSION" \
    "READ_ONLY" false "NOT_REQUIRED" "FAILURE" "NOT_APPLICABLE" "request failed"
  echo "ERROR: failed to retrieve role assignments for space '$SPACE_ID'" >&2
  exit "$EXIT_GENERAL_FAILURE"
fi
