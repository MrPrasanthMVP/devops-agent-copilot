#!/usr/bin/env bash
# change-hotspot-status.sh - WRITE: Changes a SonarQube security
# hotspot's review status. Requires a pre-issued, matching
# "APPROVE UPDATE" approval record.
#
# Purpose: Execute the CHANGE_STATUS stage for one hotspot.
# Supported OS: Linux, macOS (Bash).
# Dependencies: scripts/common/common.sh
# Parameters: --base-url --hotspot-key --status [--resolution] [--comment]
#   [--organization] --user --operation-id [--dry-run]
# Status values: TO_REVIEW, REVIEWED (REVIEWED requires --resolution FIXED|SAFE)
# Authentication: SonarQube user token (POC: local-secrets).
# Required permissions: 'Administer Security Hotspot' on the project.
# Approval requirements: MANDATORY "APPROVE UPDATE".
# Dry-run: --dry-run prints the proposed action and exits without mutating.
# Deployment: works against BOTH Server and Cloud (pass --organization for Cloud).
# API/MCP dependency: REST fallback (POST api/hotspots/change_status).
# Exit codes: 0 success, 6 approval denied, 7 verification failure, 1 general failure.
# Output: JSON result.
# Verification: show-after-change; confirm the hotspot's status (and
#   resolution, when applicable) matches.
# Audit: writes one WRITE audit record.
# Security: TLS enforced; approval re-checked immediately before POST.
#
# Example:
#   ./change-hotspot-status.sh --base-url https://sonarqube.example.internal \
#     --hotspot-key AbCd1234 --status REVIEWED --resolution SAFE --user jdoe --operation-id op-aaa111

set -euo pipefail
SCRIPT_VERSION="1.0.0"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../../../../scripts/common/common.sh"

BASE_URL="" HOTSPOT_KEY="" STATUS="" RESOLUTION="" COMMENT="" ORGANIZATION="" USER_NAME="" OPERATION_ID="" DRY_RUN=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --base-url) BASE_URL="$2"; shift 2 ;;
    --hotspot-key) HOTSPOT_KEY="$2"; shift 2 ;;
    --status) STATUS="$2"; shift 2 ;;
    --resolution) RESOLUTION="$2"; shift 2 ;;
    --comment) COMMENT="$2"; shift 2 ;;
    --organization) ORGANIZATION="$2"; shift 2 ;;
    --user) USER_NAME="$2"; shift 2 ;;
    --operation-id) OPERATION_ID="$2"; shift 2 ;;
    --dry-run) DRY_RUN=true; shift ;;
    *) echo "Unknown argument: $1" >&2; exit "$EXIT_INVALID_PARAMETERS" ;;
  esac
done
[[ -z "$BASE_URL" || -z "$HOTSPOT_KEY" || -z "$STATUS" || -z "$USER_NAME" || -z "$OPERATION_ID" ]] && { echo "Missing required arguments" >&2; exit "$EXIT_INVALID_PARAMETERS"; }
[[ "$STATUS" == "REVIEWED" && -z "$RESOLUTION" ]] && { echo "ERROR: --resolution (FIXED or SAFE) is required when --status is REVIEWED" >&2; exit "$EXIT_INVALID_PARAMETERS"; }

TARGET="$HOTSPOT_KEY"
OPERATION_KEY="sonarqube.hotspot.change_status"

set +e
APPROVAL_OUTPUT="$(test_approval_token "$OPERATION_ID" "sonarqube" "$TARGET" "$OPERATION_KEY" "APPROVE UPDATE")"
set -e
if [[ "$APPROVAL_OUTPUT" != "VALID" ]]; then
  write_audit_log "$OPERATION_ID" "$USER_NAME" "sonarqube" "runtime-detected" "hotspot" "CHANGE_STATUS" "$TARGET" \
    "rest-api" "sonarqube-hotspots" "change-hotspot-status.sh" "$SCRIPT_VERSION" \
    "WRITE" true "DENIED" "DENIED" "NOT_APPLICABLE" "${APPROVAL_OUTPUT#INVALID: }"
  echo "ERROR: Approval check failed: ${APPROVAL_OUTPUT#INVALID: }" >&2
  exit "$EXIT_APPROVAL_DENIED"
fi

if [[ "$DRY_RUN" == true ]]; then
  echo "(dry-run) Would CHANGE_STATUS ($STATUS) SonarQube hotspot '$TARGET'. No change made."
  exit "$EXIT_SUCCESS"
fi

CHANGE_URI="$BASE_URL/api/hotspots/change_status"
SHOW_URI="$BASE_URL/api/hotspots/show?hotspot=$HOTSPOT_KEY"
if [[ -n "$ORGANIZATION" ]]; then
  CHANGE_URI="$CHANGE_URI?organization=$ORGANIZATION"
  SHOW_URI="$SHOW_URI&organization=$ORGANIZATION"
fi
TOKEN="$(read_local_secret sonarqube)"
BODY="$(build_form_body hotspot "$HOTSPOT_KEY" status "$STATUS" resolution "$RESOLUTION" comment "$COMMENT")"

if invoke_secure_rest POST "$CHANGE_URI" "$TOKEN" "Bearer" "$BODY" "application/x-www-form-urlencoded" >/dev/null; then
  set_approval_consumed "$OPERATION_ID"
  VERIFICATION="FAILED"; RESULT="UNKNOWN"
  if FOUND="$(invoke_secure_rest GET "$SHOW_URI" "$TOKEN")"; then
    ACTUAL_STATUS="$(echo "$FOUND" | jq -r '.status // ""')"
    ACTUAL_RESOLUTION="$(echo "$FOUND" | jq -r '.resolution // ""')"
    if [[ "$ACTUAL_STATUS" == "$STATUS" && ( -z "$RESOLUTION" || "$ACTUAL_RESOLUTION" == "$RESOLUTION" ) ]]; then
      VERIFICATION="CONFIRMED"; RESULT="SUCCESS"
    fi
  fi

  write_audit_log "$OPERATION_ID" "$USER_NAME" "sonarqube" "runtime-detected" "hotspot" "CHANGE_STATUS" "$TARGET" \
    "rest-api" "sonarqube-hotspots" "change-hotspot-status.sh" "$SCRIPT_VERSION" \
    "WRITE" true "APPROVED" "$RESULT" "$VERIFICATION" "null"

  jq -nc --arg o "$OPERATION_ID" --arg t "$TARGET" --arg s "$STATUS" --arg r "$RESULT" --arg v "$VERIFICATION" \
    '{operationId:$o,target:$t,status:$s,result:$r,verification:$v}'

  [[ "$VERIFICATION" != "CONFIRMED" ]] && exit "$EXIT_VERIFICATION_FAILURE"
  exit "$EXIT_SUCCESS"
else
  write_audit_log "$OPERATION_ID" "$USER_NAME" "sonarqube" "runtime-detected" "hotspot" "CHANGE_STATUS" "$TARGET" \
    "rest-api" "sonarqube-hotspots" "change-hotspot-status.sh" "$SCRIPT_VERSION" \
    "WRITE" true "APPROVED" "FAILURE" "UNKNOWN" "request failed"
  echo "ERROR: failed to change status for hotspot '$TARGET'" >&2
  exit "$EXIT_GENERAL_FAILURE"
fi
