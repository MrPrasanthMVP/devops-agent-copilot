#!/usr/bin/env bash
# get-repository.sh - READ_ONLY: Retrieves a JFrog repository configuration.
#
# Purpose: Fetch current repository configuration (GET, no mutation).
# Supported OS: Linux, macOS (Bash).
# Dependencies: scripts/common/common.sh
# Parameters: --base-url --repo-key --user
# Authentication: JFrog access token (POC: local-secrets).
# Required permissions: read access to repository configuration.
# Approval requirements: NONE.
# Dry-run: not applicable.
# API/MCP dependency: REST fallback (GET /artifactory/api/repositories/{repoKey}).
# Exit codes: 0 success, 1 general failure.
# Output: repository configuration JSON on stdout.
# Verification: N/A.
# Audit: writes one READ audit record.
# Security: TLS enforced; token never logged/printed.
#
# Example:
#   ./get-repository.sh --base-url https://jfrog.example.com --repo-key releases-local --user jdoe

set -euo pipefail
SCRIPT_VERSION="1.0.0"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../../../../scripts/common/common.sh"

BASE_URL="" REPO_KEY="" USER_NAME=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --base-url) BASE_URL="$2"; shift 2 ;;
    --repo-key) REPO_KEY="$2"; shift 2 ;;
    --user) USER_NAME="$2"; shift 2 ;;
    *) echo "Unknown argument: $1" >&2; exit "$EXIT_INVALID_PARAMETERS" ;;
  esac
done
[[ -z "$BASE_URL" || -z "$REPO_KEY" || -z "$USER_NAME" ]] && { echo "Missing required arguments" >&2; exit "$EXIT_INVALID_PARAMETERS"; }
if ! [[ "$REPO_KEY" =~ ^[A-Za-z0-9._-]+$ ]]; then echo "ERROR: --repo-key contains invalid characters." >&2; exit "$EXIT_INVALID_PARAMETERS"; fi

OPERATION_ID="$(new_operation_id)"
URI="$BASE_URL/artifactory/api/repositories/$REPO_KEY"
TOKEN="$(read_local_secret jfrog)"

if RESPONSE="$(invoke_secure_rest GET "$URI" "$TOKEN")"; then
  write_audit_log "$OPERATION_ID" "$USER_NAME" "jfrog" "runtime-detected" "repository" "GET" "$REPO_KEY" \
    "rest-api" "jfrog-repositories" "get-repository.sh" "$SCRIPT_VERSION" \
    "READ_ONLY" false "NOT_REQUIRED" "SUCCESS" "NOT_APPLICABLE" "null"
  echo "$RESPONSE"
  exit "$EXIT_SUCCESS"
else
  write_audit_log "$OPERATION_ID" "$USER_NAME" "jfrog" "runtime-detected" "repository" "GET" "$REPO_KEY" \
    "rest-api" "jfrog-repositories" "get-repository.sh" "$SCRIPT_VERSION" \
    "READ_ONLY" false "NOT_REQUIRED" "FAILURE" "NOT_APPLICABLE" "request failed"
  echo "ERROR: failed to retrieve repository '$REPO_KEY'" >&2
  exit "$EXIT_GENERAL_FAILURE"
fi
