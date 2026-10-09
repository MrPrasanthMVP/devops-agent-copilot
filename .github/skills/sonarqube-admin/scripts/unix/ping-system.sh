#!/usr/bin/env bash
# ping-system.sh - READ_ONLY: Verifies a SonarQube Server instance is
# operational. Server/Community Build ONLY -- SonarQube Cloud has no
# equivalent self-reported ping endpoint (it is a managed SaaS instance).
#
# Purpose: Liveness check (GET, no mutation).
# Supported OS: Linux, macOS (Bash).
# Dependencies: scripts/common/common.sh
# Parameters: --base-url --user
# Authentication: SonarQube user token (POC: local-secrets) -- passed for
#   parity with every other script even though the endpoint itself is public.
# Required permissions: None (public liveness endpoint).
# Approval requirements: NONE - READ_ONLY operations execute immediately.
# Deployment: Server/Community Build ONLY. Do not call this against SonarQube Cloud.
# API/MCP dependency: REST fallback (GET api/system/ping).
# Exit codes: 0 success, 1 general failure.
# Output: {"ping":"pong"} JSON object on stdout (the raw endpoint
#   response is the plain-text string "pong"; wrapped here for output
#   consistency with every other script in this framework).
# Verification: N/A (this script IS a read, not something to verify).
# Audit: writes one READ audit record.
# Security: TLS enforced; token never logged or printed.
#
# Example:
#   ./ping-system.sh --base-url https://sonarqube.example.internal --user jdoe

set -euo pipefail
SCRIPT_VERSION="1.0.0"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../../../../scripts/common/common.sh"

BASE_URL="" USER_NAME=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --base-url) BASE_URL="$2"; shift 2 ;;
    --user) USER_NAME="$2"; shift 2 ;;
    *) echo "Unknown argument: $1" >&2; exit "$EXIT_INVALID_PARAMETERS" ;;
  esac
done
[[ -z "$BASE_URL" || -z "$USER_NAME" ]] && { echo "Missing required arguments" >&2; exit "$EXIT_INVALID_PARAMETERS"; }

OPERATION_ID="$(new_operation_id)"
TARGET="server-ping"
URI="$BASE_URL/api/system/ping"
TOKEN="$(read_local_secret sonarqube)"

if RESULT="$(invoke_secure_rest GET "$URI" "$TOKEN")"; then
  write_audit_log "$OPERATION_ID" "$USER_NAME" "sonarqube" "runtime-detected" "system" "PING" "$TARGET" \
    "rest-api" "sonarqube-admin" "ping-system.sh" "$SCRIPT_VERSION" \
    "READ_ONLY" false "NOT_REQUIRED" "SUCCESS" "NOT_APPLICABLE" "null"
  jq -nc --arg ping "$RESULT" '{ping:$ping}'
  exit "$EXIT_SUCCESS"
else
  write_audit_log "$OPERATION_ID" "$USER_NAME" "sonarqube" "runtime-detected" "system" "PING" "$TARGET" \
    "rest-api" "sonarqube-admin" "ping-system.sh" "$SCRIPT_VERSION" \
    "READ_ONLY" false "NOT_REQUIRED" "FAILURE" "NOT_APPLICABLE" "request failed"
  echo "ERROR: failed to ping SonarQube server" >&2
  exit "$EXIT_GENERAL_FAILURE"
fi
