#!/usr/bin/env bash
# list-quality-gates.sh - READ_ONLY: Lists all SonarQube quality gates.
#
# Purpose: Fetch the quality gate list (GET, no mutation).
# Supported OS: Linux, macOS (Bash).
# Dependencies: scripts/common/common.sh (curl, jq)
# Parameters: --base-url [--organization] --user
# Authentication: SonarQube user token (POC: local-secrets).
# Required permissions: none beyond a valid token (instance-wide read).
# Approval requirements: NONE.
# Deployment: works against BOTH Server and Cloud (pass --organization for Cloud).
# API/MCP dependency: REST fallback; prefer the SonarQube MCP server's
#   quality-gate-list tool when available.
# Exit codes: 0 success, 1 general failure.
# Output: quality gates JSON on stdout.
# Verification: N/A.
# Audit: writes one READ audit record.
# Security: TLS enforced; token never logged/printed.
#
# Example:
#   ./list-quality-gates.sh --base-url https://sonarqube.example.internal --user jdoe

set -euo pipefail
SCRIPT_VERSION="1.0.0"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../../../../scripts/common/common.sh"

BASE_URL="" ORGANIZATION="" USER_NAME=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --base-url) BASE_URL="$2"; shift 2 ;;
    --organization) ORGANIZATION="$2"; shift 2 ;;
    --user) USER_NAME="$2"; shift 2 ;;
    *) echo "Unknown argument: $1" >&2; exit "$EXIT_INVALID_PARAMETERS" ;;
  esac
done
[[ -z "$BASE_URL" || -z "$USER_NAME" ]] && { echo "Missing required arguments" >&2; exit "$EXIT_INVALID_PARAMETERS"; }

OPERATION_ID="$(new_operation_id)"
TARGET="all-quality-gates"
URI="$BASE_URL/api/qualitygates/list"
[[ -n "$ORGANIZATION" ]] && URI="$URI?organization=$ORGANIZATION"
TOKEN="$(read_local_secret sonarqube)"

if RESPONSE="$(invoke_secure_rest GET "$URI" "$TOKEN")"; then
  write_audit_log "$OPERATION_ID" "$USER_NAME" "sonarqube" "runtime-detected" "quality_gate" "LIST" "$TARGET" \
    "rest-api" "sonarqube-quality-gates" "list-quality-gates.sh" "$SCRIPT_VERSION" \
    "READ_ONLY" false "NOT_REQUIRED" "SUCCESS" "NOT_APPLICABLE" "null"
  echo "$RESPONSE"
  exit "$EXIT_SUCCESS"
else
  write_audit_log "$OPERATION_ID" "$USER_NAME" "sonarqube" "runtime-detected" "quality_gate" "LIST" "$TARGET" \
    "rest-api" "sonarqube-quality-gates" "list-quality-gates.sh" "$SCRIPT_VERSION" \
    "READ_ONLY" false "NOT_REQUIRED" "FAILURE" "NOT_APPLICABLE" "request failed"
  echo "ERROR: failed to list quality gates" >&2
  exit "$EXIT_GENERAL_FAILURE"
fi
