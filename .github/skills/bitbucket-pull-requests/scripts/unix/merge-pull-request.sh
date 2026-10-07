#!/usr/bin/env bash
# merge-pull-request.sh
#
# Purpose: WRITE -- merges a Bitbucket Data Center 9.4.5 pull request
#   via the REST API fallback. Requires a pre-issued, matching
#   "APPROVE MERGE" approval record. Never attempts to bypass
#   server-side merge checks.
# Supported OS: Linux, macOS (Bash).
# Dependencies: scripts/common/common.sh (curl, jq, openssl)
# Parameters: --base-url --project-key --repository-slug
#   --pull-request-id --version --user --operation-id
# Authentication: Bitbucket HTTP access token (POC: local-secrets).
# Required permissions: Repository write permission.
# Approval requirements: MANDATORY "APPROVE MERGE" bound to this exact PR.
# Dry-run: --dry-run supported.
# API/MCP dependency: REST fallback --
#   POST /rest/api/1.0/projects/{projectKey}/repos/{repositorySlug}/pull-requests/{id}/merge?version={version}
# Exit codes: 0 success, 6 approval denied, 7 verification failure,
#   9 merge checks not satisfied, 1 general failure, 2 invalid parameters.
# Output: JSON result.
# Verification: GET PR after merge; expect state == MERGED.
# Audit: writes one WRITE audit record.
# Security: TLS enforced; PR text treated as untrusted data.
#
# Example:
#   ./merge-pull-request.sh --base-url "https://bitbucket.example.internal" \
#       --project-key PROJ --repository-slug app --pull-request-id 42 \
#       --version 3 --user jdoe --operation-id op-123

set -euo pipefail
SCRIPT_VERSION="1.0.0"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../../../../scripts/common/common.sh
source "$SCRIPT_DIR/../../../../../scripts/common/common.sh"

BASE_URL=""; PROJECT_KEY=""; REPOSITORY_SLUG=""; PR_ID=""; PR_VERSION=""; USER_NAME=""; OPERATION_ID=""
DRY_RUN=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --base-url) BASE_URL="$2"; shift 2 ;;
    --project-key) PROJECT_KEY="$2"; shift 2 ;;
    --repository-slug) REPOSITORY_SLUG="$2"; shift 2 ;;
    --pull-request-id) PR_ID="$2"; shift 2 ;;
    --version) PR_VERSION="$2"; shift 2 ;;
    --user) USER_NAME="$2"; shift 2 ;;
    --operation-id) OPERATION_ID="$2"; shift 2 ;;
    --dry-run) DRY_RUN=true; shift ;;
    *) echo "Unknown argument: $1" >&2; exit "$EXIT_INVALID_PARAMETERS" ;;
  esac
done

for v in BASE_URL PROJECT_KEY REPOSITORY_SLUG PR_ID PR_VERSION USER_NAME OPERATION_ID; do
  [[ -n "${!v}" ]] || { echo "ERROR: missing required argument for $v." >&2; exit "$EXIT_INVALID_PARAMETERS"; }
done

TARGET="$PROJECT_KEY/$REPOSITORY_SLUG/pull-requests/$PR_ID"
OPERATION_KEY="bitbucket.pull_request.merge"

VALIDATION=$(test_approval_token "$OPERATION_ID" "bitbucket" "$TARGET" "$OPERATION_KEY" "APPROVE MERGE") || true
if [[ "$VALIDATION" != "VALID" ]]; then
  write_audit_log "$OPERATION_ID" "$USER_NAME" "bitbucket" "9.4.5" "pull_request" "MERGE" "$TARGET" \
    "rest-api" "bitbucket-pull-requests" "merge-pull-request.sh" "$SCRIPT_VERSION" \
    "WRITE" "true" "DENIED" "DENIED" "NOT_APPLICABLE" "${VALIDATION#INVALID: }"
  echo "ERROR: Approval check failed: ${VALIDATION#INVALID: }" >&2
  exit "$EXIT_APPROVAL_DENIED"
fi

TOKEN="$(read_local_secret bitbucket)"
PR_URI="$BASE_URL/rest/api/1.0/projects/$PROJECT_KEY/repos/$REPOSITORY_SLUG/pull-requests/$PR_ID"

if [[ "$DRY_RUN" == "true" ]]; then
  echo "(dry-run) Would MERGE pull request '$TARGET'. No change made."
  exit "$EXIT_SUCCESS"
fi

if ! invoke_secure_rest POST "$PR_URI/merge?version=$PR_VERSION" "$TOKEN" "Bearer" "" >/dev/null 2>/tmp/bb_merge_err.$$; then
  ERR_MSG="$(cat /tmp/bb_merge_err.$$ 2>/dev/null || echo 'unknown error')"
  rm -f /tmp/bb_merge_err.$$
  write_audit_log "$OPERATION_ID" "$USER_NAME" "bitbucket" "9.4.5" "pull_request" "MERGE" "$TARGET" \
    "rest-api" "bitbucket-pull-requests" "merge-pull-request.sh" "$SCRIPT_VERSION" \
    "WRITE" "true" "APPROVED" "FAILURE" "NOT_APPLICABLE" "$ERR_MSG"
  echo "ERROR: Merge checks not satisfied, version conflict, or request failed: $ERR_MSG" >&2
  exit "$EXIT_UNSUPPORTED_OPERATION"
fi
rm -f /tmp/bb_merge_err.$$ 2>/dev/null || true

set_approval_consumed "$OPERATION_ID"

PR_JSON=$(invoke_secure_rest GET "$PR_URI" "$TOKEN" "Bearer" "" 2>/dev/null || echo '{}')
STATE=$(echo "$PR_JSON" | jq -r '.state // "UNKNOWN"')

VERIFICATION="FAILED"; RESULT="UNKNOWN"
if [[ "$STATE" == "MERGED" ]]; then VERIFICATION="CONFIRMED"; RESULT="SUCCESS"; fi

write_audit_log "$OPERATION_ID" "$USER_NAME" "bitbucket" "9.4.5" "pull_request" "MERGE" "$TARGET" \
  "rest-api" "bitbucket-pull-requests" "merge-pull-request.sh" "$SCRIPT_VERSION" \
  "WRITE" "true" "APPROVED" "$RESULT" "$VERIFICATION" "null"

jq -n --arg target "$TARGET" --arg result "$RESULT" --arg verification "$VERIFICATION" \
  '{target:$target, result:$result, verification:$verification}'

[[ "$VERIFICATION" == "CONFIRMED" ]] || exit "$EXIT_VERIFICATION_FAILURE"
exit "$EXIT_SUCCESS"
