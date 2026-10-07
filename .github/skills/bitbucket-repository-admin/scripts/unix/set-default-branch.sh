#!/usr/bin/env bash
# set-default-branch.sh - ADMINISTRATIVE: Sets a Bitbucket repository's
# default branch. Requires a pre-issued "APPROVE ADMIN CHANGE" approval.
#
# Purpose: Execute the UPDATE stage for a repository's default branch.
# Supported OS: Linux, macOS (Bash).
# Dependencies: scripts/common/common.sh
# Parameters: --base-url --project-key --repository-slug --branch --user --operation-id [--dry-run]
# Authentication: Bitbucket HTTP access token (POC: local-secrets).
# Required permissions: Bitbucket project admin permission.
# Approval requirements: MANDATORY "APPROVE ADMIN CHANGE".
# Dry-run: --dry-run supported.
# API/MCP dependency: REST fallback (PUT .../branches/default).
# Exit codes: 0 success, 6 approval denied, 7 verification failure, 1 general failure.
# Output: JSON result.
# Verification: GET default branch after update; confirm match.
# Audit: writes one ADMINISTRATIVE audit record.
# Security: TLS enforced; approval re-checked immediately before PUT.
#
# Example:
#   ./set-default-branch.sh --base-url https://bitbucket.example.com \
#     --project-key ABC --repository-slug xyz --branch main --user jdoe --operation-id op-123

set -euo pipefail
SCRIPT_VERSION="1.0.0"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../../../../scripts/common/common.sh"

BASE_URL="" PROJECT_KEY="" REPO_SLUG="" BRANCH="" USER_NAME="" OPERATION_ID="" DRY_RUN=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --base-url) BASE_URL="$2"; shift 2 ;;
    --project-key) PROJECT_KEY="$2"; shift 2 ;;
    --repository-slug) REPO_SLUG="$2"; shift 2 ;;
    --branch) BRANCH="$2"; shift 2 ;;
    --user) USER_NAME="$2"; shift 2 ;;
    --operation-id) OPERATION_ID="$2"; shift 2 ;;
    --dry-run) DRY_RUN=true; shift ;;
    *) echo "Unknown argument: $1" >&2; exit "$EXIT_INVALID_PARAMETERS" ;;
  esac
done
[[ -z "$BASE_URL" || -z "$PROJECT_KEY" || -z "$REPO_SLUG" || -z "$BRANCH" || -z "$USER_NAME" || -z "$OPERATION_ID" ]] && { echo "Missing required arguments" >&2; exit "$EXIT_INVALID_PARAMETERS"; }

TARGET="$PROJECT_KEY/$REPO_SLUG"
OPERATION_KEY="bitbucket.repository.default_branch.update"

set +e
APPROVAL_OUTPUT="$(test_approval_token "$OPERATION_ID" "bitbucket" "$TARGET" "$OPERATION_KEY" "APPROVE ADMIN CHANGE")"
APPROVAL_STATUS=$?
set -e

if [[ $APPROVAL_STATUS -ne 0 ]]; then
  write_audit_log "$OPERATION_ID" "$USER_NAME" "bitbucket" "9.4.5" "repository" "UPDATE" "$TARGET" \
    "rest-api" "bitbucket-repository-admin" "set-default-branch.sh" "$SCRIPT_VERSION" \
    "ADMINISTRATIVE" true "DENIED" "DENIED" "NOT_APPLICABLE" "$APPROVAL_OUTPUT"
  echo "$APPROVAL_OUTPUT" >&2
  exit "$EXIT_APPROVAL_DENIED"
fi

if [[ "$DRY_RUN" == true ]]; then
  echo "(dry-run) Would set default branch of '$TARGET' to '$BRANCH'. No change made."
  exit "$EXIT_SUCCESS"
fi

URI="$BASE_URL/rest/api/1.0/projects/$PROJECT_KEY/repos/$REPO_SLUG/branches/default"
BRANCH_REF_ID="refs/heads/$BRANCH"
TOKEN="$(read_local_secret bitbucket)"
BODY="$(jq -nc --arg id "$BRANCH_REF_ID" '{id:$id}')"

if invoke_secure_rest PUT "$URI" "$TOKEN" "Bearer" "$BODY" >/dev/null; then
  set_approval_consumed "$OPERATION_ID"
  VERIFICATION="FAILED"; RESULT="UNKNOWN"
  if CURRENT="$(invoke_secure_rest GET "$URI" "$TOKEN")"; then
    CUR_ID="$(echo "$CURRENT" | jq -r '.id // empty')"
    CUR_DISPLAY="$(echo "$CURRENT" | jq -r '.displayId // empty')"
    if [[ "$CUR_ID" == "$BRANCH_REF_ID" || "$CUR_DISPLAY" == "$BRANCH" ]]; then
      VERIFICATION="CONFIRMED"; RESULT="SUCCESS"
    fi
  fi

  write_audit_log "$OPERATION_ID" "$USER_NAME" "bitbucket" "9.4.5" "repository" "UPDATE" "$TARGET" \
    "rest-api" "bitbucket-repository-admin" "set-default-branch.sh" "$SCRIPT_VERSION" \
    "ADMINISTRATIVE" true "APPROVED" "$RESULT" "$VERIFICATION" "null"

  jq -nc --arg o "$OPERATION_ID" --arg t "$TARGET" --arg r "$RESULT" --arg v "$VERIFICATION" \
    '{operationId:$o,target:$t,result:$r,verification:$v}'

  [[ "$VERIFICATION" != "CONFIRMED" ]] && exit "$EXIT_VERIFICATION_FAILURE"
  exit "$EXIT_SUCCESS"
else
  write_audit_log "$OPERATION_ID" "$USER_NAME" "bitbucket" "9.4.5" "repository" "UPDATE" "$TARGET" \
    "rest-api" "bitbucket-repository-admin" "set-default-branch.sh" "$SCRIPT_VERSION" \
    "ADMINISTRATIVE" true "APPROVED" "FAILURE" "UNKNOWN" "request failed"
  echo "ERROR: failed to set default branch for '$TARGET'" >&2
  exit "$EXIT_GENERAL_FAILURE"
fi
