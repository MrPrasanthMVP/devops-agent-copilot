#!/usr/bin/env bash
# set-role-assignment.sh - SECURITY_SENSITIVE: Assigns a role to a
# principal on a Confluence Cloud space. Requires "APPROVE PERMISSION CHANGE".
# Supported OS: Linux, macOS. Dependencies: scripts/common/common.sh
# Parameters: --site-url --space-id --principal-id --principal-type
#   --role-id --email --api-token --user --operation-id [--dry-run]
# Authentication: Confluence Cloud basic auth. Required permissions: space "admin" role.
# Approval requirements: MANDATORY "APPROVE PERMISSION CHANGE".
# API/MCP dependency: REST fallback (POST /wiki/api/v2/spaces/{id}/role-assignments).
# Exit codes: 0 success, 6 approval denied, 7 verification failure, 1 general failure.
# Output: JSON result. Verification: GET role assignments; confirm principal+role present.
# Audit: one SECURITY_SENSITIVE record. Security: TLS enforced, approval re-checked.
#
# Example: ./set-role-assignment.sh --site-url https://example.atlassian.net \
#   --space-id 123456 --principal-id group-abc --principal-type GROUP \
#   --role-id viewer-role-id --email jdoe@example.com \
#   --api-token "$CONFLUENCE_API_TOKEN" --user jdoe --operation-id op-123

set -euo pipefail
SCRIPT_VERSION="1.0.0"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../../../../scripts/common/common.sh"

SITE_URL="" SPACE_ID="" PRINCIPAL_ID="" PRINCIPAL_TYPE="" ROLE_ID="" EMAIL="" API_TOKEN="" USER_NAME="" OPERATION_ID="" DRY_RUN=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --site-url) SITE_URL="$2"; shift 2 ;;
    --space-id) SPACE_ID="$2"; shift 2 ;;
    --principal-id) PRINCIPAL_ID="$2"; shift 2 ;;
    --principal-type) PRINCIPAL_TYPE="$2"; shift 2 ;;
    --role-id) ROLE_ID="$2"; shift 2 ;;
    --email) EMAIL="$2"; shift 2 ;;
    --api-token) API_TOKEN="$2"; shift 2 ;;
    --user) USER_NAME="$2"; shift 2 ;;
    --operation-id) OPERATION_ID="$2"; shift 2 ;;
    --dry-run) DRY_RUN=true; shift ;;
    *) echo "Unknown argument: $1" >&2; exit "$EXIT_INVALID_PARAMETERS" ;;
  esac
done
[[ -z "$SITE_URL" || -z "$SPACE_ID" || -z "$PRINCIPAL_ID" || -z "$PRINCIPAL_TYPE" || -z "$ROLE_ID" || -z "$EMAIL" || -z "$API_TOKEN" || -z "$USER_NAME" || -z "$OPERATION_ID" ]] && { echo "Missing required arguments" >&2; exit "$EXIT_INVALID_PARAMETERS"; }

OPERATION_KEY="confluence.permissions.update"
set +e
APPROVAL_OUTPUT="$(test_approval_token "$OPERATION_ID" "confluence" "$SPACE_ID" "$OPERATION_KEY" "APPROVE PERMISSION CHANGE")"
APPROVAL_STATUS=$?
set -e

if [[ $APPROVAL_STATUS -ne 0 ]]; then
  write_audit_log "$OPERATION_ID" "$USER_NAME" "confluence" "cloud" "space_role" "UPDATE" "$SPACE_ID" \
    "rest-api" "confluence-permissions" "set-role-assignment.sh" "$SCRIPT_VERSION" \
    "SECURITY_SENSITIVE" true "DENIED" "DENIED" "NOT_APPLICABLE" "$APPROVAL_OUTPUT"
  echo "$APPROVAL_OUTPUT" >&2
  exit "$EXIT_APPROVAL_DENIED"
fi

if [[ "$DRY_RUN" == true ]]; then
  echo "(dry-run) Would ASSIGN role '$ROLE_ID' to $PRINCIPAL_TYPE '$PRINCIPAL_ID' on space '$SPACE_ID'. No change made."
  exit "$EXIT_SUCCESS"
fi

URI="$SITE_URL/wiki/api/v2/spaces/$SPACE_ID/role-assignments"
BASIC="$(printf '%s:%s' "$EMAIL" "$API_TOKEN" | base64 | tr -d '\n')"
BODY="$(jq -nc --arg id "$PRINCIPAL_ID" --arg type "$PRINCIPAL_TYPE" --arg role "$ROLE_ID" \
  '{principals: [{id:$id, type:$type, roleId:$role}]}')"

if invoke_secure_rest POST "$URI" "$BASIC" "Basic" "$BODY" >/dev/null; then
  set_approval_consumed "$OPERATION_ID"
  VERIFICATION="FAILED"; RESULT="UNKNOWN"
  if CURRENT="$(invoke_secure_rest GET "$URI" "$BASIC" "Basic")"; then
    MATCH="$(echo "$CURRENT" | jq --arg id "$PRINCIPAL_ID" --arg role "$ROLE_ID" \
      '[.results[] | select(.principalId==$id and .roleId==$role)] | length')"
    [[ "$MATCH" -gt 0 ]] && { VERIFICATION="CONFIRMED"; RESULT="SUCCESS"; }
  fi

  write_audit_log "$OPERATION_ID" "$USER_NAME" "confluence" "cloud" "space_role" "UPDATE" "$SPACE_ID" \
    "rest-api" "confluence-permissions" "set-role-assignment.sh" "$SCRIPT_VERSION" \
    "SECURITY_SENSITIVE" true "APPROVED" "$RESULT" "$VERIFICATION" "null"

  jq -nc --arg o "$OPERATION_ID" --arg t "$SPACE_ID" --arg r "$RESULT" --arg v "$VERIFICATION" \
    '{operationId:$o,target:$t,result:$r,verification:$v}'
  [[ "$VERIFICATION" != "CONFIRMED" ]] && exit "$EXIT_VERIFICATION_FAILURE"
  exit "$EXIT_SUCCESS"
else
  write_audit_log "$OPERATION_ID" "$USER_NAME" "confluence" "cloud" "space_role" "UPDATE" "$SPACE_ID" \
    "rest-api" "confluence-permissions" "set-role-assignment.sh" "$SCRIPT_VERSION" \
    "SECURITY_SENSITIVE" true "APPROVED" "FAILURE" "UNKNOWN" "request failed"
  echo "ERROR: failed to assign role on space '$SPACE_ID'" >&2
  exit "$EXIT_GENERAL_FAILURE"
fi
