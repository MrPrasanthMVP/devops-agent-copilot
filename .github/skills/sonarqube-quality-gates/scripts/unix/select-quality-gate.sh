#!/usr/bin/env bash
# select-quality-gate.sh - WRITE: Associates a SonarQube project with a
# quality gate. Requires a pre-issued, matching "APPROVE UPDATE" approval record.
#
# Purpose: Execute the SELECT stage, binding a project to a named
#   quality gate (future analyses are evaluated against it).
# Supported OS: Linux, macOS (Bash).
# Dependencies: scripts/common/common.sh
# Parameters: --base-url --project-key --gate-name [--organization]
#   --user --operation-id [--dry-run]
# Authentication: SonarQube user token (POC: local-secrets).
# Required permissions: 'Administer Quality Gates' permission.
# Approval requirements: MANDATORY "APPROVE UPDATE".
# Dry-run: --dry-run prints the proposed action and exits without mutating.
# Deployment: works against BOTH Server and Cloud (pass --organization for Cloud).
# API/MCP dependency: REST fallback (POST api/qualitygates/select).
# Exit codes: 0 success, 6 approval denied, 1 general failure.
# Output: JSON result.
# Verification: api/qualitygates/select has no read-back body -- a
#   non-failing POST is the only confirmation this API offers; reported
#   as CONFIRMED on success rather than claiming a richer GET-after-write
#   check the API does not support.
# Audit: writes one WRITE audit record.
# Security: TLS enforced; approval re-checked immediately before POST.
#
# Example:
#   ./select-quality-gate.sh --base-url https://sonarqube.example.internal \
#     --project-key my-app --gate-name "Sonar way" --user jdoe --operation-id op-aaa111

set -euo pipefail
SCRIPT_VERSION="1.0.0"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../../../../scripts/common/common.sh"

BASE_URL="" PROJECT_KEY="" GATE_NAME="" ORGANIZATION="" USER_NAME="" OPERATION_ID="" DRY_RUN=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --base-url) BASE_URL="$2"; shift 2 ;;
    --project-key) PROJECT_KEY="$2"; shift 2 ;;
    --gate-name) GATE_NAME="$2"; shift 2 ;;
    --organization) ORGANIZATION="$2"; shift 2 ;;
    --user) USER_NAME="$2"; shift 2 ;;
    --operation-id) OPERATION_ID="$2"; shift 2 ;;
    --dry-run) DRY_RUN=true; shift ;;
    *) echo "Unknown argument: $1" >&2; exit "$EXIT_INVALID_PARAMETERS" ;;
  esac
done
[[ -z "$BASE_URL" || -z "$PROJECT_KEY" || -z "$GATE_NAME" || -z "$USER_NAME" || -z "$OPERATION_ID" ]] && { echo "Missing required arguments" >&2; exit "$EXIT_INVALID_PARAMETERS"; }

TARGET="$PROJECT_KEY"
OPERATION_KEY="sonarqube.quality_gate.select"

set +e
APPROVAL_OUTPUT="$(test_approval_token "$OPERATION_ID" "sonarqube" "$TARGET" "$OPERATION_KEY" "APPROVE UPDATE")"
set -e
if [[ "$APPROVAL_OUTPUT" != "VALID" ]]; then
  write_audit_log "$OPERATION_ID" "$USER_NAME" "sonarqube" "runtime-detected" "quality_gate" "SELECT" "$TARGET" \
    "rest-api" "sonarqube-quality-gates" "select-quality-gate.sh" "$SCRIPT_VERSION" \
    "WRITE" true "DENIED" "DENIED" "NOT_APPLICABLE" "${APPROVAL_OUTPUT#INVALID: }"
  echo "ERROR: Approval check failed: ${APPROVAL_OUTPUT#INVALID: }" >&2
  exit "$EXIT_APPROVAL_DENIED"
fi

if [[ "$DRY_RUN" == true ]]; then
  echo "(dry-run) Would SELECT quality gate '$GATE_NAME' for SonarQube project '$TARGET'. No change made."
  exit "$EXIT_SUCCESS"
fi

SELECT_URI="$BASE_URL/api/qualitygates/select"
[[ -n "$ORGANIZATION" ]] && SELECT_URI="$SELECT_URI?organization=$ORGANIZATION"
TOKEN="$(read_local_secret sonarqube)"
BODY="$(build_form_body projectKey "$PROJECT_KEY" gateName "$GATE_NAME")"

if invoke_secure_rest POST "$SELECT_URI" "$TOKEN" "Bearer" "$BODY" "application/x-www-form-urlencoded" >/dev/null; then
  set_approval_consumed "$OPERATION_ID"
  # api/qualitygates/select has no read-back body -- a non-failing POST
  # is the only confirmation this API offers (see header comment).
  VERIFICATION="CONFIRMED"; RESULT="SUCCESS"

  write_audit_log "$OPERATION_ID" "$USER_NAME" "sonarqube" "runtime-detected" "quality_gate" "SELECT" "$TARGET" \
    "rest-api" "sonarqube-quality-gates" "select-quality-gate.sh" "$SCRIPT_VERSION" \
    "WRITE" true "APPROVED" "$RESULT" "$VERIFICATION" "null"

  jq -nc --arg o "$OPERATION_ID" --arg t "$TARGET" --arg g "$GATE_NAME" --arg r "$RESULT" --arg v "$VERIFICATION" \
    '{operationId:$o,target:$t,gateName:$g,result:$r,verification:$v}'
  exit "$EXIT_SUCCESS"
else
  write_audit_log "$OPERATION_ID" "$USER_NAME" "sonarqube" "runtime-detected" "quality_gate" "SELECT" "$TARGET" \
    "rest-api" "sonarqube-quality-gates" "select-quality-gate.sh" "$SCRIPT_VERSION" \
    "WRITE" true "APPROVED" "FAILURE" "UNKNOWN" "request failed"
  echo "ERROR: failed to select quality gate for '$TARGET'" >&2
  exit "$EXIT_GENERAL_FAILURE"
fi
