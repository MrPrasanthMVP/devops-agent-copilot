#!/usr/bin/env bash
# get-page.sh - READ_ONLY: Retrieves a Confluence Cloud page.
#
# Purpose: Fetch current page content/version (GET, no mutation).
# Supported OS: Linux, macOS (Bash).
# Dependencies: scripts/common/common.sh
# Parameters: --site-url --page-id --email --api-token --user
# Authentication: Confluence Cloud basic auth (email + API token).
# Required permissions: "View" permission on the page's space.
# Approval requirements: NONE.
# Dry-run: not applicable.
# API/MCP dependency: REST fallback; prefer discovered Rovo MCP read tool.
# Exit codes: 0 success, 1 general failure.
# Output: page JSON on stdout (includes version.number needed for updates).
# Verification: N/A.
# Audit: writes one READ audit record.
# Security: TLS enforced; token never logged/printed.
#
# Example:
#   ./get-page.sh --site-url https://example.atlassian.net --page-id 123456 \
#     --email jdoe@example.com --api-token "$CONFLUENCE_API_TOKEN" --user jdoe

set -euo pipefail
SCRIPT_VERSION="1.0.0"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../../../../scripts/common/common.sh"

SITE_URL="" PAGE_ID="" EMAIL="" API_TOKEN="" USER_NAME=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --site-url) SITE_URL="$2"; shift 2 ;;
    --page-id) PAGE_ID="$2"; shift 2 ;;
    --email) EMAIL="$2"; shift 2 ;;
    --api-token) API_TOKEN="$2"; shift 2 ;;
    --user) USER_NAME="$2"; shift 2 ;;
    *) echo "Unknown argument: $1" >&2; exit "$EXIT_INVALID_PARAMETERS" ;;
  esac
done
[[ -z "$SITE_URL" || -z "$PAGE_ID" || -z "$EMAIL" || -z "$API_TOKEN" || -z "$USER_NAME" ]] && { echo "Missing required arguments" >&2; exit "$EXIT_INVALID_PARAMETERS"; }

OPERATION_ID="$(new_operation_id)"
URI="$SITE_URL/wiki/api/v2/pages/$PAGE_ID?body-format=storage"
BASIC="$(printf '%s:%s' "$EMAIL" "$API_TOKEN" | base64 | tr -d '\n')"

if RESPONSE="$(invoke_secure_rest GET "$URI" "$BASIC" "Basic")"; then
  write_audit_log "$OPERATION_ID" "$USER_NAME" "confluence" "cloud" "page" "GET" "$PAGE_ID" \
    "rest-api" "confluence-pages" "get-page.sh" "$SCRIPT_VERSION" \
    "READ_ONLY" false "NOT_REQUIRED" "SUCCESS" "NOT_APPLICABLE" "null"
  echo "$RESPONSE"
  exit "$EXIT_SUCCESS"
else
  write_audit_log "$OPERATION_ID" "$USER_NAME" "confluence" "cloud" "page" "GET" "$PAGE_ID" \
    "rest-api" "confluence-pages" "get-page.sh" "$SCRIPT_VERSION" \
    "READ_ONLY" false "NOT_REQUIRED" "FAILURE" "NOT_APPLICABLE" "request failed"
  echo "ERROR: failed to retrieve page '$PAGE_ID'" >&2
  exit "$EXIT_GENERAL_FAILURE"
fi
