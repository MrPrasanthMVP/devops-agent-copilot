#!/usr/bin/env bash
# list-webhooks.sh - READ_ONLY: Lists SonarQube webhooks (global, or
# project-scoped).
#
# Purpose: Fetch webhook configuration (GET, no mutation).
# Supported OS: Linux, macOS (Bash).
# Dependencies: scripts/common/common.sh
# Parameters: --base-url [--project-key] [--organization] --user
# Authentication: SonarQube user token (POC: local-secrets).
# Required permissions: 'Administer System' (global) or 'Administer' on
#   the project (project-scoped).
# Approval requirements: NONE - READ_ONLY operations execute immediately.
# Deployment: works against BOTH Server and Cloud (pass --organization for Cloud).
# API/MCP dependency: REST fallback (GET api/webhooks/list).
# Exit codes: 0 success, 3 auth failure, 1 general failure.
# Output: webhooks JSON array on stdout.
# Verification: N/A (this script IS a read, not something to verify).
# Audit: writes one READ audit record.
# Security: TLS enforced; token never logged or printed.
#
# Example:
#   ./list-webhooks.sh --base-url https://sonarqube.example.internal --user jdoe

set -euo pipefail
SCRIPT_VERSION="1.0.0"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../../../../scripts/common/common.sh"

BASE_URL="" PROJECT_KEY="" ORGANIZATION="" USER_NAME=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --base-url) BASE_URL="$2"; shift 2 ;;
    --project-key) PROJECT_KEY="$2"; shift 2 ;;
    --organization) ORGANIZATION="$2"; shift 2 ;;
    --user) USER_NAME="$2"; shift 2 ;;
    *) echo "Unknown argument: $1" >&2; exit "$EXIT_INVALID_PARAMETERS" ;;
  esac
done
[[ -z "$BASE_URL" || -z "$USER_NAME" ]] && { echo "Missing required arguments" >&2; exit "$EXIT_INVALID_PARAMETERS"; }

OPERATION_ID="$(new_operation_id)"
if [[ -n "$PROJECT_KEY" ]]; then TARGET="$PROJECT_KEY"; else TARGET="global"; fi

URI="$BASE_URL/api/webhooks/list"
QS=""
[[ -n "$PROJECT_KEY" ]] && QS="${QS:+$QS&}project=$PROJECT_KEY"
[[ -n "$ORGANIZATION" ]] && QS="${QS:+$QS&}organization=$ORGANIZATION"
[[ -n "$QS" ]] && URI="$URI?$QS"

TOKEN="$(read_local_secret sonarqube)"

if RESULT="$(invoke_secure_rest GET "$URI" "$TOKEN")"; then
  write_audit_log "$OPERATION_ID" "$USER_NAME" "sonarqube" "runtime-detected" "webhook" "LIST" "$TARGET" \
    "rest-api" "sonarqube-webhooks" "list-webhooks.sh" "$SCRIPT_VERSION" \
    "READ_ONLY" false "NOT_REQUIRED" "SUCCESS" "NOT_APPLICABLE" "null"
  echo "$RESULT"
  exit "$EXIT_SUCCESS"
else
  write_audit_log "$OPERATION_ID" "$USER_NAME" "sonarqube" "runtime-detected" "webhook" "LIST" "$TARGET" \
    "rest-api" "sonarqube-webhooks" "list-webhooks.sh" "$SCRIPT_VERSION" \
    "READ_ONLY" false "NOT_REQUIRED" "FAILURE" "NOT_APPLICABLE" "request failed"
  echo "ERROR: failed to list SonarQube webhooks" >&2
  exit "$EXIT_GENERAL_FAILURE"
fi
