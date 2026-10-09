#!/usr/bin/env bash
# list-projects.sh - READ_ONLY: Lists/searches SonarQube projects.
#
# Purpose: Fetch the project list (GET, no mutation).
# Supported OS: Linux, macOS (Bash).
# Dependencies: scripts/common/common.sh (curl, jq)
# Parameters: --base-url [--organization] [--query] --user
# Authentication: SonarQube user token (POC: local-secrets).
# Required permissions: Browse permission on the projects returned.
# Approval requirements: NONE.
# Deployment: works against BOTH SonarQube Server/Community Build
#   (self-managed --base-url) and SonarQube Cloud (--base-url
#   https://sonarcloud.io or https://sonarqube.us, plus --organization).
# API/MCP dependency: REST fallback; prefer the SonarQube MCP server's
#   project-search tool when available.
# Exit codes: 0 success, 1 general failure.
# Output: projects JSON on stdout.
# Verification: N/A.
# Audit: writes one READ audit record.
# Security: TLS enforced; token never logged/printed.
#
# Example:
#   ./list-projects.sh --base-url https://sonarqube.example.internal --user jdoe
#   ./list-projects.sh --base-url https://sonarcloud.io --organization my-org --user jdoe

set -euo pipefail
SCRIPT_VERSION="1.0.0"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../../../../scripts/common/common.sh"

BASE_URL="" ORGANIZATION="" QUERY="" USER_NAME=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --base-url) BASE_URL="$2"; shift 2 ;;
    --organization) ORGANIZATION="$2"; shift 2 ;;
    --query) QUERY="$2"; shift 2 ;;
    --user) USER_NAME="$2"; shift 2 ;;
    *) echo "Unknown argument: $1" >&2; exit "$EXIT_INVALID_PARAMETERS" ;;
  esac
done
[[ -z "$BASE_URL" || -z "$USER_NAME" ]] && { echo "Missing required arguments" >&2; exit "$EXIT_INVALID_PARAMETERS"; }

OPERATION_ID="$(new_operation_id)"
TARGET="all-projects"
[[ -n "$QUERY" ]] && TARGET="search:$QUERY"
URI="$BASE_URL/api/projects/search?ps=500"
[[ -n "$QUERY" ]] && URI="$URI&q=$QUERY"
[[ -n "$ORGANIZATION" ]] && URI="$URI&organization=$ORGANIZATION"
TOKEN="$(read_local_secret sonarqube)"

if RESPONSE="$(invoke_secure_rest GET "$URI" "$TOKEN")"; then
  write_audit_log "$OPERATION_ID" "$USER_NAME" "sonarqube" "runtime-detected" "project" "LIST" "$TARGET" \
    "rest-api" "sonarqube-projects" "list-projects.sh" "$SCRIPT_VERSION" \
    "READ_ONLY" false "NOT_REQUIRED" "SUCCESS" "NOT_APPLICABLE" "null"
  echo "$RESPONSE"
  exit "$EXIT_SUCCESS"
else
  write_audit_log "$OPERATION_ID" "$USER_NAME" "sonarqube" "runtime-detected" "project" "LIST" "$TARGET" \
    "rest-api" "sonarqube-projects" "list-projects.sh" "$SCRIPT_VERSION" \
    "READ_ONLY" false "NOT_REQUIRED" "FAILURE" "NOT_APPLICABLE" "request failed"
  echo "ERROR: failed to list SonarQube projects" >&2
  exit "$EXIT_GENERAL_FAILURE"
fi
