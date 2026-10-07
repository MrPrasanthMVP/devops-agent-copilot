#!/usr/bin/env bash
# create-project.sh - ADMINISTRATIVE: Creates a new Jira Cloud project.
# Requires a pre-issued, matching "APPROVE ADMIN CHANGE" approval record.
#
# Purpose: Execute the CREATE stage for a new Jira project.
# Supported OS: Linux, macOS (Bash).
# Dependencies: scripts/common/common.sh
# Parameters: --site-url --project-key --project-name --project-type-key
#   --lead-account-id --email --api-token --user --operation-id [--dry-run]
# Authentication: Jira Cloud basic auth (email + API token).
# Required permissions: "Administer Jira" global permission (verified:
#   https://developer.atlassian.com/cloud/jira/platform/rest/v3/api-group-projects/ ).
# Approval requirements: MANDATORY "APPROVE ADMIN CHANGE".
# Dry-run: --dry-run supported.
# API/MCP dependency: REST fallback (POST /rest/api/3/project).
# Exit codes: 0 success, 6 approval denied, 7 verification failure, 1 general failure.
# Output: JSON result.
# Verification: GET the created project; confirm key/name match.
# Audit: writes one WRITE audit record (classified ADMINISTRATIVE).
# Security: TLS enforced; approval re-checked immediately before POST.
#
# Example:
#   ./create-project.sh --site-url https://example.atlassian.net \
#     --project-key NEWPRJ --project-name "New Project" --project-type-key business \
#     --lead-account-id "5b10a2844c20165700ede21g" --email jdoe@example.com \
#     --api-token "$JIRA_API_TOKEN" --user jdoe --operation-id op-123

set -euo pipefail
SCRIPT_VERSION="1.0.0"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../../../../scripts/common/common.sh"

SITE_URL="" PROJECT_KEY="" PROJECT_NAME="" PROJECT_TYPE_KEY="" LEAD_ACCOUNT_ID="" EMAIL="" API_TOKEN="" USER_NAME="" OPERATION_ID="" DRY_RUN=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --site-url) SITE_URL="$2"; shift 2 ;;
    --project-key) PROJECT_KEY="$2"; shift 2 ;;
    --project-name) PROJECT_NAME="$2"; shift 2 ;;
    --project-type-key) PROJECT_TYPE_KEY="$2"; shift 2 ;;
    --lead-account-id) LEAD_ACCOUNT_ID="$2"; shift 2 ;;
    --email) EMAIL="$2"; shift 2 ;;
    --api-token) API_TOKEN="$2"; shift 2 ;;
    --user) USER_NAME="$2"; shift 2 ;;
    --operation-id) OPERATION_ID="$2"; shift 2 ;;
    --dry-run) DRY_RUN=true; shift ;;
    *) echo "Unknown argument: $1" >&2; exit "$EXIT_INVALID_PARAMETERS" ;;
  esac
done
[[ -z "$SITE_URL" || -z "$PROJECT_KEY" || -z "$PROJECT_NAME" || -z "$PROJECT_TYPE_KEY" || -z "$LEAD_ACCOUNT_ID" || -z "$EMAIL" || -z "$API_TOKEN" || -z "$USER_NAME" || -z "$OPERATION_ID" ]] && { echo "Missing required arguments" >&2; exit "$EXIT_INVALID_PARAMETERS"; }

OPERATION_KEY="jira.project.create"
set +e
APPROVAL_OUTPUT="$(test_approval_token "$OPERATION_ID" "jira" "$PROJECT_KEY" "$OPERATION_KEY" "APPROVE ADMIN CHANGE")"
APPROVAL_STATUS=$?
set -e

if [[ $APPROVAL_STATUS -ne 0 ]]; then
  write_audit_log "$OPERATION_ID" "$USER_NAME" "jira" "cloud" "project" "CREATE" "$PROJECT_KEY" \
    "rest-api" "jira-admin" "create-project.sh" "$SCRIPT_VERSION" \
    "ADMINISTRATIVE" true "DENIED" "DENIED" "NOT_APPLICABLE" "$APPROVAL_OUTPUT"
  echo "$APPROVAL_OUTPUT" >&2
  exit "$EXIT_APPROVAL_DENIED"
fi

if [[ "$DRY_RUN" == true ]]; then
  echo "(dry-run) Would CREATE Jira project '$PROJECT_KEY'. No change made."
  exit "$EXIT_SUCCESS"
fi

URI="$SITE_URL/rest/api/3/project"
BASIC="$(printf '%s:%s' "$EMAIL" "$API_TOKEN" | base64 | tr -d '\n')"
BODY="$(jq -nc --arg key "$PROJECT_KEY" --arg name "$PROJECT_NAME" --arg type "$PROJECT_TYPE_KEY" \
  --arg lead "$LEAD_ACCOUNT_ID" '{key:$key,name:$name,projectTypeKey:$type,leadAccountId:$lead}')"

if CREATED="$(invoke_secure_rest POST "$URI" "$BASIC" "Basic" "$BODY")"; then
  set_approval_consumed "$OPERATION_ID"
  VERIFICATION="FAILED"; RESULT="UNKNOWN"
  CHECK_URI="$SITE_URL/rest/api/3/project/$PROJECT_KEY"
  if CURRENT="$(invoke_secure_rest GET "$CHECK_URI" "$BASIC" "Basic")"; then
    CUR_KEY="$(echo "$CURRENT" | jq -r '.key // empty')"
    CUR_NAME="$(echo "$CURRENT" | jq -r '.name // empty')"
    if [[ "$CUR_KEY" == "$PROJECT_KEY" && "$CUR_NAME" == "$PROJECT_NAME" ]]; then VERIFICATION="CONFIRMED"; RESULT="SUCCESS"; fi
  fi

  write_audit_log "$OPERATION_ID" "$USER_NAME" "jira" "cloud" "project" "CREATE" "$PROJECT_KEY" \
    "rest-api" "jira-admin" "create-project.sh" "$SCRIPT_VERSION" \
    "ADMINISTRATIVE" true "APPROVED" "$RESULT" "$VERIFICATION" "null"

  jq -nc --arg o "$OPERATION_ID" --arg t "$PROJECT_KEY" --arg r "$RESULT" --arg v "$VERIFICATION" \
    '{operationId:$o,target:$t,result:$r,verification:$v}'

  [[ "$VERIFICATION" != "CONFIRMED" ]] && exit "$EXIT_VERIFICATION_FAILURE"
  exit "$EXIT_SUCCESS"
else
  write_audit_log "$OPERATION_ID" "$USER_NAME" "jira" "cloud" "project" "CREATE" "$PROJECT_KEY" \
    "rest-api" "jira-admin" "create-project.sh" "$SCRIPT_VERSION" \
    "ADMINISTRATIVE" true "APPROVED" "FAILURE" "UNKNOWN" "request failed"
  echo "ERROR: failed to create project '$PROJECT_KEY'" >&2
  exit "$EXIT_GENERAL_FAILURE"
fi
