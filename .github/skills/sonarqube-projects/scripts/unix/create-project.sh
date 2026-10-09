#!/usr/bin/env bash
# create-project.sh - WRITE: Creates a new SonarQube project.
# Requires a pre-issued, matching "APPROVE CREATE" approval record.
#
# Purpose: Execute the CREATE stage for a new project.
# Supported OS: Linux, macOS (Bash).
# Dependencies: scripts/common/common.sh
# Parameters: --base-url --project-key --project-name [--organization]
#   [--visibility] --user --operation-id [--dry-run]
# Authentication: SonarQube user token (POC: local-secrets).
# Required permissions: 'Create Projects' permission.
# Approval requirements: MANDATORY "APPROVE CREATE".
# Dry-run: --dry-run prints the proposed action and exits without mutating.
# Deployment: works against BOTH Server and Cloud (pass --organization for Cloud).
# API/MCP dependency: REST fallback (POST api/projects/create).
# Exit codes: 0 success, 6 approval denied, 7 verification failure, 1 general failure.
# Output: JSON result.
# Verification: search-after-create; confirm the project key is present.
# Audit: writes one WRITE audit record.
# Security: TLS enforced; approval re-checked immediately before POST.
#
# Example:
#   ./create-project.sh --base-url https://sonarqube.example.internal \
#     --project-key my-app --project-name "My App" --user jdoe --operation-id op-aaa111

set -euo pipefail
SCRIPT_VERSION="1.0.0"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../../../../scripts/common/common.sh"

BASE_URL="" PROJECT_KEY="" PROJECT_NAME="" ORGANIZATION="" VISIBILITY="" USER_NAME="" OPERATION_ID="" DRY_RUN=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --base-url) BASE_URL="$2"; shift 2 ;;
    --project-key) PROJECT_KEY="$2"; shift 2 ;;
    --project-name) PROJECT_NAME="$2"; shift 2 ;;
    --organization) ORGANIZATION="$2"; shift 2 ;;
    --visibility) VISIBILITY="$2"; shift 2 ;;
    --user) USER_NAME="$2"; shift 2 ;;
    --operation-id) OPERATION_ID="$2"; shift 2 ;;
    --dry-run) DRY_RUN=true; shift ;;
    *) echo "Unknown argument: $1" >&2; exit "$EXIT_INVALID_PARAMETERS" ;;
  esac
done
[[ -z "$BASE_URL" || -z "$PROJECT_KEY" || -z "$PROJECT_NAME" || -z "$USER_NAME" || -z "$OPERATION_ID" ]] && { echo "Missing required arguments" >&2; exit "$EXIT_INVALID_PARAMETERS"; }

TARGET="$PROJECT_KEY"
OPERATION_KEY="sonarqube.project.create"

set +e
APPROVAL_OUTPUT="$(test_approval_token "$OPERATION_ID" "sonarqube" "$TARGET" "$OPERATION_KEY" "APPROVE CREATE")"
set -e
if [[ "$APPROVAL_OUTPUT" != "VALID" ]]; then
  write_audit_log "$OPERATION_ID" "$USER_NAME" "sonarqube" "runtime-detected" "project" "CREATE" "$TARGET" \
    "rest-api" "sonarqube-projects" "create-project.sh" "$SCRIPT_VERSION" \
    "WRITE" true "DENIED" "DENIED" "NOT_APPLICABLE" "${APPROVAL_OUTPUT#INVALID: }"
  echo "ERROR: Approval check failed: ${APPROVAL_OUTPUT#INVALID: }" >&2
  exit "$EXIT_APPROVAL_DENIED"
fi

if [[ "$DRY_RUN" == true ]]; then
  echo "(dry-run) Would CREATE SonarQube project '$TARGET'. No change made."
  exit "$EXIT_SUCCESS"
fi

CREATE_URI="$BASE_URL/api/projects/create"
SEARCH_URI="$BASE_URL/api/projects/search?projects=$PROJECT_KEY"
if [[ -n "$ORGANIZATION" ]]; then
  CREATE_URI="$CREATE_URI?organization=$ORGANIZATION"
  SEARCH_URI="$SEARCH_URI&organization=$ORGANIZATION"
fi
TOKEN="$(read_local_secret sonarqube)"
BODY="$(build_form_body project "$PROJECT_KEY" name "$PROJECT_NAME" visibility "$VISIBILITY")"

if invoke_secure_rest POST "$CREATE_URI" "$TOKEN" "Bearer" "$BODY" "application/x-www-form-urlencoded" >/dev/null; then
  set_approval_consumed "$OPERATION_ID"
  VERIFICATION="FAILED"; RESULT="UNKNOWN"
  if FOUND="$(invoke_secure_rest GET "$SEARCH_URI" "$TOKEN")"; then
    COUNT="$(echo "$FOUND" | jq '.components | length')"
    if [[ "$COUNT" -gt 0 ]]; then VERIFICATION="CONFIRMED"; RESULT="SUCCESS"; fi
  fi

  write_audit_log "$OPERATION_ID" "$USER_NAME" "sonarqube" "runtime-detected" "project" "CREATE" "$TARGET" \
    "rest-api" "sonarqube-projects" "create-project.sh" "$SCRIPT_VERSION" \
    "WRITE" true "APPROVED" "$RESULT" "$VERIFICATION" "null"

  jq -nc --arg o "$OPERATION_ID" --arg t "$TARGET" --arg r "$RESULT" --arg v "$VERIFICATION" \
    '{operationId:$o,target:$t,result:$r,verification:$v}'

  [[ "$VERIFICATION" != "CONFIRMED" ]] && exit "$EXIT_VERIFICATION_FAILURE"
  exit "$EXIT_SUCCESS"
else
  write_audit_log "$OPERATION_ID" "$USER_NAME" "sonarqube" "runtime-detected" "project" "CREATE" "$TARGET" \
    "rest-api" "sonarqube-projects" "create-project.sh" "$SCRIPT_VERSION" \
    "WRITE" true "APPROVED" "FAILURE" "UNKNOWN" "request failed"
  echo "ERROR: failed to create project '$TARGET'" >&2
  exit "$EXIT_GENERAL_FAILURE"
fi
