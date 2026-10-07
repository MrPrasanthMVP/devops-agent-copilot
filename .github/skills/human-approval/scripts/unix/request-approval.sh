#!/usr/bin/env bash
# request-approval.sh
#
# Purpose: Prints the PROPOSED OPERATION block and stages a PENDING
#   proposal (NOT yet a valid approval token) so that confirm-approval.sh
#   can later mint the canonical HMAC-signed approval token via
#   common.sh's new_approval_token once the human types the exact
#   required phrase.
# Supported OS: Linux, macOS (Bash).
# Dependencies: scripts/common/common.sh (curl, jq, openssl)
# Authentication: None (local bookkeeping only).
# Exit codes: 0 success, 1 general failure, 2 invalid parameters.
# Output: JSON: {operationId, approvalType, expiresAfterSeconds}
# Audit: appends a REQUEST_APPROVAL audit record.
# Security: No credentials handled. No network calls.
#
# Example:
#   ./request-approval.sh --system bitbucket --target "PROJ/TEST" \
#       --operation-key "bitbucket.repository.delete" --risk DESTRUCTIVE \
#       --approval-type "APPROVE DELETE" --current-state "exists, 42 commits" \
#       --proposed-state "permanently deleted" --impact "Permanent repository deletion." \
#       --requested-by "jdoe"

set -euo pipefail
SCRIPT_VERSION="1.0.0"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../../../../scripts/common/common.sh
source "$SCRIPT_DIR/../../../../../scripts/common/common.sh"

EXPIRES_AFTER_SECONDS=900
REQUESTED_BY="${USER:-unknown}"
SYSTEM=""; TARGET=""; OPERATION_KEY=""; RISK=""; APPROVAL_TYPE=""
CURRENT_STATE=""; PROPOSED_STATE=""; IMPACT=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --system) SYSTEM="$2"; shift 2 ;;
    --target) TARGET="$2"; shift 2 ;;
    --operation-key) OPERATION_KEY="$2"; shift 2 ;;
    --risk) RISK="$2"; shift 2 ;;
    --approval-type) APPROVAL_TYPE="$2"; shift 2 ;;
    --current-state) CURRENT_STATE="$2"; shift 2 ;;
    --proposed-state) PROPOSED_STATE="$2"; shift 2 ;;
    --impact) IMPACT="$2"; shift 2 ;;
    --requested-by) REQUESTED_BY="$2"; shift 2 ;;
    --expires-after-seconds) EXPIRES_AFTER_SECONDS="$2"; shift 2 ;;
    *) echo "Unknown argument: $1" >&2; exit "$EXIT_INVALID_PARAMETERS" ;;
  esac
done

case "$SYSTEM" in
  bitbucket|jira|confluence|jfrog|github) ;;
  *) echo "ERROR: --system must be one of bitbucket|jira|confluence|jfrog|github" >&2; exit "$EXIT_INVALID_PARAMETERS" ;;
esac
for v in TARGET OPERATION_KEY RISK APPROVAL_TYPE CURRENT_STATE PROPOSED_STATE IMPACT; do
  [[ -n "${!v}" ]] || { echo "ERROR: missing required argument for $v." >&2; exit "$EXIT_INVALID_PARAMETERS"; }
done

ROOT="$(repo_root)"
PROPOSALS_DIR="$ROOT/.proposals"
mkdir -p "$PROPOSALS_DIR"

OPERATION_ID="$(new_operation_id)"
TIMESTAMP="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

echo
echo "PROPOSED OPERATION"
echo
echo "System:          $SYSTEM"
echo "Target:          $TARGET"
echo "Operation:       $OPERATION_KEY"
echo "Current state:   $CURRENT_STATE"
echo "Proposed state:  $PROPOSED_STATE"
echo "Risk:            $RISK"
echo "Impact:          $IMPACT"
echo
echo "Explicit approval required. Type: $APPROVAL_TYPE"
echo "(operationId: $OPERATION_ID, expires in ${EXPIRES_AFTER_SECONDS}s)"
echo

jq -n \
  --arg operationId "$OPERATION_ID" --arg user "$REQUESTED_BY" --arg system "$SYSTEM" \
  --arg target "$TARGET" --arg operationKey "$OPERATION_KEY" --arg risk "$RISK" \
  --arg approvalType "$APPROVAL_TYPE" --arg currentState "$CURRENT_STATE" --arg proposedState "$PROPOSED_STATE" \
  --arg impact "$IMPACT" --arg requestedAt "$TIMESTAMP" --argjson expiresAfterSeconds "$EXPIRES_AFTER_SECONDS" \
  '{operationId:$operationId, user:$user, system:$system, target:$target, operationKey:$operationKey,
    risk:$risk, approvalType:$approvalType, currentState:$currentState, proposedState:$proposedState,
    impact:$impact, requestedAt:$requestedAt, expiresAfterSeconds:$expiresAfterSeconds}' \
  > "$PROPOSALS_DIR/$OPERATION_ID.json"

write_audit_log "$OPERATION_ID" "$REQUESTED_BY" "$SYSTEM" "n/a" "proposal" "REQUEST_APPROVAL" "$TARGET" \
  "none" "human-approval" "scripts/unix/request-approval.sh" "$SCRIPT_VERSION" \
  "$RISK" "true" "PENDING" "SUCCESS" "NOT_APPLICABLE" "null"

jq -n --arg operationId "$OPERATION_ID" --arg approvalType "$APPROVAL_TYPE" --argjson expiresAfterSeconds "$EXPIRES_AFTER_SECONDS" \
  '{operationId:$operationId, approvalType:$approvalType, expiresAfterSeconds:$expiresAfterSeconds}'

exit "$EXIT_SUCCESS"
