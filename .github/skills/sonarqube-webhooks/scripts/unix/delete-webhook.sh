#!/usr/bin/env bash
# delete-webhook.sh - DESTRUCTIVE: Permanently deletes a SonarQube
# webhook. Requires a pre-issued, matching "APPROVE DELETE" approval record.
#
# Purpose: Execute the DELETE stage for a webhook.
# Supported OS: Linux, macOS (Bash).
# Dependencies: scripts/common/common.sh
# Parameters: --base-url --webhook-key [--project-key] [--organization]
#   --user --operation-id [--dry-run]
# Authentication: SonarQube user token (POC: local-secrets).
# Required permissions: 'Administer System' (global) or 'Administer' on
#   the project (project-scoped).
# Approval requirements: MANDATORY "APPROVE DELETE".
# Dry-run: --dry-run prints the proposed action and exits without mutating.
# Deployment: works against BOTH Server and Cloud (pass --organization for Cloud).
# API/MCP dependency: REST fallback only (POST api/webhooks/delete) -- no
#   MCP delete-webhook tool exists in the verified catalog (see SKILL.md).
# Exit codes: 0 success, 6 approval denied, 7 verification failure, 1 general failure.
# Output: JSON result.
# Verification: list-after-delete; confirm the webhook key is absent.
# Audit: writes one DESTRUCTIVE audit record.
# Security: TLS enforced; approval re-checked immediately before POST.
#
# Example:
#   ./delete-webhook.sh --base-url https://sonarqube.example.internal \
#     --webhook-key AbCd1234 --user jdoe --operation-id op-aaa111

set -euo pipefail
SCRIPT_VERSION="1.0.0"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../../../../scripts/common/common.sh"

BASE_URL="" WEBHOOK_KEY="" PROJECT_KEY="" ORGANIZATION="" USER_NAME="" OPERATION_ID="" DRY_RUN=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --base-url) BASE_URL="$2"; shift 2 ;;
    --webhook-key) WEBHOOK_KEY="$2"; shift 2 ;;
    --project-key) PROJECT_KEY="$2"; shift 2 ;;
    --organization) ORGANIZATION="$2"; shift 2 ;;
    --user) USER_NAME="$2"; shift 2 ;;
    --operation-id) OPERATION_ID="$2"; shift 2 ;;
    --dry-run) DRY_RUN=true; shift ;;
    *) echo "Unknown argument: $1" >&2; exit "$EXIT_INVALID_PARAMETERS" ;;
  esac
done
[[ -z "$BASE_URL" || -z "$WEBHOOK_KEY" || -z "$USER_NAME" || -z "$OPERATION_ID" ]] && { echo "Missing required arguments" >&2; exit "$EXIT_INVALID_PARAMETERS"; }

TARGET="$WEBHOOK_KEY"
OPERATION_KEY="sonarqube.webhook.delete"

set +e
APPROVAL_OUTPUT="$(test_approval_token "$OPERATION_ID" "sonarqube" "$TARGET" "$OPERATION_KEY" "APPROVE DELETE")"
set -e
if [[ "$APPROVAL_OUTPUT" != "VALID" ]]; then
  write_audit_log "$OPERATION_ID" "$USER_NAME" "sonarqube" "runtime-detected" "webhook" "DELETE" "$TARGET" \
    "rest-api" "sonarqube-webhooks" "delete-webhook.sh" "$SCRIPT_VERSION" \
    "DESTRUCTIVE" true "DENIED" "DENIED" "NOT_APPLICABLE" "${APPROVAL_OUTPUT#INVALID: }"
  echo "ERROR: Approval check failed: ${APPROVAL_OUTPUT#INVALID: }" >&2
  exit "$EXIT_APPROVAL_DENIED"
fi

if [[ "$DRY_RUN" == true ]]; then
  echo "(dry-run) Would DELETE SonarQube webhook '$TARGET'. No change made."
  exit "$EXIT_SUCCESS"
fi

DELETE_URI="$BASE_URL/api/webhooks/delete"
LIST_URI="$BASE_URL/api/webhooks/list"
LIST_QS=""
[[ -n "$PROJECT_KEY" ]] && LIST_QS="${LIST_QS:+$LIST_QS&}project=$PROJECT_KEY"
if [[ -n "$ORGANIZATION" ]]; then
  DELETE_URI="$DELETE_URI?organization=$ORGANIZATION"
  LIST_QS="${LIST_QS:+$LIST_QS&}organization=$ORGANIZATION"
fi
[[ -n "$LIST_QS" ]] && LIST_URI="$LIST_URI?$LIST_QS"

TOKEN="$(read_local_secret sonarqube)"
BODY="$(build_form_body webhook "$WEBHOOK_KEY")"

if invoke_secure_rest POST "$DELETE_URI" "$TOKEN" "Bearer" "$BODY" "application/x-www-form-urlencoded" >/dev/null; then
  set_approval_consumed "$OPERATION_ID"
  VERIFICATION="FAILED"; RESULT="UNKNOWN"
  if FOUND="$(invoke_secure_rest GET "$LIST_URI" "$TOKEN")"; then
    STILL_PRESENT="$(echo "$FOUND" | jq --arg k "$WEBHOOK_KEY" '[.webhooks[] | select(.key==$k)] | length')"
    if [[ "$STILL_PRESENT" -eq 0 ]]; then VERIFICATION="CONFIRMED"; RESULT="SUCCESS"; fi
  fi

  write_audit_log "$OPERATION_ID" "$USER_NAME" "sonarqube" "runtime-detected" "webhook" "DELETE" "$TARGET" \
    "rest-api" "sonarqube-webhooks" "delete-webhook.sh" "$SCRIPT_VERSION" \
    "DESTRUCTIVE" true "APPROVED" "$RESULT" "$VERIFICATION" "null"

  jq -nc --arg o "$OPERATION_ID" --arg t "$TARGET" --arg r "$RESULT" --arg v "$VERIFICATION" \
    '{operationId:$o,target:$t,result:$r,verification:$v}'

  [[ "$VERIFICATION" != "CONFIRMED" ]] && exit "$EXIT_VERIFICATION_FAILURE"
  exit "$EXIT_SUCCESS"
else
  write_audit_log "$OPERATION_ID" "$USER_NAME" "sonarqube" "runtime-detected" "webhook" "DELETE" "$TARGET" \
    "rest-api" "sonarqube-webhooks" "delete-webhook.sh" "$SCRIPT_VERSION" \
    "DESTRUCTIVE" true "APPROVED" "FAILURE" "UNKNOWN" "request failed"
  echo "ERROR: failed to delete webhook '$TARGET'" >&2
  exit "$EXIT_GENERAL_FAILURE"
fi
