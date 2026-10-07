#!/usr/bin/env bash
# create-repository.sh - ADMINISTRATIVE: Creates a new JFrog repository
# configuration. Requires a pre-issued "APPROVE ADMIN CHANGE" approval.
#
# Purpose: Execute the CREATE stage for a new repository configuration.
# Supported OS: Linux, macOS (Bash).
# Dependencies: scripts/common/common.sh
# Parameters: --base-url --repo-key --rclass --package-type --user --operation-id [--dry-run]
# Authentication: JFrog access token (POC: local-secrets).
# Required permissions: Artifactory admin permission.
# Approval requirements: MANDATORY "APPROVE ADMIN CHANGE".
# Dry-run: --dry-run supported.
# API/MCP dependency: REST fallback (PUT /artifactory/api/repositories/{repoKey}).
# Exit codes: 0 success, 6 approval denied, 7 verification failure, 1 general failure.
# Output: JSON result.
# Verification: GET after create; confirm rclass matches.
# Audit: writes one ADMINISTRATIVE audit record.
# Security: TLS enforced; approval re-checked immediately before PUT.
#
# Example:
#   ./create-repository.sh --base-url https://jfrog.example.com \
#     --repo-key libs-release-local --rclass local --package-type generic \
#     --user jdoe --operation-id op-123

set -euo pipefail
SCRIPT_VERSION="1.0.0"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../../../../scripts/common/common.sh"

BASE_URL="" REPO_KEY="" RCLASS="" PACKAGE_TYPE="" USER_NAME="" OPERATION_ID="" DRY_RUN=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --base-url) BASE_URL="$2"; shift 2 ;;
    --repo-key) REPO_KEY="$2"; shift 2 ;;
    --rclass) RCLASS="$2"; shift 2 ;;
    --package-type) PACKAGE_TYPE="$2"; shift 2 ;;
    --user) USER_NAME="$2"; shift 2 ;;
    --operation-id) OPERATION_ID="$2"; shift 2 ;;
    --dry-run) DRY_RUN=true; shift ;;
    *) echo "Unknown argument: $1" >&2; exit "$EXIT_INVALID_PARAMETERS" ;;
  esac
done
[[ -z "$BASE_URL" || -z "$REPO_KEY" || -z "$RCLASS" || -z "$PACKAGE_TYPE" || -z "$USER_NAME" || -z "$OPERATION_ID" ]] && { echo "Missing required arguments" >&2; exit "$EXIT_INVALID_PARAMETERS"; }
if ! [[ "$REPO_KEY" =~ ^[A-Za-z0-9._-]+$ ]]; then echo "ERROR: --repo-key contains invalid characters." >&2; exit "$EXIT_INVALID_PARAMETERS"; fi
case "$RCLASS" in local|remote|virtual|federated) ;; *) echo "ERROR: --rclass must be local|remote|virtual|federated" >&2; exit "$EXIT_INVALID_PARAMETERS" ;; esac

OPERATION_KEY="jfrog.repository.create"
set +e
APPROVAL_OUTPUT="$(test_approval_token "$OPERATION_ID" "jfrog" "$REPO_KEY" "$OPERATION_KEY" "APPROVE ADMIN CHANGE")"
APPROVAL_STATUS=$?
set -e

if [[ $APPROVAL_STATUS -ne 0 ]]; then
  write_audit_log "$OPERATION_ID" "$USER_NAME" "jfrog" "runtime-detected" "repository" "CREATE" "$REPO_KEY" \
    "rest-api" "jfrog-repositories" "create-repository.sh" "$SCRIPT_VERSION" \
    "ADMINISTRATIVE" true "DENIED" "DENIED" "NOT_APPLICABLE" "$APPROVAL_OUTPUT"
  echo "$APPROVAL_OUTPUT" >&2
  exit "$EXIT_APPROVAL_DENIED"
fi

if [[ "$DRY_RUN" == true ]]; then
  echo "(dry-run) Would CREATE JFrog repository '$REPO_KEY'. No change made."
  exit "$EXIT_SUCCESS"
fi

URI="$BASE_URL/artifactory/api/repositories/$REPO_KEY"
TOKEN="$(read_local_secret jfrog)"
BODY="$(jq -nc --arg key "$REPO_KEY" --arg rclass "$RCLASS" --arg pt "$PACKAGE_TYPE" '{key:$key,rclass:$rclass,packageType:$pt}')"

if invoke_secure_rest PUT "$URI" "$TOKEN" "Bearer" "$BODY" >/dev/null; then
  set_approval_consumed "$OPERATION_ID"
  VERIFICATION="FAILED"; RESULT="UNKNOWN"
  if CREATED="$(invoke_secure_rest GET "$URI" "$TOKEN")"; then
    CUR_RCLASS="$(echo "$CREATED" | jq -r '.rclass // empty')"
    if [[ "$CUR_RCLASS" == "$RCLASS" ]]; then VERIFICATION="CONFIRMED"; RESULT="SUCCESS"; fi
  fi

  write_audit_log "$OPERATION_ID" "$USER_NAME" "jfrog" "runtime-detected" "repository" "CREATE" "$REPO_KEY" \
    "rest-api" "jfrog-repositories" "create-repository.sh" "$SCRIPT_VERSION" \
    "ADMINISTRATIVE" true "APPROVED" "$RESULT" "$VERIFICATION" "null"

  jq -nc --arg o "$OPERATION_ID" --arg t "$REPO_KEY" --arg r "$RESULT" --arg v "$VERIFICATION" \
    '{operationId:$o,target:$t,result:$r,verification:$v}'

  [[ "$VERIFICATION" != "CONFIRMED" ]] && exit "$EXIT_VERIFICATION_FAILURE"
  exit "$EXIT_SUCCESS"
else
  write_audit_log "$OPERATION_ID" "$USER_NAME" "jfrog" "runtime-detected" "repository" "CREATE" "$REPO_KEY" \
    "rest-api" "jfrog-repositories" "create-repository.sh" "$SCRIPT_VERSION" \
    "ADMINISTRATIVE" true "APPROVED" "FAILURE" "UNKNOWN" "request failed"
  echo "ERROR: failed to create repository '$REPO_KEY'" >&2
  exit "$EXIT_GENERAL_FAILURE"
fi
