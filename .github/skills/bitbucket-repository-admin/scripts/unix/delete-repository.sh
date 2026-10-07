#!/usr/bin/env bash
# delete-repository.sh
#
# Purpose: DESTRUCTIVE -- permanently deletes a Bitbucket Data Center
#   9.4.5 repository via the REST API fallback. Requires a pre-issued,
#   matching "APPROVE DELETE" approval record.
# Supported OS: Linux, macOS (Bash).
# Dependencies: scripts/common/common.sh (curl, jq, openssl)
# Parameters: --base-url --project-key --repository-slug --user --operation-id
# Authentication: Bitbucket HTTP access token (POC: local-secrets).
# Required permissions: Repository admin (or project admin).
# Approval requirements: MANDATORY "APPROVE DELETE" bound to this exact
#   ProjectKey/RepositorySlug.
# Dry-run: --dry-run supported.
# API/MCP dependency: REST fallback --
#   DELETE /rest/api/1.0/projects/{projectKey}/repos/{repositorySlug}
# Exit codes: 0 success, 6 approval denied, 7 verification failure,
#   1 general failure, 2 invalid parameters.
# Output: JSON result.
# Verification: GET after DELETE; expect HTTP 404.
# Audit: writes one DESTRUCTIVE audit record.
# Security: TLS enforced; approval re-checked immediately before DELETE.
#
# Example:
#   ./delete-repository.sh --base-url "https://bitbucket.example.internal" \
#       --project-key PROJ --repository-slug test --user jdoe --operation-id op-123

set -euo pipefail
SCRIPT_VERSION="1.0.0"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../../../../scripts/common/common.sh
source "$SCRIPT_DIR/../../../../../scripts/common/common.sh"

DRY_RUN=false
BASE_URL=""; PROJECT_KEY=""; REPOSITORY_SLUG=""; USER_NAME=""; OPERATION_ID=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --base-url) BASE_URL="$2"; shift 2 ;;
    --project-key) PROJECT_KEY="$2"; shift 2 ;;
    --repository-slug) REPOSITORY_SLUG="$2"; shift 2 ;;
    --user) USER_NAME="$2"; shift 2 ;;
    --operation-id) OPERATION_ID="$2"; shift 2 ;;
    --dry-run) DRY_RUN=true; shift ;;
    *) echo "Unknown argument: $1" >&2; exit "$EXIT_INVALID_PARAMETERS" ;;
  esac
done

for v in BASE_URL PROJECT_KEY REPOSITORY_SLUG USER_NAME OPERATION_ID; do
  [[ -n "${!v}" ]] || { echo "ERROR: missing required argument for $v." >&2; exit "$EXIT_INVALID_PARAMETERS"; }
done
[[ "$PROJECT_KEY" =~ ^[A-Za-z0-9_.-]+$ ]] || { echo "ERROR: invalid project key." >&2; exit "$EXIT_INVALID_PARAMETERS"; }
[[ "$REPOSITORY_SLUG" =~ ^[A-Za-z0-9_.-]+$ ]] || { echo "ERROR: invalid repository slug." >&2; exit "$EXIT_INVALID_PARAMETERS"; }

TARGET="$PROJECT_KEY/$REPOSITORY_SLUG"
OPERATION_KEY="bitbucket.repository.delete"

VALIDATION=$(test_approval_token "$OPERATION_ID" "bitbucket" "$TARGET" "$OPERATION_KEY" "APPROVE DELETE") || true
if [[ "$VALIDATION" != "VALID" ]]; then
  write_audit_log "$OPERATION_ID" "$USER_NAME" "bitbucket" "9.4.5" "repository" "DELETE" "$TARGET" \
    "rest-api" "bitbucket-repository-admin" "delete-repository.sh" "$SCRIPT_VERSION" \
    "DESTRUCTIVE" "true" "DENIED" "DENIED" "NOT_APPLICABLE" "${VALIDATION#INVALID: }"
  echo "ERROR: Approval check failed: ${VALIDATION#INVALID: }" >&2
  exit "$EXIT_APPROVAL_DENIED"
fi

TOKEN="$(read_local_secret bitbucket)"
URI="$BASE_URL/rest/api/1.0/projects/$PROJECT_KEY/repos/$REPOSITORY_SLUG"

if [[ "$DRY_RUN" == "true" ]]; then
  echo "(dry-run) Would DELETE Bitbucket repository '$TARGET'. No change made."
  exit "$EXIT_SUCCESS"
fi

if ! invoke_secure_rest DELETE "$URI" "$TOKEN" "Bearer" "" >/dev/null 2>/tmp/bb_del_err.$$; then
  ERR_MSG="$(cat /tmp/bb_del_err.$$ 2>/dev/null || echo 'unknown error')"
  rm -f /tmp/bb_del_err.$$
  write_audit_log "$OPERATION_ID" "$USER_NAME" "bitbucket" "9.4.5" "repository" "DELETE" "$TARGET" \
    "rest-api" "bitbucket-repository-admin" "delete-repository.sh" "$SCRIPT_VERSION" \
    "DESTRUCTIVE" "true" "APPROVED" "FAILURE" "UNKNOWN" "$ERR_MSG"
  echo "ERROR: Failed to delete repository '$TARGET': $ERR_MSG" >&2
  exit "$EXIT_GENERAL_FAILURE"
fi
rm -f /tmp/bb_del_err.$$ 2>/dev/null || true

set_approval_consumed "$OPERATION_ID"

VERIFICATION="UNKNOWN"; RESULT="UNKNOWN"
if invoke_secure_rest GET "$URI" "$TOKEN" "Bearer" "" >/dev/null 2>&1; then
  VERIFICATION="FAILED"
else
  VERIFICATION="CONFIRMED"; RESULT="SUCCESS"
fi

write_audit_log "$OPERATION_ID" "$USER_NAME" "bitbucket" "9.4.5" "repository" "DELETE" "$TARGET" \
  "rest-api" "bitbucket-repository-admin" "delete-repository.sh" "$SCRIPT_VERSION" \
  "DESTRUCTIVE" "true" "APPROVED" "$RESULT" "$VERIFICATION" "null"

jq -n --arg operationId "$OPERATION_ID" --arg target "$TARGET" --arg result "$RESULT" --arg verification "$VERIFICATION" \
  '{operationId:$operationId, target:$target, result:$result, verification:$verification}'

[[ "$VERIFICATION" == "CONFIRMED" ]] || exit "$EXIT_VERIFICATION_FAILURE"
exit "$EXIT_SUCCESS"
