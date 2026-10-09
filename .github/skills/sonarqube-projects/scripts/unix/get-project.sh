#!/usr/bin/env bash
# get-project.sh - READ_ONLY: Retrieves a single SonarQube project by key.
#
# Purpose: Fetch one project's details (GET via api/projects/search with
#   projects=<key> -- SonarQube has no single-object project GET endpoint).
# Supported OS: Linux, macOS (Bash).
# Dependencies: scripts/common/common.sh (curl, jq)
# Parameters: --base-url --project-key [--organization] --user
# Authentication: SonarQube user token (POC: local-secrets).
# Required permissions: Browse permission on the project.
# Approval requirements: NONE.
# Deployment: works against BOTH Server and Cloud (pass --organization for Cloud).
# API/MCP dependency: REST fallback; prefer the SonarQube MCP server's
#   project-read tool when available.
# Exit codes: 0 success, 8 not found, 1 general failure.
# Output: project JSON on stdout.
# Verification: N/A.
# Audit: writes one READ audit record.
# Security: TLS enforced; token never logged/printed.
#
# Example:
#   ./get-project.sh --base-url https://sonarqube.example.internal --project-key my-app --user jdoe

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
[[ -z "$BASE_URL" || -z "$PROJECT_KEY" || -z "$USER_NAME" ]] && { echo "Missing required arguments" >&2; exit "$EXIT_INVALID_PARAMETERS"; }

OPERATION_ID="$(new_operation_id)"
TARGET="$PROJECT_KEY"
URI="$BASE_URL/api/projects/search?projects=$PROJECT_KEY"
[[ -n "$ORGANIZATION" ]] && URI="$URI&organization=$ORGANIZATION"
TOKEN="$(read_local_secret sonarqube)"

if RESPONSE="$(invoke_secure_rest GET "$URI" "$TOKEN")"; then
  COUNT="$(echo "$RESPONSE" | jq '.components | length')"
  if [[ "$COUNT" -eq 0 ]]; then
    write_audit_log "$OPERATION_ID" "$USER_NAME" "sonarqube" "runtime-detected" "project" "GET" "$TARGET" \
      "rest-api" "sonarqube-projects" "get-project.sh" "$SCRIPT_VERSION" \
      "READ_ONLY" false "NOT_REQUIRED" "FAILURE" "NOT_APPLICABLE" "project not found"
    echo "ERROR: project '$TARGET' not found" >&2
    exit "$EXIT_TARGET_NOT_FOUND"
  fi
  write_audit_log "$OPERATION_ID" "$USER_NAME" "sonarqube" "runtime-detected" "project" "GET" "$TARGET" \
    "rest-api" "sonarqube-projects" "get-project.sh" "$SCRIPT_VERSION" \
    "READ_ONLY" false "NOT_REQUIRED" "SUCCESS" "NOT_APPLICABLE" "null"
  echo "$RESPONSE" | jq '.components[0]'
  exit "$EXIT_SUCCESS"
else
  write_audit_log "$OPERATION_ID" "$USER_NAME" "sonarqube" "runtime-detected" "project" "GET" "$TARGET" \
    "rest-api" "sonarqube-projects" "get-project.sh" "$SCRIPT_VERSION" \
    "READ_ONLY" false "NOT_REQUIRED" "FAILURE" "NOT_APPLICABLE" "request failed"
  echo "ERROR: failed to retrieve project '$TARGET'" >&2
  exit "$EXIT_GENERAL_FAILURE"
fi
