#!/usr/bin/env bash
# get-artifact-info.sh - READ_ONLY: Retrieves storage info for one artifact.
#
# Purpose: Fetch size/checksum/metadata for an artifact (GET only).
# Supported OS: Linux, macOS (Bash).
# Dependencies: scripts/common/common.sh
# Parameters: --base-url --repo-key --item-path --user
# Authentication: JFrog access token (POC: local-secrets).
# Required permissions: read access on the target repository.
# Approval requirements: NONE.
# Dry-run: not applicable.
# API/MCP dependency: REST fallback (GET /artifactory/api/storage/{repoKey}/{itemPath}).
# Exit codes: 0 success, 1 general failure.
# Output: storage info JSON on stdout.
# Verification: N/A.
# Audit: writes one READ audit record.
# Security: TLS enforced; --item-path rejected if it contains ".."; token never logged.
#
# Example:
#   ./get-artifact-info.sh --base-url https://jfrog.example.com \
#     --repo-key releases-local --item-path "com/example/app/1.0/app.jar" --user jdoe

set -euo pipefail
SCRIPT_VERSION="1.0.0"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../../../../scripts/common/common.sh"

BASE_URL="" REPO_KEY="" ITEM_PATH="" USER_NAME=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --base-url) BASE_URL="$2"; shift 2 ;;
    --repo-key) REPO_KEY="$2"; shift 2 ;;
    --item-path) ITEM_PATH="$2"; shift 2 ;;
    --user) USER_NAME="$2"; shift 2 ;;
    *) echo "Unknown argument: $1" >&2; exit "$EXIT_INVALID_PARAMETERS" ;;
  esac
done
[[ -z "$BASE_URL" || -z "$REPO_KEY" || -z "$ITEM_PATH" || -z "$USER_NAME" ]] && { echo "Missing required arguments" >&2; exit "$EXIT_INVALID_PARAMETERS"; }
if [[ "$ITEM_PATH" == *".."* ]]; then echo "ERROR: --item-path must not contain '..'" >&2; exit "$EXIT_INVALID_PARAMETERS"; fi

OPERATION_ID="$(new_operation_id)"
TARGET="$REPO_KEY/$ITEM_PATH"
URI="$BASE_URL/artifactory/api/storage/$REPO_KEY/$ITEM_PATH"
TOKEN="$(read_local_secret jfrog)"

if RESPONSE="$(invoke_secure_rest GET "$URI" "$TOKEN")"; then
  write_audit_log "$OPERATION_ID" "$USER_NAME" "jfrog" "runtime-detected" "artifact" "GET" "$TARGET" \
    "rest-api" "jfrog-artifacts" "get-artifact-info.sh" "$SCRIPT_VERSION" \
    "READ_ONLY" false "NOT_REQUIRED" "SUCCESS" "NOT_APPLICABLE" "null"
  echo "$RESPONSE"
  exit "$EXIT_SUCCESS"
else
  write_audit_log "$OPERATION_ID" "$USER_NAME" "jfrog" "runtime-detected" "artifact" "GET" "$TARGET" \
    "rest-api" "jfrog-artifacts" "get-artifact-info.sh" "$SCRIPT_VERSION" \
    "READ_ONLY" false "NOT_REQUIRED" "FAILURE" "NOT_APPLICABLE" "request failed"
  echo "ERROR: failed to retrieve artifact info for '$TARGET'" >&2
  exit "$EXIT_GENERAL_FAILURE"
fi
