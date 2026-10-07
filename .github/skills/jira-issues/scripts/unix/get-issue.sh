#!/usr/bin/env bash
# get-issue.sh - READ_ONLY: Retrieves a Jira Cloud issue.
#
# Purpose: Fetch current issue fields (GET, no mutation).
# Supported OS: Linux, macOS (Bash).
# Dependencies: scripts/common/common.sh
# Parameters: --site-url --issue-key --email --api-token --user
# Authentication: Jira Cloud basic auth (email + API token).
# Required permissions: "Browse projects" Jira permission.
# Approval requirements: NONE.
# Dry-run: not applicable.
# API/MCP dependency: REST fallback; prefer discovered Rovo MCP read tool.
# Exit codes: 0 success, 1 general failure.
# Output: issue JSON on stdout.
# Verification: N/A.
# Audit: writes one READ audit record.
# Security: TLS enforced; token never logged/printed.
#
# Example:
#   ./get-issue.sh --site-url https://example.atlassian.net --issue-key ABC-123 \
#     --email jdoe@example.com --api-token "$JIRA_API_TOKEN" --user jdoe

set -euo pipefail
SCRIPT_VERSION="1.0.0"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../../../../scripts/common/common.sh"

SITE_URL="" ISSUE_KEY="" EMAIL="" API_TOKEN="" USER_NAME=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --site-url) SITE_URL="$2"; shift 2 ;;
    --issue-key) ISSUE_KEY="$2"; shift 2 ;;
    --email) EMAIL="$2"; shift 2 ;;
    --api-token) API_TOKEN="$2"; shift 2 ;;
    --user) USER_NAME="$2"; shift 2 ;;
    *) echo "Unknown argument: $1" >&2; exit "$EXIT_INVALID_PARAMETERS" ;;
  esac
done
[[ -z "$SITE_URL" || -z "$ISSUE_KEY" || -z "$EMAIL" || -z "$API_TOKEN" || -z "$USER_NAME" ]] && { echo "Missing required arguments" >&2; exit "$EXIT_INVALID_PARAMETERS"; }

OPERATION_ID="$(new_operation_id)"
URI="$SITE_URL/rest/api/3/issue/$ISSUE_KEY"
BASIC="$(printf '%s:%s' "$EMAIL" "$API_TOKEN" | base64 | tr -d '\n')"

if RESPONSE="$(invoke_secure_rest GET "$URI" "$BASIC" "Basic")"; then
  write_audit_log "$OPERATION_ID" "$USER_NAME" "jira" "cloud" "issue" "GET" "$ISSUE_KEY" \
    "rest-api" "jira-issues" "get-issue.sh" "$SCRIPT_VERSION" \
    "READ_ONLY" false "NOT_REQUIRED" "SUCCESS" "NOT_APPLICABLE" "null"
  echo "$RESPONSE"
  exit "$EXIT_SUCCESS"
else
  write_audit_log "$OPERATION_ID" "$USER_NAME" "jira" "cloud" "issue" "GET" "$ISSUE_KEY" \
    "rest-api" "jira-issues" "get-issue.sh" "$SCRIPT_VERSION" \
    "READ_ONLY" false "NOT_REQUIRED" "FAILURE" "NOT_APPLICABLE" "request failed"
  echo "ERROR: failed to retrieve issue '$ISSUE_KEY'" >&2
  exit "$EXIT_GENERAL_FAILURE"
fi
