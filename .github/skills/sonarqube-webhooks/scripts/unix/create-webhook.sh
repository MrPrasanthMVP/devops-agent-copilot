#!/usr/bin/env bash
# create-webhook.sh - WRITE: Creates a new SonarQube webhook (global, or
# project-scoped). Requires a pre-issued, matching "APPROVE CREATE"
# approval record.
#
# Purpose: Execute the CREATE stage for a new webhook.
# Supported OS: Linux, macOS (Bash).
# Dependencies: scripts/common/common.sh
# Parameters: --base-url --name --url [--project-key] [--secret]
#   [--organization] --user --operation-id [--dry-run]
# Authentication: SonarQube user token (POC: local-secrets).
# Required permissions: 'Administer System' (global) or 'Administer' on
#   the project (project-scoped).
# Approval requirements: MANDATORY "APPROVE CREATE".
# Dry-run: --dry-run prints the proposed action and exits without mutating.
# Deployment: works against BOTH Server and Cloud (pass --organization for Cloud).
# API/MCP dependency: REST fallback (POST api/webhooks/create).
# Exit codes: 0 success, 6 approval denied, 7 verification failure, 1 general failure.
# Output: JSON result (includes the created webhook's key).
# Verification: list-after-create; confirm a webhook with the returned key is present.
# Audit: writes one WRITE audit record. The webhook secret (if supplied)
#   is never logged, printed, or included in the audit record.
# Security: TLS enforced; approval re-checked immediately before POST.
#
# Example:
#   ./create-webhook.sh --base-url https://sonarqube.example.internal \
#     --name "CI notify" --url https://ci.example.internal/sonar-hook \
#     --project-key my-app --user jdoe --operation-id op-aaa111

set -euo pipefail
SCRIPT_VERSION="1.0.0"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../../../../scripts/common/common.sh"

BASE_URL="" NAME="" WEBHOOK_URL="" PROJECT_KEY="" SECRET="" ORGANIZATION="" USER_NAME="" OPERATION_ID="" DRY_RUN=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --base-url) BASE_URL="$2"; shift 2 ;;
    --name) NAME="$2"; shift 2 ;;
    --url) WEBHOOK_URL="$2"; shift 2 ;;
    --project-key) PROJECT_KEY="$2"; shift 2 ;;
    --secret) SECRET="$2"; shift 2 ;;
    --organization) ORGANIZATION="$2"; shift 2 ;;
    --user) USER_NAME="$2"; shift 2 ;;
    --operation-id) OPERATION_ID="$2"; shift 2 ;;
    --dry-run) DRY_RUN=true; shift ;;
    *) echo "Unknown argument: $1" >&2; exit "$EXIT_INVALID_PARAMETERS" ;;
  esac
done
[[ -z "$BASE_URL" || -z "$NAME" || -z "$WEBHOOK_URL" || -z "$USER_NAME" || -z "$OPERATION_ID" ]] && { echo "Missing required arguments" >&2; exit "$EXIT_INVALID_PARAMETERS"; }

if [[ -n "$PROJECT_KEY" ]]; then TARGET="$PROJECT_KEY/$NAME"; else TARGET="global/$NAME"; fi
OPERATION_KEY="sonarqube.webhook.create"

set +e
APPROVAL_OUTPUT="$(test_approval_token "$OPERATION_ID" "sonarqube" "$TARGET" "$OPERATION_KEY" "APPROVE CREATE")"
set -e
if [[ "$APPROVAL_OUTPUT" != "VALID" ]]; then
  write_audit_log "$OPERATION_ID" "$USER_NAME" "sonarqube" "runtime-detected" "webhook" "CREATE" "$TARGET" \
    "rest-api" "sonarqube-webhooks" "create-webhook.sh" "$SCRIPT_VERSION" \
    "WRITE" true "DENIED" "DENIED" "NOT_APPLICABLE" "${APPROVAL_OUTPUT#INVALID: }"
  echo "ERROR: Approval check failed: ${APPROVAL_OUTPUT#INVALID: }" >&2
  exit "$EXIT_APPROVAL_DENIED"
fi

if [[ "$DRY_RUN" == true ]]; then
  echo "(dry-run) Would CREATE SonarQube webhook '$TARGET'. No change made."
  exit "$EXIT_SUCCESS"
fi

CREATE_URI="$BASE_URL/api/webhooks/create"
LIST_URI="$BASE_URL/api/webhooks/list"
LIST_QS=""
[[ -n "$PROJECT_KEY" ]] && LIST_QS="${LIST_QS:+$LIST_QS&}project=$PROJECT_KEY"
if [[ -n "$ORGANIZATION" ]]; then
  CREATE_URI="$CREATE_URI?organization=$ORGANIZATION"
  LIST_QS="${LIST_QS:+$LIST_QS&}organization=$ORGANIZATION"
fi
[[ -n "$LIST_QS" ]] && LIST_URI="$LIST_URI?$LIST_QS"

TOKEN="$(read_local_secret sonarqube)"
BODY="$(build_form_body name "$NAME" url "$WEBHOOK_URL" project "$PROJECT_KEY" secret "$SECRET")"

if CREATED="$(invoke_secure_rest POST "$CREATE_URI" "$TOKEN" "Bearer" "$BODY" "application/x-www-form-urlencoded")"; then
  CREATED_KEY="$(echo "$CREATED" | jq -r '.webhook.key // ""')"
  set_approval_consumed "$OPERATION_ID"
  VERIFICATION="FAILED"; RESULT="UNKNOWN"
  if FOUND="$(invoke_secure_rest GET "$LIST_URI" "$TOKEN")"; then
    MATCH_COUNT="$(echo "$FOUND" | jq --arg k "$CREATED_KEY" '[.webhooks[] | select(.key==$k)] | length')"
    if [[ "$MATCH_COUNT" -gt 0 ]]; then VERIFICATION="CONFIRMED"; RESULT="SUCCESS"; fi
  fi

  write_audit_log "$OPERATION_ID" "$USER_NAME" "sonarqube" "runtime-detected" "webhook" "CREATE" "$TARGET" \
    "rest-api" "sonarqube-webhooks" "create-webhook.sh" "$SCRIPT_VERSION" \
    "WRITE" true "APPROVED" "$RESULT" "$VERIFICATION" "null"

  jq -nc --arg o "$OPERATION_ID" --arg t "$TARGET" --arg k "$CREATED_KEY" --arg r "$RESULT" --arg v "$VERIFICATION" \
    '{operationId:$o,target:$t,webhookKey:$k,result:$r,verification:$v}'

  [[ "$VERIFICATION" != "CONFIRMED" ]] && exit "$EXIT_VERIFICATION_FAILURE"
  exit "$EXIT_SUCCESS"
else
  write_audit_log "$OPERATION_ID" "$USER_NAME" "sonarqube" "runtime-detected" "webhook" "CREATE" "$TARGET" \
    "rest-api" "sonarqube-webhooks" "create-webhook.sh" "$SCRIPT_VERSION" \
    "WRITE" true "APPROVED" "FAILURE" "UNKNOWN" "request failed"
  echo "ERROR: failed to create webhook '$TARGET'" >&2
  exit "$EXIT_GENERAL_FAILURE"
fi
