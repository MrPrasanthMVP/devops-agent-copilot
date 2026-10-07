#!/usr/bin/env bash
# update-branch-protection.sh - ADMINISTRATIVE: Updates branch protection
# settings. Requires a pre-issued "APPROVE BRANCH PROTECTION" approval.
#
# Purpose: Execute the UPDATE stage for branch protection.
# Supported OS: Linux, macOS (Bash).
# Dependencies: scripts/common/common.sh
# Parameters: --api-base-url --owner --repo --branch
#   --required-approving-review-count --enforce-admins --user
#   --operation-id [--dry-run]
# Authentication: GitHub token (POC: local-secrets).
# Required permissions: repository admin permission.
# Approval requirements: MANDATORY "APPROVE BRANCH PROTECTION".
# Dry-run: --dry-run supported.
# API/MCP dependency: REST fallback
#   (PUT /repos/{owner}/{repo}/branches/{branch}/protection).
# Exit codes: 0 success, 6 approval denied, 7 verification failure, 1 general failure.
# Output: JSON result.
# Verification: GET after PUT; compare required_approving_review_count
#   and enforce_admins.enabled against proposed values.
# Audit: writes one ADMINISTRATIVE audit record.
# Security: TLS enforced; approval re-checked immediately before PUT.
#
# Example:
#   ./update-branch-protection.sh --api-base-url https://api.github.com \
#     --owner myorg --repo myrepo --branch main \
#     --required-approving-review-count 2 --enforce-admins true \
#     --user jdoe --operation-id op-123

set -euo pipefail
SCRIPT_VERSION="1.0.0"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../../../../scripts/common/common.sh"

API_BASE_URL="" OWNER="" REPO="" BRANCH="" REVIEW_COUNT="" ENFORCE_ADMINS="" USER_NAME="" OPERATION_ID="" DRY_RUN=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --api-base-url) API_BASE_URL="$2"; shift 2 ;;
    --owner) OWNER="$2"; shift 2 ;;
    --repo) REPO="$2"; shift 2 ;;
    --branch) BRANCH="$2"; shift 2 ;;
    --required-approving-review-count) REVIEW_COUNT="$2"; shift 2 ;;
    --enforce-admins) ENFORCE_ADMINS="$2"; shift 2 ;;
    --user) USER_NAME="$2"; shift 2 ;;
    --operation-id) OPERATION_ID="$2"; shift 2 ;;
    --dry-run) DRY_RUN=true; shift ;;
    *) echo "Unknown argument: $1" >&2; exit "$EXIT_INVALID_PARAMETERS" ;;
  esac
done
[[ -z "$API_BASE_URL" || -z "$OWNER" || -z "$REPO" || -z "$BRANCH" || -z "$REVIEW_COUNT" || -z "$ENFORCE_ADMINS" || -z "$USER_NAME" || -z "$OPERATION_ID" ]] && { echo "Missing required arguments" >&2; exit "$EXIT_INVALID_PARAMETERS"; }

TARGET="$OWNER/$REPO@$BRANCH"
OPERATION_KEY="github.branch_protection.update"

set +e
APPROVAL_OUTPUT="$(test_approval_token "$OPERATION_ID" "github" "$TARGET" "$OPERATION_KEY" "APPROVE BRANCH PROTECTION")"
APPROVAL_STATUS=$?
set -e

if [[ $APPROVAL_STATUS -ne 0 ]]; then
  write_audit_log "$OPERATION_ID" "$USER_NAME" "github" "runtime-detected" "branch_protection" "UPDATE" "$TARGET" \
    "rest-api" "github-branch-protection" "update-branch-protection.sh" "$SCRIPT_VERSION" \
    "ADMINISTRATIVE" true "DENIED" "DENIED" "NOT_APPLICABLE" "$APPROVAL_OUTPUT"
  echo "$APPROVAL_OUTPUT" >&2
  exit "$EXIT_APPROVAL_DENIED"
fi

if [[ "$DRY_RUN" == true ]]; then
  echo "(dry-run) Would UPDATE branch protection for '$TARGET'. No change made."
  exit "$EXIT_SUCCESS"
fi

URI="$API_BASE_URL/repos/$OWNER/$REPO/branches/$BRANCH/protection"
TOKEN="$(read_local_secret github)"
BODY="$(jq -nc --argjson count "$REVIEW_COUNT" --argjson enforce "$ENFORCE_ADMINS" \
  '{required_status_checks: null, enforce_admins: $enforce, required_pull_request_reviews: {required_approving_review_count: $count}, restrictions: null}')"

if invoke_secure_rest PUT "$URI" "$TOKEN" "Bearer" "$BODY" >/dev/null; then
  set_approval_consumed "$OPERATION_ID"
  VERIFICATION="FAILED"; RESULT="UNKNOWN"
  if CURRENT="$(invoke_secure_rest GET "$URI" "$TOKEN")"; then
    CUR_COUNT="$(echo "$CURRENT" | jq -r '.required_pull_request_reviews.required_approving_review_count // empty')"
    CUR_ENFORCE="$(echo "$CURRENT" | jq -r '.enforce_admins.enabled // empty')"
    if [[ "$CUR_COUNT" == "$REVIEW_COUNT" && "$CUR_ENFORCE" == "$ENFORCE_ADMINS" ]]; then
      VERIFICATION="CONFIRMED"; RESULT="SUCCESS"
    fi
  fi

  write_audit_log "$OPERATION_ID" "$USER_NAME" "github" "runtime-detected" "branch_protection" "UPDATE" "$TARGET" \
    "rest-api" "github-branch-protection" "update-branch-protection.sh" "$SCRIPT_VERSION" \
    "ADMINISTRATIVE" true "APPROVED" "$RESULT" "$VERIFICATION" "null"

  jq -nc --arg o "$OPERATION_ID" --arg t "$TARGET" --arg r "$RESULT" --arg v "$VERIFICATION" \
    '{operationId:$o,target:$t,result:$r,verification:$v}'

  [[ "$VERIFICATION" != "CONFIRMED" ]] && exit "$EXIT_VERIFICATION_FAILURE"
  exit "$EXIT_SUCCESS"
else
  write_audit_log "$OPERATION_ID" "$USER_NAME" "github" "runtime-detected" "branch_protection" "UPDATE" "$TARGET" \
    "rest-api" "github-branch-protection" "update-branch-protection.sh" "$SCRIPT_VERSION" \
    "ADMINISTRATIVE" true "APPROVED" "FAILURE" "UNKNOWN" "request failed"
  echo "ERROR: failed to update branch protection for '$TARGET'" >&2
  exit "$EXIT_GENERAL_FAILURE"
fi
