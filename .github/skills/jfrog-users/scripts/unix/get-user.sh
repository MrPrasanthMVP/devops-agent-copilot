#!/usr/bin/env bash
# get-user.sh - READ_ONLY: Retrieves a JFrog Platform user account.
#
# Purpose: Fetch current user account details (GET only).
# Supported OS: Linux, macOS (Bash).
# Dependencies: scripts/common/common.sh
# Parameters: --base-url --username --user
# Authentication: JFrog access token (POC: local-secrets).
# Required permissions: admin privileges.
# Approval requirements: NONE.
# Dry-run: not applicable.
# API/MCP dependency: REST fallback (GET /access/api/v2/users/{username}).
# Exit codes: 0 success, 1 general failure.
# Output: user JSON on stdout.
# Verification: N/A.
# Audit: writes one READ audit record.
# Security: TLS enforced; token never logged/printed.
#
# Example:
#   ./get-user.sh --base-url https://jfrog.example.com --username jdoe --user admin-jdoe

set -euo pipefail
SCRIPT_VERSION="1.0.0"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../../../../scripts/common/common.sh"

BASE_URL="" USERNAME="" USER_NAME=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --base-url) BASE_URL="$2"; shift 2 ;;
    --username) USERNAME="$2"; shift 2 ;;
    --user) USER_NAME="$2"; shift 2 ;;
    *) echo "Unknown argument: $1" >&2; exit "$EXIT_INVALID_PARAMETERS" ;;
  esac
done
[[ -z "$BASE_URL" || -z "$USERNAME" || -z "$USER_NAME" ]] && { echo "Missing required arguments" >&2; exit "$EXIT_INVALID_PARAMETERS"; }

OPERATION_ID="$(new_operation_id)"
URI="$BASE_URL/access/api/v2/users/$USERNAME"
TOKEN="$(read_local_secret jfrog)"

if RESPONSE="$(invoke_secure_rest GET "$URI" "$TOKEN")"; then
  write_audit_log "$OPERATION_ID" "$USER_NAME" "jfrog" "runtime-detected" "user" "GET" "$USERNAME" \
    "rest-api" "jfrog-users" "get-user.sh" "$SCRIPT_VERSION" \
    "READ_ONLY" false "NOT_REQUIRED" "SUCCESS" "NOT_APPLICABLE" "null"
  echo "$RESPONSE"
  exit "$EXIT_SUCCESS"
else
  write_audit_log "$OPERATION_ID" "$USER_NAME" "jfrog" "runtime-detected" "user" "GET" "$USERNAME" \
    "rest-api" "jfrog-users" "get-user.sh" "$SCRIPT_VERSION" \
    "READ_ONLY" false "NOT_REQUIRED" "FAILURE" "NOT_APPLICABLE" "request failed"
  echo "ERROR: failed to retrieve user '$USERNAME'" >&2
  exit "$EXIT_GENERAL_FAILURE"
fi
