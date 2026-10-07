#!/usr/bin/env bash
# add-permission-grant.sh - SECURITY_SENSITIVE: Adds a permission grant to
# a Jira Cloud permission scheme. Requires "APPROVE PERMISSION CHANGE".
# Supported OS: Linux, macOS. Dependencies: scripts/common/common.sh
# Parameters: --site-url --scheme-id --permission-key --holder-type
#   --holder-parameter --email --api-token --user --operation-id [--dry-run]
# Authentication: Jira Cloud basic auth. Required permissions: "Administer Jira".
# Approval requirements: MANDATORY "APPROVE PERMISSION CHANGE".
# API/MCP dependency: REST fallback (POST .../permissionscheme/{id}/permission).
# Exit codes: 0 success, 6 approval denied, 7 verification failure, 1 general failure.
# Output: JSON result. Verification: GET scheme; confirm grant present.
# Audit: one SECURITY_SENSITIVE record. Security: TLS enforced, approval re-checked.
#
# Example: ./add-permission-grant.sh --site-url https://example.atlassian.net \
#   --scheme-id 10000 --permission-key ADMINISTER_PROJECTS --holder-type group \
#   --holder-parameter platform-eng --email jdoe@example.com \
#   --api-token "$JIRA_API_TOKEN" --user jdoe --operation-id op-123

set -euo pipefail
SCRIPT_VERSION="1.0.0"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../../../../scripts/common/common.sh"

SITE_URL="" SCHEME_ID="" PERMISSION_KEY="" HOLDER_TYPE="" HOLDER_PARAM="" EMAIL="" API_TOKEN="" USER_NAME="" OPERATION_ID="" DRY_RUN=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --site-url) SITE_URL="$2"; shift 2 ;;
    --scheme-id) SCHEME_ID="$2"; shift 2 ;;
    --permission-key) PERMISSION_KEY="$2"; shift 2 ;;
    --holder-type) HOLDER_TYPE="$2"; shift 2 ;;
    --holder-parameter) HOLDER_PARAM="$2"; shift 2 ;;
    --email) EMAIL="$2"; shift 2 ;;
    --api-token) API_TOKEN="$2"; shift 2 ;;
    --user) USER_NAME="$2"; shift 2 ;;
    --operation-id) OPERATION_ID="$2"; shift 2 ;;
    --dry-run) DRY_RUN=true; shift ;;
    *) echo "Unknown argument: $1" >&2; exit "$EXIT_INVALID_PARAMETERS" ;;
  esac
done
[[ -z "$SITE_URL" || -z "$SCHEME_ID" || -z "$PERMISSION_KEY" || -z "$HOLDER_TYPE" || -z "$HOLDER_PARAM" || -z "$EMAIL" || -z "$API_TOKEN" || -z "$USER_NAME" || -z "$OPERATION_ID" ]] && { echo "Missing required arguments" >&2; exit "$EXIT_INVALID_PARAMETERS"; }

OPERATION_KEY="jira.permissions.update"
set +e
APPROVAL_OUTPUT="$(test_approval_token "$OPERATION_ID" "jira" "$SCHEME_ID" "$OPERATION_KEY" "APPROVE PERMISSION CHANGE")"
APPROVAL_STATUS=$?
set -e

if [[ $APPROVAL_STATUS -ne 0 ]]; then
  write_audit_log "$OPERATION_ID" "$USER_NAME" "jira" "cloud" "permission_scheme" "UPDATE" "$SCHEME_ID" \
    "rest-api" "jira-permissions" "add-permission-grant.sh" "$SCRIPT_VERSION" \
    "SECURITY_SENSITIVE" true "DENIED" "DENIED" "NOT_APPLICABLE" "$APPROVAL_OUTPUT"
  echo "$APPROVAL_OUTPUT" >&2
  exit "$EXIT_APPROVAL_DENIED"
fi

if [[ "$DRY_RUN" == true ]]; then
  echo "(dry-run) Would ADD grant '$PERMISSION_KEY' to $HOLDER_TYPE '$HOLDER_PARAM' on scheme '$SCHEME_ID'. No change made."
  exit "$EXIT_SUCCESS"
fi

URI="$SITE_URL/rest/api/3/permissionscheme/$SCHEME_ID/permission"
GET_URI="$SITE_URL/rest/api/3/permissionscheme/$SCHEME_ID"
BASIC="$(printf '%s:%s' "$EMAIL" "$API_TOKEN" | base64 | tr -d '\n')"
BODY="$(jq -nc --arg p "$PERMISSION_KEY" --arg t "$HOLDER_TYPE" --arg param "$HOLDER_PARAM" \
  '{permission:$p, holder:{type:$t, parameter:$param}}')"

if invoke_secure_rest POST "$URI" "$BASIC" "Basic" "$BODY" >/dev/null; then
  set_approval_consumed "$OPERATION_ID"
  VERIFICATION="FAILED"; RESULT="UNKNOWN"
  if CURRENT="$(invoke_secure_rest GET "$GET_URI" "$BASIC" "Basic")"; then
    MATCH="$(echo "$CURRENT" | jq --arg p "$PERMISSION_KEY" --arg t "$HOLDER_TYPE" --arg param "$HOLDER_PARAM" \
      '[.permissions[] | select(.permission==$p and .holder.type==$t and .holder.parameter==$param)] | length')"
    [[ "$MATCH" -gt 0 ]] && { VERIFICATION="CONFIRMED"; RESULT="SUCCESS"; }
  fi

  write_audit_log "$OPERATION_ID" "$USER_NAME" "jira" "cloud" "permission_scheme" "UPDATE" "$SCHEME_ID" \
    "rest-api" "jira-permissions" "add-permission-grant.sh" "$SCRIPT_VERSION" \
    "SECURITY_SENSITIVE" true "APPROVED" "$RESULT" "$VERIFICATION" "null"

  jq -nc --arg o "$OPERATION_ID" --arg t "$SCHEME_ID" --arg r "$RESULT" --arg v "$VERIFICATION" \
    '{operationId:$o,target:$t,result:$r,verification:$v}'
  [[ "$VERIFICATION" != "CONFIRMED" ]] && exit "$EXIT_VERIFICATION_FAILURE"
  exit "$EXIT_SUCCESS"
else
  write_audit_log "$OPERATION_ID" "$USER_NAME" "jira" "cloud" "permission_scheme" "UPDATE" "$SCHEME_ID" \
    "rest-api" "jira-permissions" "add-permission-grant.sh" "$SCRIPT_VERSION" \
    "SECURITY_SENSITIVE" true "APPROVED" "FAILURE" "UNKNOWN" "request failed"
  echo "ERROR: failed to add permission grant on scheme '$SCHEME_ID'" >&2
  exit "$EXIT_GENERAL_FAILURE"
fi
