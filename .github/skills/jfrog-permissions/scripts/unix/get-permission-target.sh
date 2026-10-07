#!/usr/bin/env bash
# get-permission-target.sh - READ_ONLY: Retrieves a permission target (v2).
#
# Purpose: Fetch current permission target definition (GET only).
# Supported OS: Linux, macOS (Bash).
# Dependencies: scripts/common/common.sh
# Parameters: --base-url --permission-target-name --user
# Authentication: JFrog access token (POC: local-secrets).
# Required permissions: admin or "Manage" permission on the target.
# Approval requirements: NONE.
# Dry-run: not applicable.
# API/MCP dependency: REST fallback (GET /artifactory/api/v2/security/permissions/{name}).
# Exit codes: 0 success, 1 general failure.
# Output: permission target JSON on stdout.
# Verification: N/A.
# Audit: writes one READ audit record.
# Security: TLS enforced; token never logged/printed.
#
# Example:
#   ./get-permission-target.sh --base-url https://jfrog.example.com \
#     --permission-target-name releases-local-perm --user jdoe

set -euo pipefail
SCRIPT_VERSION="1.0.0"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../../../../scripts/common/common.sh"

BASE_URL="" NAME="" USER_NAME=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --base-url) BASE_URL="$2"; shift 2 ;;
    --permission-target-name) NAME="$2"; shift 2 ;;
    --user) USER_NAME="$2"; shift 2 ;;
    *) echo "Unknown argument: $1" >&2; exit "$EXIT_INVALID_PARAMETERS" ;;
  esac
done
[[ -z "$BASE_URL" || -z "$NAME" || -z "$USER_NAME" ]] && { echo "Missing required arguments" >&2; exit "$EXIT_INVALID_PARAMETERS"; }

OPERATION_ID="$(new_operation_id)"
URI="$BASE_URL/artifactory/api/v2/security/permissions/$NAME"
TOKEN="$(read_local_secret jfrog)"

if RESPONSE="$(invoke_secure_rest GET "$URI" "$TOKEN")"; then
  write_audit_log "$OPERATION_ID" "$USER_NAME" "jfrog" "runtime-detected" "permission_target" "GET" "$NAME" \
    "rest-api" "jfrog-permissions" "get-permission-target.sh" "$SCRIPT_VERSION" \
    "READ_ONLY" false "NOT_REQUIRED" "SUCCESS" "NOT_APPLICABLE" "null"
  echo "$RESPONSE"
  exit "$EXIT_SUCCESS"
else
  write_audit_log "$OPERATION_ID" "$USER_NAME" "jfrog" "runtime-detected" "permission_target" "GET" "$NAME" \
    "rest-api" "jfrog-permissions" "get-permission-target.sh" "$SCRIPT_VERSION" \
    "READ_ONLY" false "NOT_REQUIRED" "FAILURE" "NOT_APPLICABLE" "request failed"
  echo "ERROR: failed to retrieve permission target '$NAME'" >&2
  exit "$EXIT_GENERAL_FAILURE"
fi
