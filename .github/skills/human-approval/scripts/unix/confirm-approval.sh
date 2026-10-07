#!/usr/bin/env bash
# confirm-approval.sh
#
# Purpose: Validates the human's literal response against the staged
#   proposal's expected approval phrase, and, if it matches exactly,
#   mints the canonical HMAC-signed approval token via common.sh's
#   new_approval_token.
# Supported OS: Linux, macOS (Bash).
# Dependencies: scripts/common/common.sh (curl, jq, openssl)
# Exit codes: 0 approved, 1 general failure, 2 invalid parameters,
#   6 approval denied / phrase did not match, 7 proposal expired,
#   8 operationId not found.
# Output: JSON object describing the outcome.
# Audit: appends a CONFIRM_APPROVAL audit record.
# Security: Rejects generic affirmations as insufficient.
#
# Example:
#   ./confirm-approval.sh --operation-id "op-xxxx" --approval-phrase-received "APPROVE DELETE" --approved-by "jdoe"

set -euo pipefail
SCRIPT_VERSION="1.0.0"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../../../../scripts/common/common.sh
source "$SCRIPT_DIR/../../../../../scripts/common/common.sh"

APPROVED_BY="${USER:-unknown}"
OPERATION_ID=""; PHRASE_RECEIVED=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --operation-id) OPERATION_ID="$2"; shift 2 ;;
    --approval-phrase-received) PHRASE_RECEIVED="$2"; shift 2 ;;
    --approved-by) APPROVED_BY="$2"; shift 2 ;;
    *) echo "Unknown argument: $1" >&2; exit "$EXIT_INVALID_PARAMETERS" ;;
  esac
done

[[ -n "$OPERATION_ID" && -n "$PHRASE_RECEIVED" ]] || { echo "ERROR: --operation-id and --approval-phrase-received are required." >&2; exit "$EXIT_INVALID_PARAMETERS"; }

ROOT="$(repo_root)"
PROPOSAL_FILE="$ROOT/.proposals/$OPERATION_ID.json"
[[ -f "$PROPOSAL_FILE" ]] || { echo "ERROR: Unknown or already-confirmed operationId: $OPERATION_ID" >&2; exit "$EXIT_TARGET_NOT_FOUND"; }

REQUESTED_AT=$(jq -r '.requestedAt' "$PROPOSAL_FILE")
EXPIRES_AFTER=$(jq -r '.expiresAfterSeconds' "$PROPOSAL_FILE")
EXPECTED_PHRASE=$(jq -r '.approvalType' "$PROPOSAL_FILE")
SYSTEM=$(jq -r '.system' "$PROPOSAL_FILE")
TARGET=$(jq -r '.target' "$PROPOSAL_FILE")
OPERATION_KEY=$(jq -r '.operationKey' "$PROPOSAL_FILE")
RISK=$(jq -r '.risk' "$PROPOSAL_FILE")

REQUESTED_EPOCH=$(date -u -d "$REQUESTED_AT" +%s 2>/dev/null || date -u -j -f "%Y-%m-%dT%H:%M:%SZ" "$REQUESTED_AT" +%s)
NOW_EPOCH=$(date -u +%s)
AGE=$(( NOW_EPOCH - REQUESTED_EPOCH ))

if (( AGE > EXPIRES_AFTER )); then
  rm -f "$PROPOSAL_FILE"
  echo "ERROR: Proposal $OPERATION_ID has EXPIRED (${AGE}s old, limit ${EXPIRES_AFTER}s). Re-propose the operation." >&2
  exit "$EXIT_VERIFICATION_FAILURE"
fi

NORMALIZED_RECEIVED="$(echo "$PHRASE_RECEIVED" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
LOWER_RECEIVED="$(echo "$NORMALIZED_RECEIVED" | tr '[:upper:]' '[:lower:]')"

STATUS="DENIED"
if [[ "$NORMALIZED_RECEIVED" == "$EXPECTED_PHRASE" ]]; then
  STATUS="APPROVED"
else
  case "$LOWER_RECEIVED" in
    yes|ok|okay|sure|"do it"|"go ahead"|proceed|fine|confirm|approved)
      echo "WARNING: Generic affirmation '$NORMALIZED_RECEIVED' is not sufficient. Exact phrase required: '$EXPECTED_PHRASE'" >&2
      ;;
  esac
fi

if [[ "$STATUS" == "APPROVED" ]]; then
  TOKEN=$(new_approval_token "$OPERATION_ID" "$APPROVED_BY" "$SYSTEM" "$TARGET" "$OPERATION_KEY" "$RISK" "$EXPECTED_PHRASE")
  rm -f "$PROPOSAL_FILE"

  write_audit_log "$OPERATION_ID" "$APPROVED_BY" "$SYSTEM" "n/a" "proposal" "CONFIRM_APPROVAL" "$TARGET" \
    "none" "human-approval" "scripts/unix/confirm-approval.sh" "$SCRIPT_VERSION" \
    "$RISK" "true" "APPROVED" "SUCCESS" "NOT_APPLICABLE" "null"

  echo "$TOKEN"
  exit "$EXIT_SUCCESS"
else
  write_audit_log "$OPERATION_ID" "$APPROVED_BY" "$SYSTEM" "n/a" "proposal" "CONFIRM_APPROVAL" "$TARGET" \
    "none" "human-approval" "scripts/unix/confirm-approval.sh" "$SCRIPT_VERSION" \
    "$RISK" "true" "DENIED" "DENIED" "NOT_APPLICABLE" "null"

  jq -n --arg operationId "$OPERATION_ID" --arg received "$NORMALIZED_RECEIVED" --arg expected "$EXPECTED_PHRASE" \
    '{operationId:$operationId, status:"DENIED", receivedPhrase:$received, expectedPhrase:$expected}'
  exit "$EXIT_APPROVAL_DENIED"
fi
