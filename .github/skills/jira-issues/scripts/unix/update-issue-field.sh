#!/usr/bin/env bash
# update-issue-field.sh - WRITE: Updates a single Jira Cloud issue field.
# Requires a pre-issued, matching "APPROVE UPDATE" approval record.
#
# Purpose: Execute the UPDATE stage for one issue field.
# Supported OS: Linux, macOS (Bash).
# Dependencies: scripts/common/common.sh
# Parameters: --site-url --issue-key --field-name --field-value-json
#   --email --api-token --user --operation-id [--dry-run]
# Authentication: Jira Cloud basic auth (email + API token).
# Required permissions: "Edit issues" Jira permission.
# Approval requirements: MANDATORY "APPROVE UPDATE".
# Dry-run: --dry-run supported.
# API/MCP dependency: REST fallback (PUT /rest/api/3/issue/{issueIdOrKey}).
# Exit codes: 0 success, 6 approval denied, 7 verification failure, 1 general failure.
# Output: JSON result.
# Verification: GET after update; confirm field value matches.
# Audit: writes one WRITE audit record.
# Security: TLS enforced; approval re-checked immediately before PUT.
#
# Example:
#   ./update-issue-field.sh --site-url https://example.atlassian.net \
#     --issue-key ABC-123 --field-name priority --field-value-json '{"name":"P1"}' \
#     --email jdoe@example.com --api-token "$JIRA_API_TOKEN" --user jdoe --operation-id op-123

set -euo pipefail
SCRIPT_VERSION="1.0.0"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../../../../scripts/common/common.sh"

SITE_URL="" ISSUE_KEY="" FIELD_NAME="" FIELD_VALUE_JSON="" EMAIL="" API_TOKEN="" USER_NAME="" OPERATION_ID="" DRY_RUN=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --site-url) SITE_URL="$2"; shift 2 ;;
    --issue-key) ISSUE_KEY="$2"; shift 2 ;;
    --field-name) FIELD_NAME="$2"; shift 2 ;;
    --field-value-json) FIELD_VALUE_JSON="$2"; shift 2 ;;
    --email) EMAIL="$2"; shift 2 ;;
    --api-token) API_TOKEN="$2"; shift 2 ;;
    --user) USER_NAME="$2"; shift 2 ;;
    --operation-id) OPERATION_ID="$2"; shift 2 ;;
    --dry-run) DRY_RUN=true; shift ;;
    *) echo "Unknown argument: $1" >&2; exit "$EXIT_INVALID_PARAMETERS" ;;
  esac
done
[[ -z "$SITE_URL" || -z "$ISSUE_KEY" || -z "$FIELD_NAME" || -z "$FIELD_VALUE_JSON" || -z "$EMAIL" || -z "$API_TOKEN" || -z "$USER_NAME" || -z "$OPERATION_ID" ]] && { echo "Missing required arguments" >&2; exit "$EXIT_INVALID_PARAMETERS"; }

OPERATION_KEY="jira.issue.update"
set +e
APPROVAL_OUTPUT="$(test_approval_token "$OPERATION_ID" "jira" "$ISSUE_KEY" "$OPERATION_KEY" "APPROVE UPDATE")"
APPROVAL_STATUS=$?
set -e

if [[ $APPROVAL_STATUS -ne 0 ]]; then
  write_audit_log "$OPERATION_ID" "$USER_NAME" "jira" "cloud" "issue" "UPDATE" "$ISSUE_KEY" \
    "rest-api" "jira-issues" "update-issue-field.sh" "$SCRIPT_VERSION" \
    "WRITE" true "DENIED" "DENIED" "NOT_APPLICABLE" "$APPROVAL_OUTPUT"
  echo "$APPROVAL_OUTPUT" >&2
  exit "$EXIT_APPROVAL_DENIED"
fi

if [[ "$DRY_RUN" == true ]]; then
  echo "(dry-run) Would UPDATE field '$FIELD_NAME' on issue '$ISSUE_KEY'. No change made."
  exit "$EXIT_SUCCESS"
fi

URI="$SITE_URL/rest/api/3/issue/$ISSUE_KEY"
BASIC="$(printf '%s:%s' "$EMAIL" "$API_TOKEN" | base64 | tr -d '\n')"
BODY="$(jq -nc --arg f "$FIELD_NAME" --argjson v "$FIELD_VALUE_JSON" '{fields: {($f): $v}}')"

if invoke_secure_rest PUT "$URI" "$BASIC" "Basic" "$BODY" >/dev/null; then
  set_approval_consumed "$OPERATION_ID"
  VERIFICATION="FAILED"; RESULT="UNKNOWN"
  if CURRENT="$(invoke_secure_rest GET "$URI" "$BASIC" "Basic")"; then
    CUR_VALUE="$(echo "$CURRENT" | jq -c --arg f "$FIELD_NAME" '.fields[$f]')"
    EXP_VALUE="$(echo "$FIELD_VALUE_JSON" | jq -c '.')"
    if [[ "$CUR_VALUE" == "$EXP_VALUE" ]]; then VERIFICATION="CONFIRMED"; RESULT="SUCCESS"; fi
  fi

  write_audit_log "$OPERATION_ID" "$USER_NAME" "jira" "cloud" "issue" "UPDATE" "$ISSUE_KEY" \
    "rest-api" "jira-issues" "update-issue-field.sh" "$SCRIPT_VERSION" \
    "WRITE" true "APPROVED" "$RESULT" "$VERIFICATION" "null"

  jq -nc --arg o "$OPERATION_ID" --arg t "$ISSUE_KEY" --arg r "$RESULT" --arg v "$VERIFICATION" \
    '{operationId:$o,target:$t,result:$r,verification:$v}'

  [[ "$VERIFICATION" != "CONFIRMED" ]] && exit "$EXIT_VERIFICATION_FAILURE"
  exit "$EXIT_SUCCESS"
else
  write_audit_log "$OPERATION_ID" "$USER_NAME" "jira" "cloud" "issue" "UPDATE" "$ISSUE_KEY" \
    "rest-api" "jira-issues" "update-issue-field.sh" "$SCRIPT_VERSION" \
    "WRITE" true "APPROVED" "FAILURE" "UNKNOWN" "request failed"
  echo "ERROR: failed to update field '$FIELD_NAME' on issue '$ISSUE_KEY'" >&2
  exit "$EXIT_GENERAL_FAILURE"
fi
