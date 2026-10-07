#!/usr/bin/env bash
# delete-artifacts.sh
#
# Purpose: DESTRUCTIVE -- deletes a batch of previously-proposed
#   candidate artifacts from one Artifactory repository. Requires a
#   single pre-issued "APPROVE DELETE" approval bound to this exact
#   repository, covering exactly the candidate set shown to the human
#   (Section 20 pipeline). The calling agent is the trust boundary for
#   "which paths were in the approved batch" -- repository-level
#   binding still prevents reusing an approval across repositories.
# Supported OS: Linux, macOS (Bash).
# Dependencies: scripts/common/common.sh (curl, jq, openssl)
# Parameters: --base-url --repository --candidate-path (repeatable) --user --operation-id
# Authentication: JFrog access token (POC: local-secrets).
# Required permissions: Delete permission on the target repository.
# Approval requirements: MANDATORY "APPROVE DELETE" bound to this exact Repository.
# Dry-run: --dry-run supported.
# API/MCP dependency: REST fallback -- DELETE /artifactory/{repo-key}/{item-path} (per path)
# Exit codes: 0 success, 6 approval denied, 7 verification failure, 1 general failure, 2 invalid parameters.
# Output: JSON result summary (per-path + overall).
# Verification: GET after each DELETE; expect HTTP 404 for every path.
# Audit: writes one DESTRUCTIVE audit record per deleted path.
# Security: TLS enforced; approval re-checked immediately before the batch executes.
#
# Example:
#   ./delete-artifacts.sh --base-url "https://jfrog.example.com" --repository releases-local \
#       --candidate-path "com/example/app/1.0/app.jar" --candidate-path "com/example/app/1.1/app.jar" \
#       --user jdoe --operation-id op-123

set -euo pipefail
SCRIPT_VERSION="1.0.0"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../../../../scripts/common/common.sh
source "$SCRIPT_DIR/../../../../../scripts/common/common.sh"

DRY_RUN=false
BASE_URL=""; REPOSITORY=""; USER_NAME=""; OPERATION_ID=""
CANDIDATE_PATHS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --base-url) BASE_URL="$2"; shift 2 ;;
    --repository) REPOSITORY="$2"; shift 2 ;;
    --candidate-path) CANDIDATE_PATHS+=("$2"); shift 2 ;;
    --user) USER_NAME="$2"; shift 2 ;;
    --operation-id) OPERATION_ID="$2"; shift 2 ;;
    --dry-run) DRY_RUN=true; shift ;;
    *) echo "Unknown argument: $1" >&2; exit "$EXIT_INVALID_PARAMETERS" ;;
  esac
done

for v in BASE_URL REPOSITORY USER_NAME OPERATION_ID; do
  [[ -n "${!v}" ]] || { echo "ERROR: missing required argument for $v." >&2; exit "$EXIT_INVALID_PARAMETERS"; }
done
[[ "$REPOSITORY" =~ ^[A-Za-z0-9_.-]+$ ]] || { echo "ERROR: invalid repository key." >&2; exit "$EXIT_INVALID_PARAMETERS"; }
[[ "${#CANDIDATE_PATHS[@]}" -gt 0 ]] || { echo "ERROR: at least one --candidate-path is required." >&2; exit "$EXIT_INVALID_PARAMETERS"; }
for p in "${CANDIDATE_PATHS[@]}"; do
  [[ "$p" != *".."* ]] || { echo "ERROR: path traversal detected in candidate path '$p'." >&2; exit "$EXIT_INVALID_PARAMETERS"; }
done

OPERATION_KEY="jfrog.artifact.delete"
VALIDATION=$(test_approval_token "$OPERATION_ID" "jfrog" "$REPOSITORY" "$OPERATION_KEY" "APPROVE DELETE") || true
if [[ "$VALIDATION" != "VALID" ]]; then
  write_audit_log "$OPERATION_ID" "$USER_NAME" "jfrog" "runtime-detected" "artifact" "DELETE" "$REPOSITORY" \
    "rest-api" "jfrog-cleanup" "delete-artifacts.sh" "$SCRIPT_VERSION" \
    "DESTRUCTIVE" "true" "DENIED" "DENIED" "NOT_APPLICABLE" "${VALIDATION#INVALID: }"
  echo "ERROR: Approval check failed: ${VALIDATION#INVALID: }" >&2
  exit "$EXIT_APPROVAL_DENIED"
fi

TOKEN="$(read_local_secret jfrog)"

if [[ "$DRY_RUN" == "true" ]]; then
  echo "(dry-run) Would DELETE ${#CANDIDATE_PATHS[@]} artifact(s) from repository '$REPOSITORY'. No change made."
  exit "$EXIT_SUCCESS"
fi

ALL_CONFIRMED=true
RESULTS_JSON="[]"

for path in "${CANDIDATE_PATHS[@]}"; do
  TARGET="$REPOSITORY/$path"
  URI="$BASE_URL/artifactory/$REPOSITORY/$path"
  VERIFICATION="UNKNOWN"; RESULT="UNKNOWN"; ERR_MSG="null"

  if invoke_secure_rest DELETE "$URI" "$TOKEN" "Bearer" "" >/dev/null 2>/tmp/jfrog_del_err.$$; then
    if invoke_secure_rest GET "$URI" "$TOKEN" "Bearer" "" >/dev/null 2>&1; then
      VERIFICATION="FAILED"
    else
      VERIFICATION="CONFIRMED"; RESULT="SUCCESS"
    fi
  else
    ERR_MSG="\"$(cat /tmp/jfrog_del_err.$$ 2>/dev/null || echo 'unknown error')\""
  fi
  rm -f /tmp/jfrog_del_err.$$ 2>/dev/null || true

  [[ "$VERIFICATION" == "CONFIRMED" ]] || ALL_CONFIRMED=false

  write_audit_log "$OPERATION_ID" "$USER_NAME" "jfrog" "runtime-detected" "artifact" "DELETE" "$TARGET" \
    "rest-api" "jfrog-cleanup" "delete-artifacts.sh" "$SCRIPT_VERSION" \
    "DESTRUCTIVE" "true" "APPROVED" "$RESULT" "$VERIFICATION" "$ERR_MSG"

  RESULTS_JSON=$(echo "$RESULTS_JSON" | jq --arg target "$TARGET" --arg result "$RESULT" --arg verification "$VERIFICATION" \
    '. + [{target:$target, result:$result, verification:$verification}]')
done

set_approval_consumed "$OPERATION_ID"

OVERALL="UNKNOWN"
[[ "$ALL_CONFIRMED" == "true" ]] && OVERALL="SUCCESS"

jq -n --arg repository "$REPOSITORY" --argjson count "${#CANDIDATE_PATHS[@]}" --argjson results "$RESULTS_JSON" --arg overallResult "$OVERALL" \
  '{repository:$repository, count:$count, results:$results, overallResult:$overallResult}'

[[ "$ALL_CONFIRMED" == "true" ]] || exit "$EXIT_VERIFICATION_FAILURE"
exit "$EXIT_SUCCESS"
