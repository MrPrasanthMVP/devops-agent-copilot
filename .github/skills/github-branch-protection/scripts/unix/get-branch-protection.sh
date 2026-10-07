#!/usr/bin/env bash
# get-branch-protection.sh - READ_ONLY: Retrieves branch protection
# settings for a GitHub Enterprise (Cloud or Server) repository branch.
#
# Purpose: Fetch current branch protection configuration (GET only).
# Supported OS: Linux, macOS (Bash).
# Dependencies: scripts/common/common.sh
# Parameters: --api-base-url --owner --repo --branch --user
# Authentication: GitHub token (POC: local-secrets).
# Required permissions: repository admin read access.
# Approval requirements: NONE.
# Dry-run: not applicable.
# API/MCP dependency: REST fallback; prefer discovered GitHub MCP read tool.
# Exit codes: 0 success, 1 general failure.
# Output: branch protection JSON on stdout.
# Verification: N/A.
# Audit: writes one READ audit record.
# Security: TLS enforced; token never logged/printed.
#
# Example:
#   ./get-branch-protection.sh --api-base-url https://api.github.com \
#     --owner myorg --repo myrepo --branch main --user jdoe

set -euo pipefail
SCRIPT_VERSION="1.0.0"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../../../../scripts/common/common.sh"

API_BASE_URL="" OWNER="" REPO="" BRANCH="" USER_NAME=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --api-base-url) API_BASE_URL="$2"; shift 2 ;;
    --owner) OWNER="$2"; shift 2 ;;
    --repo) REPO="$2"; shift 2 ;;
    --branch) BRANCH="$2"; shift 2 ;;
    --user) USER_NAME="$2"; shift 2 ;;
    *) echo "Unknown argument: $1" >&2; exit "$EXIT_INVALID_PARAMETERS" ;;
  esac
done
[[ -z "$API_BASE_URL" || -z "$OWNER" || -z "$REPO" || -z "$BRANCH" || -z "$USER_NAME" ]] && { echo "Missing required arguments" >&2; exit "$EXIT_INVALID_PARAMETERS"; }

OPERATION_ID="$(new_operation_id)"
TARGET="$OWNER/$REPO@$BRANCH"
URI="$API_BASE_URL/repos/$OWNER/$REPO/branches/$BRANCH/protection"
TOKEN="$(read_local_secret github)"

if RESPONSE="$(invoke_secure_rest GET "$URI" "$TOKEN")"; then
  write_audit_log "$OPERATION_ID" "$USER_NAME" "github" "runtime-detected" "branch_protection" "GET" "$TARGET" \
    "rest-api" "github-branch-protection" "get-branch-protection.sh" "$SCRIPT_VERSION" \
    "READ_ONLY" false "NOT_REQUIRED" "SUCCESS" "NOT_APPLICABLE" "null"
  echo "$RESPONSE"
  exit "$EXIT_SUCCESS"
else
  write_audit_log "$OPERATION_ID" "$USER_NAME" "github" "runtime-detected" "branch_protection" "GET" "$TARGET" \
    "rest-api" "github-branch-protection" "get-branch-protection.sh" "$SCRIPT_VERSION" \
    "READ_ONLY" false "NOT_REQUIRED" "FAILURE" "NOT_APPLICABLE" "request failed"
  echo "ERROR: failed to retrieve branch protection for '$TARGET'" >&2
  exit "$EXIT_GENERAL_FAILURE"
fi
