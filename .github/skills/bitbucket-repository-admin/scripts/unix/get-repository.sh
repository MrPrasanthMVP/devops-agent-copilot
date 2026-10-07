#!/usr/bin/env bash
# get-repository.sh - READ_ONLY: Retrieves a Bitbucket DC repository's settings.
#
# Purpose: Fetch current repository configuration (GET, no mutation).
# Supported OS: Linux, macOS (Bash).
# Dependencies: scripts/common/common.sh (curl, jq)
# Parameters: --base-url --project-key --repository-slug --user
# Authentication: Bitbucket HTTP access token (POC: local-secrets).
# Required permissions: Bitbucket "Read" project/repository permission.
# Approval requirements: NONE.
# Dry-run: not applicable.
# API/MCP dependency: REST fallback; prefer Bitbucket DC MCP read tool when available.
# Exit codes: 0 success, 1 general failure.
# Output: repository JSON on stdout.
# Verification: N/A.
# Audit: writes one READ audit record.
# Security: TLS enforced; token never logged/printed.
#
# Example:
#   ./get-repository.sh --base-url https://bitbucket.example.com \
#     --project-key ABC --repository-slug test-repo --user jdoe

set -euo pipefail
SCRIPT_VERSION="1.0.0"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../../../../scripts/common/common.sh"

BASE_URL="" PROJECT_KEY="" REPO_SLUG="" USER_NAME=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --base-url) BASE_URL="$2"; shift 2 ;;
    --project-key) PROJECT_KEY="$2"; shift 2 ;;
    --repository-slug) REPO_SLUG="$2"; shift 2 ;;
    --user) USER_NAME="$2"; shift 2 ;;
    *) echo "Unknown argument: $1" >&2; exit "$EXIT_INVALID_PARAMETERS" ;;
  esac
done
[[ -z "$BASE_URL" || -z "$PROJECT_KEY" || -z "$REPO_SLUG" || -z "$USER_NAME" ]] && { echo "Missing required arguments" >&2; exit "$EXIT_INVALID_PARAMETERS"; }

OPERATION_ID="$(new_operation_id)"
TARGET="$PROJECT_KEY/$REPO_SLUG"
URI="$BASE_URL/rest/api/1.0/projects/$PROJECT_KEY/repos/$REPO_SLUG"
TOKEN="$(read_local_secret bitbucket)"

if RESPONSE="$(invoke_secure_rest GET "$URI" "$TOKEN")"; then
  write_audit_log "$OPERATION_ID" "$USER_NAME" "bitbucket" "9.4.5" "repository" "GET" "$TARGET" \
    "rest-api" "bitbucket-repository-admin" "get-repository.sh" "$SCRIPT_VERSION" \
    "READ_ONLY" false "NOT_REQUIRED" "SUCCESS" "NOT_APPLICABLE" "null"
  echo "$RESPONSE"
  exit "$EXIT_SUCCESS"
else
  write_audit_log "$OPERATION_ID" "$USER_NAME" "bitbucket" "9.4.5" "repository" "GET" "$TARGET" \
    "rest-api" "bitbucket-repository-admin" "get-repository.sh" "$SCRIPT_VERSION" \
    "READ_ONLY" false "NOT_REQUIRED" "FAILURE" "NOT_APPLICABLE" "request failed"
  echo "ERROR: failed to retrieve repository '$TARGET'" >&2
  exit "$EXIT_GENERAL_FAILURE"
fi
