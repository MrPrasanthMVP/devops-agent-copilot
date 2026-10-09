#!/usr/bin/env bash
# search-issues.sh - READ_ONLY: Searches SonarQube issues.
#
# Purpose: Fetch issues matching project/assignee/status filters (GET, no mutation).
# Supported OS: Linux, macOS (Bash).
# Dependencies: scripts/common/common.sh
# Parameters: --base-url [--organization] [--project-keys] [--issue-keys]
#   [--assignees] [--statuses] --user
# Authentication: SonarQube user token (POC: local-secrets).
# Required permissions: Browse permission on the project(s) searched.
# Approval requirements: NONE - READ_ONLY operations execute immediately.
# Deployment: works against BOTH Server and Cloud (pass --organization for Cloud).
# API/MCP dependency: REST fallback (GET api/issues/search).
# Exit codes: 0 success, 3 auth failure, 1 general failure.
# Output: issues JSON array on stdout.
# Verification: N/A (this script IS a read, not something to verify).
# Audit: writes one READ audit record.
# Security: TLS enforced; token never logged or printed.
#
# Example:
#   ./search-issues.sh --base-url https://sonarqube.example.internal --project-keys my-app --user jdoe

set -euo pipefail
SCRIPT_VERSION="1.0.0"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../../../../scripts/common/common.sh"

BASE_URL="" ORGANIZATION="" PROJECT_KEYS="" ISSUE_KEYS="" ASSIGNEES="" STATUSES="" USER_NAME=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --base-url) BASE_URL="$2"; shift 2 ;;
    --organization) ORGANIZATION="$2"; shift 2 ;;
    --project-keys) PROJECT_KEYS="$2"; shift 2 ;;
    --issue-keys) ISSUE_KEYS="$2"; shift 2 ;;
    --assignees) ASSIGNEES="$2"; shift 2 ;;
    --statuses) STATUSES="$2"; shift 2 ;;
    --user) USER_NAME="$2"; shift 2 ;;
    *) echo "Unknown argument: $1" >&2; exit "$EXIT_INVALID_PARAMETERS" ;;
  esac
done
[[ -z "$BASE_URL" || -z "$USER_NAME" ]] && { echo "Missing required arguments" >&2; exit "$EXIT_INVALID_PARAMETERS"; }

OPERATION_ID="$(new_operation_id)"
if [[ -n "$PROJECT_KEYS" ]]; then TARGET="projects:$PROJECT_KEYS"
elif [[ -n "$ISSUE_KEYS" ]]; then TARGET="issues:$ISSUE_KEYS"
else TARGET="all-issues"; fi

URI="$BASE_URL/api/issues/search?ps=500"
[[ -n "$PROJECT_KEYS" ]] && URI="$URI&componentKeys=$PROJECT_KEYS"
[[ -n "$ISSUE_KEYS" ]] && URI="$URI&issues=$ISSUE_KEYS"
[[ -n "$ASSIGNEES" ]] && URI="$URI&assignees=$ASSIGNEES"
[[ -n "$STATUSES" ]] && URI="$URI&issueStatuses=$STATUSES"
[[ -n "$ORGANIZATION" ]] && URI="$URI&organization=$ORGANIZATION"

TOKEN="$(read_local_secret sonarqube)"

if RESULT="$(invoke_secure_rest GET "$URI" "$TOKEN")"; then
  write_audit_log "$OPERATION_ID" "$USER_NAME" "sonarqube" "runtime-detected" "issue" "SEARCH" "$TARGET" \
    "rest-api" "sonarqube-issues" "search-issues.sh" "$SCRIPT_VERSION" \
    "READ_ONLY" false "NOT_REQUIRED" "SUCCESS" "NOT_APPLICABLE" "null"
  echo "$RESULT"
  exit "$EXIT_SUCCESS"
else
  write_audit_log "$OPERATION_ID" "$USER_NAME" "sonarqube" "runtime-detected" "issue" "SEARCH" "$TARGET" \
    "rest-api" "sonarqube-issues" "search-issues.sh" "$SCRIPT_VERSION" \
    "READ_ONLY" false "NOT_REQUIRED" "FAILURE" "NOT_APPLICABLE" "request failed"
  echo "ERROR: failed to search SonarQube issues" >&2
  exit "$EXIT_GENERAL_FAILURE"
fi
