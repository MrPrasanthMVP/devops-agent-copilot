#!/usr/bin/env bash
# set-permission-target.sh - SECURITY_SENSITIVE: Creates or replaces a
# permission target. Requires "APPROVE PERMISSION CHANGE".
#
# Purpose: Execute the create/replace stage for a permission target.
# Supported OS: Linux, macOS (Bash).
# Dependencies: scripts/common/common.sh
# Parameters: --base-url --permission-target-name --body-json --user
#   --operation-id [--dry-run]
# Authentication: JFrog access token (POC: local-secrets).
# Required permissions: Artifactory admin permission.
# Approval requirements: MANDATORY "APPROVE PERMISSION CHANGE".
# Dry-run: --dry-run supported.
# API/MCP dependency: REST fallback (POST /artifactory/api/v2/security/permissions/{name}).
# Exit codes: 0 success, 6 approval denied, 7 verification failure, 1 general failure.
# Output: JSON result.
# Verification: GET after POST; diff returned body against submitted body.
# Audit: writes one SECURITY_SENSITIVE audit record.
# Security: TLS enforced; approval re-checked immediately before POST.
#
# Example:
#   ./set-permission-target.sh --base-url https://jfrog.example.com \
#     --permission-target-name releases-local-perm \
#     --body-json '{"name":"releases-local-perm","repo":{"repositories":["releases-local"],"actions":{"groups":{"team-platform":["read","deploy"]}}}}' \
#     --user jdoe --operation-id op-123

set -euo pipefail
SCRIPT_VERSION="1.0.0"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../../../../scripts/common/common.sh"

BASE_URL="" NAME="" BODY_JSON="" USER_NAME="" OPERATION_ID="" DRY_RUN=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --base-url) BASE_URL="$2"; shift 2 ;;
    --permission-target-name) NAME="$2"; shift 2 ;;
    --body-json) BODY_JSON="$2"; shift 2 ;;
    --user) USER_NAME="$2"; shift 2 ;;
    --operation-id) OPERATION_ID="$2"; shift 2 ;;
    --dry-run) DRY_RUN=true; shift ;;
    *) echo "Unknown argument: $1" >&2; exit "$EXIT_INVALID_PARAMETERS" ;;
  esac
done
[[ -z "$BASE_URL" || -z "$NAME" || -z "$BODY_JSON" || -z "$USER_NAME" || -z "$OPERATION_ID" ]] && { echo "Missing required arguments" >&2; exit "$EXIT_INVALID_PARAMETERS"; }

OPERATION_KEY="jfrog.permissions.update"
set +e
APPROVAL_OUTPUT="$(test_approval_token "$OPERATION_ID" "jfrog" "$NAME" "$OPERATION_KEY" "APPROVE PERMISSION CHANGE")"
APPROVAL_STATUS=$?
set -e

if [[ $APPROVAL_STATUS -ne 0 ]]; then
  write_audit_log "$OPERATION_ID" "$USER_NAME" "jfrog" "runtime-detected" "permission_target" "UPDATE" "$NAME" \
    "rest-api" "jfrog-permissions" "set-permission-target.sh" "$SCRIPT_VERSION" \
    "SECURITY_SENSITIVE" true "DENIED" "DENIED" "NOT_APPLICABLE" "$APPROVAL_OUTPUT"
  echo "$APPROVAL_OUTPUT" >&2
  exit "$EXIT_APPROVAL_DENIED"
fi

if [[ "$DRY_RUN" == true ]]; then
  echo "(dry-run) Would SET permission target '$NAME'. No change made."
  exit "$EXIT_SUCCESS"
fi

URI="$BASE_URL/artifactory/api/v2/security/permissions/$NAME"
TOKEN="$(read_local_secret jfrog)"

if invoke_secure_rest POST "$URI" "$TOKEN" "Bearer" "$BODY_JSON" >/dev/null; then
  set_approval_consumed "$OPERATION_ID"
  VERIFICATION="FAILED"; RESULT="UNKNOWN"
  if CURRENT="$(invoke_secure_rest GET "$URI" "$TOKEN")"; then
    CUR_NORM="$(echo "$CURRENT" | jq -cS .)"
    EXP_NORM="$(echo "$BODY_JSON" | jq -cS .)"
    if [[ "$CUR_NORM" == "$EXP_NORM" ]]; then VERIFICATION="CONFIRMED"; RESULT="SUCCESS"; fi
  fi

  write_audit_log "$OPERATION_ID" "$USER_NAME" "jfrog" "runtime-detected" "permission_target" "UPDATE" "$NAME" \
    "rest-api" "jfrog-permissions" "set-permission-target.sh" "$SCRIPT_VERSION" \
    "SECURITY_SENSITIVE" true "APPROVED" "$RESULT" "$VERIFICATION" "null"

  jq -nc --arg o "$OPERATION_ID" --arg t "$NAME" --arg r "$RESULT" --arg v "$VERIFICATION" \
    '{operationId:$o,target:$t,result:$r,verification:$v}'

  [[ "$VERIFICATION" != "CONFIRMED" ]] && exit "$EXIT_VERIFICATION_FAILURE"
  exit "$EXIT_SUCCESS"
else
  write_audit_log "$OPERATION_ID" "$USER_NAME" "jfrog" "runtime-detected" "permission_target" "UPDATE" "$NAME" \
    "rest-api" "jfrog-permissions" "set-permission-target.sh" "$SCRIPT_VERSION" \
    "SECURITY_SENSITIVE" true "APPROVED" "FAILURE" "UNKNOWN" "request failed"
  echo "ERROR: failed to set permission target '$NAME'" >&2
  exit "$EXIT_GENERAL_FAILURE"
fi
