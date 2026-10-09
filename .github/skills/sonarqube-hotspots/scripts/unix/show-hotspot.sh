#!/usr/bin/env bash
# show-hotspot.sh - READ_ONLY: Retrieves detailed information for one
# SonarQube security hotspot.
#
# Purpose: Fetch a single hotspot's details (GET, no mutation).
# Supported OS: Linux, macOS (Bash).
# Dependencies: scripts/common/common.sh
# Parameters: --base-url --hotspot-key [--organization] --user
# Authentication: SonarQube user token (POC: local-secrets).
# Required permissions: Browse permission on the hotspot's project.
# Approval requirements: NONE - READ_ONLY operations execute immediately.
# Deployment: works against BOTH Server and Cloud (pass --organization for Cloud).
# API/MCP dependency: REST fallback (GET api/hotspots/show).
# Exit codes: 0 success, 3 auth failure, 8 not found, 1 general failure.
# Output: hotspot JSON object on stdout.
# Verification: N/A (this script IS a read, not something to verify).
# Audit: writes one READ audit record.
# Security: TLS enforced; token never logged or printed.
#
# Example:
#   ./show-hotspot.sh --base-url https://sonarqube.example.internal --hotspot-key AbCd1234 --user jdoe

set -euo pipefail
SCRIPT_VERSION="1.0.0"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../../../../scripts/common/common.sh"

BASE_URL="" HOTSPOT_KEY="" ORGANIZATION="" USER_NAME=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --base-url) BASE_URL="$2"; shift 2 ;;
    --hotspot-key) HOTSPOT_KEY="$2"; shift 2 ;;
    --organization) ORGANIZATION="$2"; shift 2 ;;
    --user) USER_NAME="$2"; shift 2 ;;
    *) echo "Unknown argument: $1" >&2; exit "$EXIT_INVALID_PARAMETERS" ;;
  esac
done
[[ -z "$BASE_URL" || -z "$HOTSPOT_KEY" || -z "$USER_NAME" ]] && { echo "Missing required arguments" >&2; exit "$EXIT_INVALID_PARAMETERS"; }

OPERATION_ID="$(new_operation_id)"
TARGET="$HOTSPOT_KEY"
URI="$BASE_URL/api/hotspots/show?hotspot=$HOTSPOT_KEY"
[[ -n "$ORGANIZATION" ]] && URI="$URI&organization=$ORGANIZATION"

TOKEN="$(read_local_secret sonarqube)"

if RESULT="$(invoke_secure_rest GET "$URI" "$TOKEN")"; then
  write_audit_log "$OPERATION_ID" "$USER_NAME" "sonarqube" "runtime-detected" "hotspot" "GET" "$TARGET" \
    "rest-api" "sonarqube-hotspots" "show-hotspot.sh" "$SCRIPT_VERSION" \
    "READ_ONLY" false "NOT_REQUIRED" "SUCCESS" "NOT_APPLICABLE" "null"
  echo "$RESULT"
  exit "$EXIT_SUCCESS"
else
  write_audit_log "$OPERATION_ID" "$USER_NAME" "sonarqube" "runtime-detected" "hotspot" "GET" "$TARGET" \
    "rest-api" "sonarqube-hotspots" "show-hotspot.sh" "$SCRIPT_VERSION" \
    "READ_ONLY" false "NOT_REQUIRED" "FAILURE" "NOT_APPLICABLE" "request failed"
  echo "ERROR: failed to retrieve hotspot '$TARGET'" >&2
  exit "$EXIT_GENERAL_FAILURE"
fi
