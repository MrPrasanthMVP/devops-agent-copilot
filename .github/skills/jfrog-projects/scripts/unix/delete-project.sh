#!/usr/bin/env bash
# delete-project.sh - DESTRUCTIVE: Deletes a JFrog Platform Project.
# Requires "APPROVE DELETE". No project-delete tool found in the
# verified MCP catalog -- REST fallback.
#
# Purpose: Execute the DELETE stage for a JFrog Project.
# Supported OS: Linux, macOS (Bash).
# Dependencies: scripts/common/common.sh
# Parameters: --base-url --project-key --user --operation-id [--dry-run]
# Authentication: JFrog access token (POC: local-secrets).
# Approval requirements: MANDATORY "APPROVE DELETE".
# API/MCP dependency: REST fallback (DELETE /access/api/v1/projects/{projectKey}).
# Exit codes: 0 success, 6 approval denied, 7 verification failure, 1 general failure.
# Output: JSON result.
# Verification: GET after delete; expect 404/NOT_FOUND.
# Audit: writes one DESTRUCTIVE audit record.
# Security: TLS enforced; approval re-checked immediately before DELETE.
#
# Example:
#   ./delete-project.sh --base-url https://jfrog.example.com --project-key payments \
#     --user admin-jdoe --operation-id op-123

set -euo pipefail
SCRIPT_VERSION="1.0.0"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../../../../scripts/common/common.sh"

BASE_URL="" PROJECT_KEY="" USER_NAME="" OPERATION_ID="" DRY_RUN=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --base-url) BASE_URL="$2"; shift 2 ;;
    --project-key) PROJECT_KEY="$2"; shift 2 ;;
    --user) USER_NAME="$2"; shift 2 ;;
    --operation-id) OPERATION_ID="$2"; shift 2 ;;
    --dry-run) DRY_RUN=true; shift ;;
    *) echo "Unknown argument: $1" >&2; exit "$EXIT_INVALID_PARAMETERS" ;;
  esac
done
[[ -z "$BASE_URL" || -z "$PROJECT_KEY" || -z "$USER_NAME" || -z "$OPERATION_ID" ]] && { echo "Missing required arguments" >&2; exit "$EXIT_INVALID_PARAMETERS"; }
if ! [[ "$PROJECT_KEY" =~ ^[a-z0-9]+$ ]]; then echo "ERROR: --project-key contains invalid characters." >&2; exit "$EXIT_INVALID_PARAMETERS"; fi

OPERATION_KEY="jfrog.projects.delete"
set +e
APPROVAL_OUTPUT="$(test_approval_token "$OPERATION_ID" "jfrog" "$PROJECT_KEY" "$OPERATION_KEY" "APPROVE DELETE")"
APPROVAL_STATUS=$?
set -e

if [[ $APPROVAL_STATUS -ne 0 ]]; then
  write_audit_log "$OPERATION_ID" "$USER_NAME" "jfrog" "runtime-detected" "project" "DELETE" "$PROJECT_KEY" \
    "rest-api" "jfrog-projects" "delete-project.sh" "$SCRIPT_VERSION" \
    "DESTRUCTIVE" true "DENIED" "DENIED" "NOT_APPLICABLE" "$APPROVAL_OUTPUT"
  echo "$APPROVAL_OUTPUT" >&2
  exit "$EXIT_APPROVAL_DENIED"
fi

if [[ "$DRY_RUN" == true ]]; then
  echo "(dry-run) Would DELETE JFrog project '$PROJECT_KEY'. No change made."
  exit "$EXIT_SUCCESS"
fi

TOKEN="$(read_local_secret jfrog)"
URI="$BASE_URL/access/api/v1/projects/$PROJECT_KEY"

if invoke_secure_rest DELETE "$URI" "$TOKEN" >/dev/null; then
  set_approval_consumed "$OPERATION_ID"
  VERIFICATION="UNKNOWN"; RESULT="UNKNOWN"
  if invoke_secure_rest GET "$URI" "$TOKEN" >/dev/null 2>&1; then
    VERIFICATION="FAILED"
  else
    VERIFICATION="CONFIRMED"; RESULT="SUCCESS"
  fi

  write_audit_log "$OPERATION_ID" "$USER_NAME" "jfrog" "runtime-detected" "project" "DELETE" "$PROJECT_KEY" \
    "rest-api" "jfrog-projects" "delete-project.sh" "$SCRIPT_VERSION" \
    "DESTRUCTIVE" true "APPROVED" "$RESULT" "$VERIFICATION" "null"

  jq -nc --arg o "$OPERATION_ID" --arg t "$PROJECT_KEY" --arg r "$RESULT" --arg v "$VERIFICATION" \
    '{operationId:$o,target:$t,result:$r,verification:$v}'

  [[ "$VERIFICATION" != "CONFIRMED" ]] && exit "$EXIT_VERIFICATION_FAILURE"
  exit "$EXIT_SUCCESS"
else
  write_audit_log "$OPERATION_ID" "$USER_NAME" "jfrog" "runtime-detected" "project" "DELETE" "$PROJECT_KEY" \
    "rest-api" "jfrog-projects" "delete-project.sh" "$SCRIPT_VERSION" \
    "DESTRUCTIVE" true "APPROVED" "FAILURE" "UNKNOWN" "request failed"
  echo "ERROR: failed to delete project '$PROJECT_KEY'" >&2
  exit "$EXIT_GENERAL_FAILURE"
fi
