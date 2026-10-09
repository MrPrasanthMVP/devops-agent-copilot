#!/usr/bin/env bash
# assign-issue.sh - WRITE: Assigns (or unassigns) a SonarQube issue.
# Requires a pre-issued, matching "APPROVE UPDATE" approval record.
#
# Purpose: Execute the ASSIGN stage for one issue.
# Supported OS: Linux, macOS (Bash).
# Dependencies: scripts/common/common.sh
# Parameters: --base-url --issue-key [--assignee] [--organization] --user
#   --operation-id [--dry-run]
# Authentication: SonarQube user token (POC: local-secrets).
# Required permissions: 'Browse' + 'Administer Issues' (or assignment rights).
# Approval requirements: MANDATORY "APPROVE UPDATE".
# Dry-run: --dry-run prints the proposed action and exits without mutating.
# Deployment: works against BOTH Server and Cloud (pass --organization for Cloud).
# API/MCP dependency: REST fallback only (POST api/issues/assign) -- no
#   MCP assign-issue tool exists in the verified catalog (see SKILL.md).
# Exit codes: 0 success, 6 approval denied, 7 verification failure, 1 general failure.
# Output: JSON result.
# Verification: search-after-assign; confirm the issue's assignee matches.
# Audit: writes one WRITE audit record.
# Security: TLS enforced; approval re-checked immediately before POST.
#
# Example:
#   ./assign-issue.sh --base-url https://sonarqube.example.internal \
#     --issue-key AbCd1234 --assignee jdoe --user jdoe --operation-id op-aaa111

set -euo pipefail
SCRIPT_VERSION="1.0.0"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../../../../scripts/common/common.sh"

BASE_URL="" ISSUE_KEY="" ASSIGNEE="" ORGANIZATION="" USER_NAME="" OPERATION_ID="" DRY_RUN=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --base-url) BASE_URL="$2"; shift 2 ;;
    --issue-key) ISSUE_KEY="$2"; shift 2 ;;
    --assignee) ASSIGNEE="$2"; shift 2 ;;
    --organization) ORGANIZATION="$2"; shift 2 ;;
    --user) USER_NAME="$2"; shift 2 ;;
    --operation-id) OPERATION_ID="$2"; shift 2 ;;
    --dry-run) DRY_RUN=true; shift ;;
    *) echo "Unknown argument: $1" >&2; exit "$EXIT_INVALID_PARAMETERS" ;;
  esac
done
[[ -z "$BASE_URL" || -z "$ISSUE_KEY" || -z "$USER_NAME" || -z "$OPERATION_ID" ]] && { echo "Missing required arguments" >&2; exit "$EXIT_INVALID_PARAMETERS"; }

TARGET="$ISSUE_KEY"
OPERATION_KEY="sonarqube.issue.assign"

set +e
APPROVAL_OUTPUT="$(test_approval_token "$OPERATION_ID" "sonarqube" "$TARGET" "$OPERATION_KEY" "APPROVE UPDATE")"
set -e
if [[ "$APPROVAL_OUTPUT" != "VALID" ]]; then
  write_audit_log "$OPERATION_ID" "$USER_NAME" "sonarqube" "runtime-detected" "issue" "ASSIGN" "$TARGET" \
    "rest-api" "sonarqube-issues" "assign-issue.sh" "$SCRIPT_VERSION" \
    "WRITE" true "DENIED" "DENIED" "NOT_APPLICABLE" "${APPROVAL_OUTPUT#INVALID: }"
  echo "ERROR: Approval check failed: ${APPROVAL_OUTPUT#INVALID: }" >&2
  exit "$EXIT_APPROVAL_DENIED"
fi

if [[ "$DRY_RUN" == true ]]; then
  echo "(dry-run) Would ASSIGN SonarQube issue '$TARGET' to '$ASSIGNEE'. No change made."
  exit "$EXIT_SUCCESS"
fi

ASSIGN_URI="$BASE_URL/api/issues/assign"
SEARCH_URI="$BASE_URL/api/issues/search?issues=$ISSUE_KEY"
if [[ -n "$ORGANIZATION" ]]; then
  ASSIGN_URI="$ASSIGN_URI?organization=$ORGANIZATION"
  SEARCH_URI="$SEARCH_URI&organization=$ORGANIZATION"
fi
TOKEN="$(read_local_secret sonarqube)"
BODY="$(build_form_body issue "$ISSUE_KEY" assignee "$ASSIGNEE")"

if invoke_secure_rest POST "$ASSIGN_URI" "$TOKEN" "Bearer" "$BODY" "application/x-www-form-urlencoded" >/dev/null; then
  set_approval_consumed "$OPERATION_ID"
  VERIFICATION="FAILED"; RESULT="UNKNOWN"
  if FOUND="$(invoke_secure_rest GET "$SEARCH_URI" "$TOKEN")"; then
    ACTUAL_ASSIGNEE="$(echo "$FOUND" | jq -r --arg k "$ISSUE_KEY" '.issues[] | select(.key==$k) | .assignee // ""')"
    if [[ "$ACTUAL_ASSIGNEE" == "$ASSIGNEE" ]]; then VERIFICATION="CONFIRMED"; RESULT="SUCCESS"; fi
  fi

  write_audit_log "$OPERATION_ID" "$USER_NAME" "sonarqube" "runtime-detected" "issue" "ASSIGN" "$TARGET" \
    "rest-api" "sonarqube-issues" "assign-issue.sh" "$SCRIPT_VERSION" \
    "WRITE" true "APPROVED" "$RESULT" "$VERIFICATION" "null"

  jq -nc --arg o "$OPERATION_ID" --arg t "$TARGET" --arg a "$ASSIGNEE" --arg r "$RESULT" --arg v "$VERIFICATION" \
    '{operationId:$o,target:$t,assignee:$a,result:$r,verification:$v}'

  [[ "$VERIFICATION" != "CONFIRMED" ]] && exit "$EXIT_VERIFICATION_FAILURE"
  exit "$EXIT_SUCCESS"
else
  write_audit_log "$OPERATION_ID" "$USER_NAME" "sonarqube" "runtime-detected" "issue" "ASSIGN" "$TARGET" \
    "rest-api" "sonarqube-issues" "assign-issue.sh" "$SCRIPT_VERSION" \
    "WRITE" true "APPROVED" "FAILURE" "UNKNOWN" "request failed"
  echo "ERROR: failed to assign issue '$TARGET'" >&2
  exit "$EXIT_GENERAL_FAILURE"
fi
