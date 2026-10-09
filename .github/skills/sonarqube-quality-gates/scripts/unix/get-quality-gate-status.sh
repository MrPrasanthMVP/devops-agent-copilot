#!/usr/bin/env bash
# get-quality-gate-status.sh - READ_ONLY: Gets a project's current
# quality gate status (PASSED/FAILED/NONE).
#
# Purpose: Fetch the computed quality gate status for a project's latest
#   analysis (GET, no mutation).
# Supported OS: Linux, macOS (Bash).
# Dependencies: scripts/common/common.sh (curl, jq)
# Parameters: --base-url --project-key [--branch] [--organization] --user
# Authentication: SonarQube user token (POC: local-secrets).
# Required permissions: 'Browse' permission on the project.
# Approval requirements: NONE.
# Deployment: works against BOTH Server and Cloud (pass --organization for Cloud).
# API/MCP dependency: REST fallback; prefer the SonarQube MCP server's
#   quality-gate-status tool when available.
# Exit codes: 0 success, 8 not found, 1 general failure.
# Output: project status JSON on stdout.
# Verification: N/A.
# Audit: writes one READ audit record.
# Security: TLS enforced; token never logged/printed.
#
# Example:
#   ./get-quality-gate-status.sh --base-url https://sonarqube.example.internal --project-key my-app --user jdoe

set -euo pipefail
SCRIPT_VERSION="1.0.0"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../../../../scripts/common/common.sh"

BASE_URL="" PROJECT_KEY="" BRANCH="" ORGANIZATION="" USER_NAME=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --base-url) BASE_URL="$2"; shift 2 ;;
    --project-key) PROJECT_KEY="$2"; shift 2 ;;
    --branch) BRANCH="$2"; shift 2 ;;
    --organization) ORGANIZATION="$2"; shift 2 ;;
    --user) USER_NAME="$2"; shift 2 ;;
    *) echo "Unknown argument: $1" >&2; exit "$EXIT_INVALID_PARAMETERS" ;;
  esac
done
[[ -z "$BASE_URL" || -z "$PROJECT_KEY" || -z "$USER_NAME" ]] && { echo "Missing required arguments" >&2; exit "$EXIT_INVALID_PARAMETERS"; }

OPERATION_ID="$(new_operation_id)"
TARGET="$PROJECT_KEY"
URI="$BASE_URL/api/qualitygates/project_status?projectKey=$PROJECT_KEY"
[[ -n "$BRANCH" ]] && URI="$URI&branch=$BRANCH"
[[ -n "$ORGANIZATION" ]] && URI="$URI&organization=$ORGANIZATION"
TOKEN="$(read_local_secret sonarqube)"

ERR_FILE="$(mktemp)"
trap 'rm -f "$ERR_FILE"' EXIT
if RESPONSE="$(invoke_secure_rest GET "$URI" "$TOKEN" 2>"$ERR_FILE")"; then
  write_audit_log "$OPERATION_ID" "$USER_NAME" "sonarqube" "runtime-detected" "quality_gate" "STATUS" "$TARGET" \
    "rest-api" "sonarqube-quality-gates" "get-quality-gate-status.sh" "$SCRIPT_VERSION" \
    "READ_ONLY" false "NOT_REQUIRED" "SUCCESS" "NOT_APPLICABLE" "null"
  echo "$RESPONSE"
  exit "$EXIT_SUCCESS"
else
  ERR_MSG="$(cat "$ERR_FILE" 2>/dev/null || echo 'request failed')"
  write_audit_log "$OPERATION_ID" "$USER_NAME" "sonarqube" "runtime-detected" "quality_gate" "STATUS" "$TARGET" \
    "rest-api" "sonarqube-quality-gates" "get-quality-gate-status.sh" "$SCRIPT_VERSION" \
    "READ_ONLY" false "NOT_REQUIRED" "FAILURE" "NOT_APPLICABLE" "$ERR_MSG"
  echo "ERROR: failed to get quality gate status for '$TARGET'" >&2
  exit "$EXIT_GENERAL_FAILURE"
fi
