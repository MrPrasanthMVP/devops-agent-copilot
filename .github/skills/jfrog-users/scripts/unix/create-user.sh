#!/usr/bin/env bash
# create-user.sh - SECURITY_SENSITIVE: Creates a new JFrog Platform user.
# Requires a pre-issued "APPROVE SECURITY CHANGE" approval record.
#
# Purpose: Execute the CREATE stage for a user account.
# Supported OS: Linux, macOS (Bash).
# Dependencies: scripts/common/common.sh
# Parameters: --base-url --username --email --password --user
#   --operation-id [--dry-run]
#   (--password should be supplied via an env var expansion by the
#    caller, e.g. --password "$JFROG_NEW_USER_PASSWORD", never a literal
#    hardcoded in a script or committed file)
# Authentication: JFrog access token (POC: local-secrets).
# Required permissions: admin privileges.
# Approval requirements: MANDATORY "APPROVE SECURITY CHANGE".
# Dry-run: --dry-run supported.
# API/MCP dependency: REST fallback (POST /access/api/v2/users).
# Exit codes: 0 success, 6 approval denied, 7 verification failure, 1 general failure.
# Output: JSON result (never includes the password).
# Verification: GET after create; confirm username matches.
# Audit: writes one SECURITY_SENSITIVE audit record; password is never
#   included in the audit payload (redact_json is a backstop only).
# Security: TLS enforced; approval re-checked immediately before POST.
#
# Example:
#   ./create-user.sh --base-url https://jfrog.example.com --username jdoe \
#     --email jdoe@example.com --password "$NEW_USER_PASSWORD" \
#     --user admin-jdoe --operation-id op-123

set -euo pipefail
SCRIPT_VERSION="1.0.0"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../../../../scripts/common/common.sh"

BASE_URL="" USERNAME="" EMAIL="" PASSWORD="" USER_NAME="" OPERATION_ID="" DRY_RUN=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --base-url) BASE_URL="$2"; shift 2 ;;
    --username) USERNAME="$2"; shift 2 ;;
    --email) EMAIL="$2"; shift 2 ;;
    --password) PASSWORD="$2"; shift 2 ;;
    --user) USER_NAME="$2"; shift 2 ;;
    --operation-id) OPERATION_ID="$2"; shift 2 ;;
    --dry-run) DRY_RUN=true; shift ;;
    *) echo "Unknown argument: $1" >&2; exit "$EXIT_INVALID_PARAMETERS" ;;
  esac
done
[[ -z "$BASE_URL" || -z "$USERNAME" || -z "$EMAIL" || -z "$PASSWORD" || -z "$USER_NAME" || -z "$OPERATION_ID" ]] && { echo "Missing required arguments" >&2; exit "$EXIT_INVALID_PARAMETERS"; }

OPERATION_KEY="jfrog.users.create"
set +e
APPROVAL_OUTPUT="$(test_approval_token "$OPERATION_ID" "jfrog" "$USERNAME" "$OPERATION_KEY" "APPROVE SECURITY CHANGE")"
APPROVAL_STATUS=$?
set -e

if [[ $APPROVAL_STATUS -ne 0 ]]; then
  write_audit_log "$OPERATION_ID" "$USER_NAME" "jfrog" "runtime-detected" "user" "CREATE" "$USERNAME" \
    "rest-api" "jfrog-users" "create-user.sh" "$SCRIPT_VERSION" \
    "SECURITY_SENSITIVE" true "DENIED" "DENIED" "NOT_APPLICABLE" "$APPROVAL_OUTPUT"
  echo "$APPROVAL_OUTPUT" >&2
  exit "$EXIT_APPROVAL_DENIED"
fi

if [[ "$DRY_RUN" == true ]]; then
  echo "(dry-run) Would CREATE JFrog user '$USERNAME'. No change made."
  exit "$EXIT_SUCCESS"
fi

COLLECTION_URI="$BASE_URL/access/api/v2/users"
USER_URI="$COLLECTION_URI/$USERNAME"
TOKEN="$(read_local_secret jfrog)"
BODY="$(jq -nc --arg u "$USERNAME" --arg e "$EMAIL" --arg p "$PASSWORD" '{username:$u,email:$e,password:$p}')"

if invoke_secure_rest POST "$COLLECTION_URI" "$TOKEN" "Bearer" "$BODY" >/dev/null; then
  unset BODY
  set_approval_consumed "$OPERATION_ID"
  VERIFICATION="FAILED"; RESULT="UNKNOWN"
  if CREATED="$(invoke_secure_rest GET "$USER_URI" "$TOKEN")"; then
    CUR_USERNAME="$(echo "$CREATED" | jq -r '.username // empty')"
    if [[ "$CUR_USERNAME" == "$USERNAME" ]]; then VERIFICATION="CONFIRMED"; RESULT="SUCCESS"; fi
  fi

  write_audit_log "$OPERATION_ID" "$USER_NAME" "jfrog" "runtime-detected" "user" "CREATE" "$USERNAME" \
    "rest-api" "jfrog-users" "create-user.sh" "$SCRIPT_VERSION" \
    "SECURITY_SENSITIVE" true "APPROVED" "$RESULT" "$VERIFICATION" "null"

  jq -nc --arg o "$OPERATION_ID" --arg t "$USERNAME" --arg r "$RESULT" --arg v "$VERIFICATION" \
    '{operationId:$o,target:$t,result:$r,verification:$v}'

  [[ "$VERIFICATION" != "CONFIRMED" ]] && exit "$EXIT_VERIFICATION_FAILURE"
  exit "$EXIT_SUCCESS"
else
  write_audit_log "$OPERATION_ID" "$USER_NAME" "jfrog" "runtime-detected" "user" "CREATE" "$USERNAME" \
    "rest-api" "jfrog-users" "create-user.sh" "$SCRIPT_VERSION" \
    "SECURITY_SENSITIVE" true "APPROVED" "FAILURE" "UNKNOWN" "request failed"
  echo "ERROR: failed to create user '$USERNAME'" >&2
  exit "$EXIT_GENERAL_FAILURE"
fi
