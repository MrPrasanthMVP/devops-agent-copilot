#!/usr/bin/env bash
# add-group-member.sh - SECURITY_SENSITIVE: Adds a user to a JFrog
# group. Requires "APPROVE PERMISSION CHANGE". No MCP tool covers this
# -- REST fallback via the user's groups array.
#
# Purpose: Execute the membership-change stage for a group.
# Supported OS: Linux, macOS (Bash).
# Dependencies: scripts/common/common.sh
# Parameters: --base-url --group-name --username --user --operation-id [--dry-run]
# Authentication: JFrog access token (POC: local-secrets).
# Approval requirements: MANDATORY "APPROVE PERMISSION CHANGE" bound to
#   Target = "GroupName/Username".
# API/MCP dependency: REST fallback -- GET then PATCH /access/api/v2/users/{username}.
# Exit codes: 0 success, 6 approval denied, 7 verification failure, 1 general failure.
# Output: JSON result.
# Verification: GET user after PATCH; confirm group present in groups array.
# Audit: writes one SECURITY_SENSITIVE audit record.
# Security: TLS enforced; approval re-checked immediately before PATCH.
#
# Example:
#   ./add-group-member.sh --base-url https://jfrog.example.com --group-name build-team \
#     --username jdoe --user admin-jdoe --operation-id op-123

set -euo pipefail
SCRIPT_VERSION="1.0.0"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../../../../scripts/common/common.sh"

BASE_URL="" GROUP_NAME="" USERNAME="" USER_NAME="" OPERATION_ID="" DRY_RUN=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --base-url) BASE_URL="$2"; shift 2 ;;
    --group-name) GROUP_NAME="$2"; shift 2 ;;
    --username) USERNAME="$2"; shift 2 ;;
    --user) USER_NAME="$2"; shift 2 ;;
    --operation-id) OPERATION_ID="$2"; shift 2 ;;
    --dry-run) DRY_RUN=true; shift ;;
    *) echo "Unknown argument: $1" >&2; exit "$EXIT_INVALID_PARAMETERS" ;;
  esac
done
[[ -z "$BASE_URL" || -z "$GROUP_NAME" || -z "$USERNAME" || -z "$USER_NAME" || -z "$OPERATION_ID" ]] && { echo "Missing required arguments" >&2; exit "$EXIT_INVALID_PARAMETERS"; }

TARGET="$GROUP_NAME/$USERNAME"
OPERATION_KEY="jfrog.groups.update"
set +e
APPROVAL_OUTPUT="$(test_approval_token "$OPERATION_ID" "jfrog" "$TARGET" "$OPERATION_KEY" "APPROVE PERMISSION CHANGE")"
APPROVAL_STATUS=$?
set -e

if [[ $APPROVAL_STATUS -ne 0 ]]; then
  write_audit_log "$OPERATION_ID" "$USER_NAME" "jfrog" "runtime-detected" "group" "UPDATE" "$TARGET" \
    "rest-api" "jfrog-groups" "add-group-member.sh" "$SCRIPT_VERSION" \
    "SECURITY_SENSITIVE" true "DENIED" "DENIED" "NOT_APPLICABLE" "$APPROVAL_OUTPUT"
  echo "$APPROVAL_OUTPUT" >&2
  exit "$EXIT_APPROVAL_DENIED"
fi

if [[ "$DRY_RUN" == true ]]; then
  echo "(dry-run) Would ADD user '$USERNAME' to JFrog group '$GROUP_NAME'. No change made."
  exit "$EXIT_SUCCESS"
fi

TOKEN="$(read_local_secret jfrog)"
USER_URI="$BASE_URL/access/api/v2/users/$USERNAME"

CURRENT_USER="$(invoke_secure_rest GET "$USER_URI" "$TOKEN")"
BODY="$(echo "$CURRENT_USER" | jq -c --arg g "$GROUP_NAME" '{groups: ((.groups // []) + [$g] | unique)}')"

if invoke_secure_rest PATCH "$USER_URI" "$TOKEN" "Bearer" "$BODY" >/dev/null; then
  set_approval_consumed "$OPERATION_ID"
  VERIFICATION="FAILED"; RESULT="UNKNOWN"
  if UPDATED="$(invoke_secure_rest GET "$USER_URI" "$TOKEN")"; then
    if echo "$UPDATED" | jq -e --arg g "$GROUP_NAME" '.groups // [] | index($g) != null' >/dev/null; then
      VERIFICATION="CONFIRMED"; RESULT="SUCCESS"
    fi
  fi

  write_audit_log "$OPERATION_ID" "$USER_NAME" "jfrog" "runtime-detected" "group" "UPDATE" "$TARGET" \
    "rest-api" "jfrog-groups" "add-group-member.sh" "$SCRIPT_VERSION" \
    "SECURITY_SENSITIVE" true "APPROVED" "$RESULT" "$VERIFICATION" "null"

  jq -nc --arg o "$OPERATION_ID" --arg t "$TARGET" --arg r "$RESULT" --arg v "$VERIFICATION" \
    '{operationId:$o,target:$t,result:$r,verification:$v}'

  [[ "$VERIFICATION" != "CONFIRMED" ]] && exit "$EXIT_VERIFICATION_FAILURE"
  exit "$EXIT_SUCCESS"
else
  write_audit_log "$OPERATION_ID" "$USER_NAME" "jfrog" "runtime-detected" "group" "UPDATE" "$TARGET" \
    "rest-api" "jfrog-groups" "add-group-member.sh" "$SCRIPT_VERSION" \
    "SECURITY_SENSITIVE" true "APPROVED" "FAILURE" "UNKNOWN" "request failed"
  echo "ERROR: failed to add user '$USERNAME' to group '$GROUP_NAME'" >&2
  exit "$EXIT_GENERAL_FAILURE"
fi
