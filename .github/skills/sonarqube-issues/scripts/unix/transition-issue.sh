#!/usr/bin/env bash
# transition-issue.sh - WRITE: Performs a workflow transition on a
# SonarQube issue (e.g. confirm, resolve, reopen). Requires a
# pre-issued, matching "APPROVE UPDATE" approval record.
#
# Purpose: Execute the TRANSITION stage for one issue.
# Supported OS: Linux, macOS (Bash).
# Dependencies: scripts/common/common.sh
# Parameters: --base-url --issue-key --transition [--organization] --user
#   --operation-id [--dry-run]
# Transition values: confirm, unconfirm, reopen, resolve, falsepositive, wontfix
# Authentication: SonarQube user token (POC: local-secrets).
# Required permissions: 'confirm'/'falsepositive'/'wontfix' require
#   'Administer Issues'; others require only 'Browse'.
# Approval requirements: MANDATORY "APPROVE UPDATE".
# Dry-run: --dry-run prints the proposed action and exits without mutating.
# Deployment: works against BOTH Server and Cloud (pass --organization for Cloud).
# API/MCP dependency: REST fallback (POST api/issues/do_transition). The
#   MCP change_sonar_issue_status tool exposes a narrower vocabulary
#   (accept/falsepositive/reopen) -- this script always uses REST
#   directly so every transition value is available.
# Exit codes: 0 success, 6 approval denied, 7 verification failure, 1 general failure.
# Output: JSON result.
# Verification: search-after-transition; confirm the issue's top-level
#   `status` matches the expected post-transition value (the `resolution`
#   sub-field is not separately re-verified).
# Audit: writes one WRITE audit record.
# Security: TLS enforced; approval re-checked immediately before POST.
#
# Example:
#   ./transition-issue.sh --base-url https://sonarqube.example.internal \
#     --issue-key AbCd1234 --transition resolve --user jdoe --operation-id op-aaa111

set -euo pipefail
SCRIPT_VERSION="1.0.0"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../../../../scripts/common/common.sh"

BASE_URL="" ISSUE_KEY="" TRANSITION="" ORGANIZATION="" USER_NAME="" OPERATION_ID="" DRY_RUN=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --base-url) BASE_URL="$2"; shift 2 ;;
    --issue-key) ISSUE_KEY="$2"; shift 2 ;;
    --transition) TRANSITION="$2"; shift 2 ;;
    --organization) ORGANIZATION="$2"; shift 2 ;;
    --user) USER_NAME="$2"; shift 2 ;;
    --operation-id) OPERATION_ID="$2"; shift 2 ;;
    --dry-run) DRY_RUN=true; shift ;;
    *) echo "Unknown argument: $1" >&2; exit "$EXIT_INVALID_PARAMETERS" ;;
  esac
done
[[ -z "$BASE_URL" || -z "$ISSUE_KEY" || -z "$TRANSITION" || -z "$USER_NAME" || -z "$OPERATION_ID" ]] && { echo "Missing required arguments" >&2; exit "$EXIT_INVALID_PARAMETERS"; }

case "$TRANSITION" in
  confirm) EXPECTED_STATUS="CONFIRMED" ;;
  unconfirm) EXPECTED_STATUS="REOPENED" ;;
  reopen) EXPECTED_STATUS="REOPENED" ;;
  resolve) EXPECTED_STATUS="RESOLVED" ;;
  falsepositive) EXPECTED_STATUS="RESOLVED" ;;
  wontfix) EXPECTED_STATUS="RESOLVED" ;;
  *) echo "ERROR: unknown --transition value '$TRANSITION' (expected one of: confirm, unconfirm, reopen, resolve, falsepositive, wontfix)" >&2; exit "$EXIT_INVALID_PARAMETERS" ;;
esac

TARGET="$ISSUE_KEY"
OPERATION_KEY="sonarqube.issue.transition"

set +e
APPROVAL_OUTPUT="$(test_approval_token "$OPERATION_ID" "sonarqube" "$TARGET" "$OPERATION_KEY" "APPROVE UPDATE")"
set -e
if [[ "$APPROVAL_OUTPUT" != "VALID" ]]; then
  write_audit_log "$OPERATION_ID" "$USER_NAME" "sonarqube" "runtime-detected" "issue" "TRANSITION" "$TARGET" \
    "rest-api" "sonarqube-issues" "transition-issue.sh" "$SCRIPT_VERSION" \
    "WRITE" true "DENIED" "DENIED" "NOT_APPLICABLE" "${APPROVAL_OUTPUT#INVALID: }"
  echo "ERROR: Approval check failed: ${APPROVAL_OUTPUT#INVALID: }" >&2
  exit "$EXIT_APPROVAL_DENIED"
fi

if [[ "$DRY_RUN" == true ]]; then
  echo "(dry-run) Would TRANSITION ($TRANSITION) SonarQube issue '$TARGET'. No change made."
  exit "$EXIT_SUCCESS"
fi

TRANSITION_URI="$BASE_URL/api/issues/do_transition"
SEARCH_URI="$BASE_URL/api/issues/search?issues=$ISSUE_KEY"
if [[ -n "$ORGANIZATION" ]]; then
  TRANSITION_URI="$TRANSITION_URI?organization=$ORGANIZATION"
  SEARCH_URI="$SEARCH_URI&organization=$ORGANIZATION"
fi
TOKEN="$(read_local_secret sonarqube)"
BODY="$(build_form_body issue "$ISSUE_KEY" transition "$TRANSITION")"

if invoke_secure_rest POST "$TRANSITION_URI" "$TOKEN" "Bearer" "$BODY" "application/x-www-form-urlencoded" >/dev/null; then
  set_approval_consumed "$OPERATION_ID"
  VERIFICATION="FAILED"; RESULT="UNKNOWN"
  if FOUND="$(invoke_secure_rest GET "$SEARCH_URI" "$TOKEN")"; then
    ACTUAL_STATUS="$(echo "$FOUND" | jq -r --arg k "$ISSUE_KEY" '.issues[] | select(.key==$k) | .status // ""')"
    if [[ "$ACTUAL_STATUS" == "$EXPECTED_STATUS" ]]; then VERIFICATION="CONFIRMED"; RESULT="SUCCESS"; fi
  fi

  write_audit_log "$OPERATION_ID" "$USER_NAME" "sonarqube" "runtime-detected" "issue" "TRANSITION" "$TARGET" \
    "rest-api" "sonarqube-issues" "transition-issue.sh" "$SCRIPT_VERSION" \
    "WRITE" true "APPROVED" "$RESULT" "$VERIFICATION" "null"

  jq -nc --arg o "$OPERATION_ID" --arg t "$TARGET" --arg tr "$TRANSITION" --arg r "$RESULT" --arg v "$VERIFICATION" \
    '{operationId:$o,target:$t,transition:$tr,result:$r,verification:$v}'

  [[ "$VERIFICATION" != "CONFIRMED" ]] && exit "$EXIT_VERIFICATION_FAILURE"
  exit "$EXIT_SUCCESS"
else
  write_audit_log "$OPERATION_ID" "$USER_NAME" "sonarqube" "runtime-detected" "issue" "TRANSITION" "$TARGET" \
    "rest-api" "sonarqube-issues" "transition-issue.sh" "$SCRIPT_VERSION" \
    "WRITE" true "APPROVED" "FAILURE" "UNKNOWN" "request failed"
  echo "ERROR: failed to transition issue '$TARGET'" >&2
  exit "$EXIT_GENERAL_FAILURE"
fi
