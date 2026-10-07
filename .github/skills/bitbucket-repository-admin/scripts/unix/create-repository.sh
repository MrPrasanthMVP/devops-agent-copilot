#!/usr/bin/env bash
# create-repository.sh - WRITE: Creates a Bitbucket DC repository.
# Requires a pre-issued, matching "APPROVE CREATE" approval record.
#
# Purpose: Execute the CREATE stage for a new repository.
# Supported OS: Linux, macOS (Bash).
# Dependencies: scripts/common/common.sh
# Parameters: --base-url --project-key --repository-slug --user --operation-id [--dry-run]
# Authentication: Bitbucket HTTP access token (POC: local-secrets).
# Required permissions: Bitbucket project "Write" permission.
# Approval requirements: MANDATORY "APPROVE CREATE".
# Dry-run: --dry-run prints the proposed action and exits without mutating.
# API/MCP dependency: REST fallback (POST /rest/api/1.0/projects/{projectKey}/repos).
# Exit codes: 0 success, 6 approval denied, 7 verification failure, 1 general failure.
# Output: JSON result.
# Verification: GET after create; confirm slug matches.
# Audit: writes one WRITE audit record.
# Security: TLS enforced; approval re-checked immediately before POST.
#
# Example:
#   ./create-repository.sh --base-url https://bitbucket.example.com \
#     --project-key ABC --repository-slug new-svc --user jdoe --operation-id op-aaa111

set -euo pipefail
SCRIPT_VERSION="1.0.0"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../../../../scripts/common/common.sh"

BASE_URL="" PROJECT_KEY="" REPO_SLUG="" USER_NAME="" OPERATION_ID="" DRY_RUN=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --base-url) BASE_URL="$2"; shift 2 ;;
    --project-key) PROJECT_KEY="$2"; shift 2 ;;
    --repository-slug) REPO_SLUG="$2"; shift 2 ;;
    --user) USER_NAME="$2"; shift 2 ;;
    --operation-id) OPERATION_ID="$2"; shift 2 ;;
    --dry-run) DRY_RUN=true; shift ;;
    *) echo "Unknown argument: $1" >&2; exit "$EXIT_INVALID_PARAMETERS" ;;
  esac
done
[[ -z "$BASE_URL" || -z "$PROJECT_KEY" || -z "$REPO_SLUG" || -z "$USER_NAME" || -z "$OPERATION_ID" ]] && { echo "Missing required arguments" >&2; exit "$EXIT_INVALID_PARAMETERS"; }

TARGET="$PROJECT_KEY/$REPO_SLUG"
OPERATION_KEY="bitbucket.repository.create"

set +e
APPROVAL_OUTPUT="$(test_approval_token "$OPERATION_ID" "bitbucket" "$TARGET" "$OPERATION_KEY" "APPROVE CREATE")"
APPROVAL_STATUS=$?
set -e

if [[ $APPROVAL_STATUS -ne 0 ]]; then
  write_audit_log "$OPERATION_ID" "$USER_NAME" "bitbucket" "9.4.5" "repository" "CREATE" "$TARGET" \
    "rest-api" "bitbucket-repository-admin" "create-repository.sh" "$SCRIPT_VERSION" \
    "WRITE" true "DENIED" "DENIED" "NOT_APPLICABLE" "$APPROVAL_OUTPUT"
  echo "$APPROVAL_OUTPUT" >&2
  exit "$EXIT_APPROVAL_DENIED"
fi

if [[ "$DRY_RUN" == true ]]; then
  echo "(dry-run) Would CREATE Bitbucket repository '$TARGET'. No change made."
  exit "$EXIT_SUCCESS"
fi

COLLECTION_URI="$BASE_URL/rest/api/1.0/projects/$PROJECT_KEY/repos"
REPO_URI="$COLLECTION_URI/$REPO_SLUG"
TOKEN="$(read_local_secret bitbucket)"
BODY="$(jq -nc --arg name "$REPO_SLUG" '{name:$name, scmId:"git"}')"

if invoke_secure_rest POST "$COLLECTION_URI" "$TOKEN" "Bearer" "$BODY" >/dev/null; then
  set_approval_consumed "$OPERATION_ID"
  VERIFICATION="FAILED"; RESULT="UNKNOWN"
  if CREATED="$(invoke_secure_rest GET "$REPO_URI" "$TOKEN")"; then
    SLUG="$(echo "$CREATED" | jq -r '.slug // empty')"
    if [[ "$SLUG" == "$REPO_SLUG" ]]; then VERIFICATION="CONFIRMED"; RESULT="SUCCESS"; fi
  fi

  write_audit_log "$OPERATION_ID" "$USER_NAME" "bitbucket" "9.4.5" "repository" "CREATE" "$TARGET" \
    "rest-api" "bitbucket-repository-admin" "create-repository.sh" "$SCRIPT_VERSION" \
    "WRITE" true "APPROVED" "$RESULT" "$VERIFICATION" "null"

  jq -nc --arg o "$OPERATION_ID" --arg t "$TARGET" --arg r "$RESULT" --arg v "$VERIFICATION" \
    '{operationId:$o,target:$t,result:$r,verification:$v}'

  [[ "$VERIFICATION" != "CONFIRMED" ]] && exit "$EXIT_VERIFICATION_FAILURE"
  exit "$EXIT_SUCCESS"
else
  write_audit_log "$OPERATION_ID" "$USER_NAME" "bitbucket" "9.4.5" "repository" "CREATE" "$TARGET" \
    "rest-api" "bitbucket-repository-admin" "create-repository.sh" "$SCRIPT_VERSION" \
    "WRITE" true "APPROVED" "FAILURE" "UNKNOWN" "request failed"
  echo "ERROR: failed to create repository '$TARGET'" >&2
  exit "$EXIT_GENERAL_FAILURE"
fi
