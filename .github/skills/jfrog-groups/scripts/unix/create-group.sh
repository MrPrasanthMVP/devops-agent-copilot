#!/usr/bin/env bash
# create-group.sh - ADMINISTRATIVE: Creates or replaces a JFrog group.
# Requires "APPROVE ADMIN CHANGE". No MCP tool covers this -- REST fallback.
#
# Purpose: Execute the CREATE/UPDATE stage for a group.
# Supported OS: Linux, macOS (Bash).
# Dependencies: scripts/common/common.sh
# Parameters: --base-url --group-name --description --user --operation-id [--dry-run]
# Authentication: JFrog access token (POC: local-secrets).
# Approval requirements: MANDATORY "APPROVE ADMIN CHANGE".
# API/MCP dependency: REST fallback (PUT /access/api/v2/groups/{group_name}).
# Exit codes: 0 success, 6 approval denied, 7 verification failure, 1 general failure.
# Output: JSON result.
# Verification: GET after PUT; confirm group_name present.
# Audit: writes one ADMINISTRATIVE audit record.
# Security: TLS enforced; approval re-checked immediately before PUT.
#
# Example:
#   ./create-group.sh --base-url https://jfrog.example.com --group-name build-team \
#     --description "CI build service accounts" --user admin-jdoe --operation-id op-123

set -euo pipefail
SCRIPT_VERSION="1.0.0"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../../../../scripts/common/common.sh"

BASE_URL="" GROUP_NAME="" DESCRIPTION="" USER_NAME="" OPERATION_ID="" DRY_RUN=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --base-url) BASE_URL="$2"; shift 2 ;;
    --group-name) GROUP_NAME="$2"; shift 2 ;;
    --description) DESCRIPTION="$2"; shift 2 ;;
    --user) USER_NAME="$2"; shift 2 ;;
    --operation-id) OPERATION_ID="$2"; shift 2 ;;
    --dry-run) DRY_RUN=true; shift ;;
    *) echo "Unknown argument: $1" >&2; exit "$EXIT_INVALID_PARAMETERS" ;;
  esac
done
[[ -z "$BASE_URL" || -z "$GROUP_NAME" || -z "$USER_NAME" || -z "$OPERATION_ID" ]] && { echo "Missing required arguments" >&2; exit "$EXIT_INVALID_PARAMETERS"; }

OPERATION_KEY="jfrog.groups.create"
set +e
APPROVAL_OUTPUT="$(test_approval_token "$OPERATION_ID" "jfrog" "$GROUP_NAME" "$OPERATION_KEY" "APPROVE ADMIN CHANGE")"
APPROVAL_STATUS=$?
set -e

if [[ $APPROVAL_STATUS -ne 0 ]]; then
  write_audit_log "$OPERATION_ID" "$USER_NAME" "jfrog" "runtime-detected" "group" "CREATE" "$GROUP_NAME" \
    "rest-api" "jfrog-groups" "create-group.sh" "$SCRIPT_VERSION" \
    "ADMINISTRATIVE" true "DENIED" "DENIED" "NOT_APPLICABLE" "$APPROVAL_OUTPUT"
  echo "$APPROVAL_OUTPUT" >&2
  exit "$EXIT_APPROVAL_DENIED"
fi

if [[ "$DRY_RUN" == true ]]; then
  echo "(dry-run) Would CREATE/UPDATE JFrog group '$GROUP_NAME'. No change made."
  exit "$EXIT_SUCCESS"
fi

TOKEN="$(read_local_secret jfrog)"
URI="$BASE_URL/access/api/v2/groups/$GROUP_NAME"
BODY="$(jq -nc --arg name "$GROUP_NAME" --arg desc "$DESCRIPTION" '{group_name:$name, description:$desc}')"

if invoke_secure_rest PUT "$URI" "$TOKEN" "Bearer" "$BODY" >/dev/null; then
  set_approval_consumed "$OPERATION_ID"
  VERIFICATION="FAILED"; RESULT="UNKNOWN"
  if CURRENT="$(invoke_secure_rest GET "$URI" "$TOKEN")"; then
    if echo "$CURRENT" | jq -e --arg n "$GROUP_NAME" '.group_name == $n' >/dev/null; then
      VERIFICATION="CONFIRMED"; RESULT="SUCCESS"
    fi
  fi

  write_audit_log "$OPERATION_ID" "$USER_NAME" "jfrog" "runtime-detected" "group" "CREATE" "$GROUP_NAME" \
    "rest-api" "jfrog-groups" "create-group.sh" "$SCRIPT_VERSION" \
    "ADMINISTRATIVE" true "APPROVED" "$RESULT" "$VERIFICATION" "null"

  jq -nc --arg o "$OPERATION_ID" --arg t "$GROUP_NAME" --arg r "$RESULT" --arg v "$VERIFICATION" \
    '{operationId:$o,target:$t,result:$r,verification:$v}'

  [[ "$VERIFICATION" != "CONFIRMED" ]] && exit "$EXIT_VERIFICATION_FAILURE"
  exit "$EXIT_SUCCESS"
else
  write_audit_log "$OPERATION_ID" "$USER_NAME" "jfrog" "runtime-detected" "group" "CREATE" "$GROUP_NAME" \
    "rest-api" "jfrog-groups" "create-group.sh" "$SCRIPT_VERSION" \
    "ADMINISTRATIVE" true "APPROVED" "FAILURE" "UNKNOWN" "request failed"
  echo "ERROR: failed to create/update group '$GROUP_NAME'" >&2
  exit "$EXIT_GENERAL_FAILURE"
fi
