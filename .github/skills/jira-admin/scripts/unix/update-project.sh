#!/usr/bin/env bash
# update-project.sh - ADMINISTRATIVE: Updates a Jira Cloud project's lead.
# Requires a pre-issued "APPROVE ADMIN CHANGE" approval record.
#
# Purpose: Execute the UPDATE stage for one project admin field.
# Supported OS: Linux, macOS (Bash). Dependencies: scripts/common/common.sh
# Parameters: --site-url --project-key --lead-account-id --email --api-token
#   --user --operation-id [--dry-run]
# Authentication: Jira Cloud basic auth (email + API token).
# Required permissions: "Administer projects" Jira permission.
# Approval requirements: MANDATORY "APPROVE ADMIN CHANGE".
# Dry-run: --dry-run supported.
# API/MCP dependency: REST fallback (PUT /rest/api/3/project/{projectIdOrKey}).
# Exit codes: 0 success, 6 approval denied, 7 verification failure, 1 general failure.
# Output: JSON result. Verification: GET after update; confirm lead.accountId.
# Audit: writes one ADMINISTRATIVE audit record.
# Security: TLS enforced; approval re-checked immediately before PUT.
#
# Example:
#   ./update-project.sh --site-url https://example.atlassian.net --project-key ABC \
#     --lead-account-id 5b10a2844c20165700ede21g --email jdoe@example.com \
#     --api-token "$JIRA_API_TOKEN" --user jdoe --operation-id op-123

set -euo pipefail
SCRIPT_VERSION="1.0.0"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../../../../scripts/common/common.sh"

SITE_URL="" PROJECT_KEY="" LEAD_ACCOUNT_ID="" EMAIL="" API_TOKEN="" USER_NAME="" OPERATION_ID="" DRY_RUN=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --site-url) SITE_URL="$2"; shift 2 ;;
    --project-key) PROJECT_KEY="$2"; shift 2 ;;
    --lead-account-id) LEAD_ACCOUNT_ID="$2"; shift 2 ;;
    --email) EMAIL="$2"; shift 2 ;;
    --api-token) API_TOKEN="$2"; shift 2 ;;
    --user) USER_NAME="$2"; shift 2 ;;
    --operation-id) OPERATION_ID="$2"; shift 2 ;;
    --dry-run) DRY_RUN=true; shift ;;
    *) echo "Unknown argument: $1" >&2; exit "$EXIT_INVALID_PARAMETERS" ;;
  esac
done
[[ -z "$SITE_URL" || -z "$PROJECT_KEY" || -z "$LEAD_ACCOUNT_ID" || -z "$EMAIL" || -z "$API_TOKEN" || -z "$USER_NAME" || -z "$OPERATION_ID" ]] && { echo "Missing required arguments" >&2; exit "$EXIT_INVALID_PARAMETERS"; }

OPERATION_KEY="jira.admin.update"
set +e
APPROVAL_OUTPUT="$(test_approval_token "$OPERATION_ID" "jira" "$PROJECT_KEY" "$OPERATION_KEY" "APPROVE ADMIN CHANGE")"
APPROVAL_STATUS=$?
set -e

if [[ $APPROVAL_STATUS -ne 0 ]]; then
  write_audit_log "$OPERATION_ID" "$USER_NAME" "jira" "cloud" "project" "UPDATE" "$PROJECT_KEY" \
    "rest-api" "jira-admin" "update-project.sh" "$SCRIPT_VERSION" \
    "ADMINISTRATIVE" true "DENIED" "DENIED" "NOT_APPLICABLE" "$APPROVAL_OUTPUT"
  echo "$APPROVAL_OUTPUT" >&2
  exit "$EXIT_APPROVAL_DENIED"
fi

if [[ "$DRY_RUN" == true ]]; then
  echo "(dry-run) Would UPDATE project '$PROJECT_KEY' lead to '$LEAD_ACCOUNT_ID'. No change made."
  exit "$EXIT_SUCCESS"
fi

URI="$SITE_URL/rest/api/3/project/$PROJECT_KEY"
BASIC="$(printf '%s:%s' "$EMAIL" "$API_TOKEN" | base64 | tr -d '\n')"
BODY="$(jq -nc --arg lead "$LEAD_ACCOUNT_ID" '{leadAccountId:$lead}')"

if invoke_secure_rest PUT "$URI" "$BASIC" "Basic" "$BODY" >/dev/null; then
  set_approval_consumed "$OPERATION_ID"
  VERIFICATION="FAILED"; RESULT="UNKNOWN"
  if CURRENT="$(invoke_secure_rest GET "$URI" "$BASIC" "Basic")"; then
    CUR_LEAD="$(echo "$CURRENT" | jq -r '.lead.accountId // empty')"
    [[ "$CUR_LEAD" == "$LEAD_ACCOUNT_ID" ]] && { VERIFICATION="CONFIRMED"; RESULT="SUCCESS"; }
  fi

  write_audit_log "$OPERATION_ID" "$USER_NAME" "jira" "cloud" "project" "UPDATE" "$PROJECT_KEY" \
    "rest-api" "jira-admin" "update-project.sh" "$SCRIPT_VERSION" \
    "ADMINISTRATIVE" true "APPROVED" "$RESULT" "$VERIFICATION" "null"

  jq -nc --arg o "$OPERATION_ID" --arg t "$PROJECT_KEY" --arg r "$RESULT" --arg v "$VERIFICATION" \
    '{operationId:$o,target:$t,result:$r,verification:$v}'
  [[ "$VERIFICATION" != "CONFIRMED" ]] && exit "$EXIT_VERIFICATION_FAILURE"
  exit "$EXIT_SUCCESS"
else
  write_audit_log "$OPERATION_ID" "$USER_NAME" "jira" "cloud" "project" "UPDATE" "$PROJECT_KEY" \
    "rest-api" "jira-admin" "update-project.sh" "$SCRIPT_VERSION" \
    "ADMINISTRATIVE" true "APPROVED" "FAILURE" "UNKNOWN" "request failed"
  echo "ERROR: failed to update project '$PROJECT_KEY'" >&2
  exit "$EXIT_GENERAL_FAILURE"
fi
