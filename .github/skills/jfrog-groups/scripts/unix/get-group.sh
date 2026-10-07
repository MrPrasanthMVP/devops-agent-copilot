#!/usr/bin/env bash
# get-group.sh - READ-ONLY: Gets a JFrog Platform group's details.
# No MCP tool covers group CRUD in the verified catalog -- REST fallback.
#
# Purpose: Read one group's configuration.
# Supported OS: Linux, macOS (Bash).
# Dependencies: scripts/common/common.sh
# Parameters: --base-url --group-name
# Authentication: JFrog access token (POC: local-secrets).
# Approval requirements: None (READ_ONLY).
# API/MCP dependency: REST fallback (GET /access/api/v2/groups/{group_name}).
# Exit codes: 0 success, 3 auth failure, 8 target not found, 1 general failure.
# Output: JSON group object.
# Audit: writes one READ_ONLY audit record.
# Security: TLS enforced.
#
# Example:
#   ./get-group.sh --base-url https://jfrog.example.com --group-name build-team

set -euo pipefail
SCRIPT_VERSION="1.0.0"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../../../../scripts/common/common.sh"

BASE_URL="" GROUP_NAME="" USER_NAME="${USER:-unknown}"
while [[ $# -gt 0 ]]; do
  case "$1" in
    --base-url) BASE_URL="$2"; shift 2 ;;
    --group-name) GROUP_NAME="$2"; shift 2 ;;
    --user) USER_NAME="$2"; shift 2 ;;
    *) echo "Unknown argument: $1" >&2; exit "$EXIT_INVALID_PARAMETERS" ;;
  esac
done
[[ -z "$BASE_URL" || -z "$GROUP_NAME" ]] && { echo "Missing required arguments" >&2; exit "$EXIT_INVALID_PARAMETERS"; }

TOKEN="$(read_local_secret jfrog)"
URI="$BASE_URL/access/api/v2/groups/$GROUP_NAME"

if ! RESPONSE="$(invoke_secure_rest GET "$URI" "$TOKEN")"; then
  echo "ERROR: get-group failed for '$GROUP_NAME'" >&2
  exit "$EXIT_GENERAL_FAILURE"
fi

write_audit_log "n/a" "$USER_NAME" "jfrog" "runtime-detected" "group" "GET" "$GROUP_NAME" \
  "rest-api" "jfrog-groups" "get-group.sh" "$SCRIPT_VERSION" \
  "READ_ONLY" false "NOT_REQUIRED" "SUCCESS" "NOT_APPLICABLE" "null"

echo "$RESPONSE"
exit "$EXIT_SUCCESS"
