#!/usr/bin/env bash
# delete-project.sh
#
# Purpose: DESTRUCTIVE -- permanently deletes a SonarQube project
#   (including all its analyses, issues, and history) via the REST API
#   fallback. Requires a pre-issued, matching "APPROVE DELETE" approval record.
# Supported OS: Linux, macOS (Bash).
# Dependencies: scripts/common/common.sh (curl, jq, openssl)
# Parameters: --base-url --project-key [--organization] --user --operation-id [--dry-run]
# Authentication: SonarQube user token (POC: local-secrets).
# Required permissions: 'Administer System' or project 'Administer' permission.
# Approval requirements: MANDATORY "APPROVE DELETE" bound to this exact ProjectKey.
# Dry-run: --dry-run supported.
# Deployment: works against BOTH Server and Cloud (pass --organization for Cloud).
# API/MCP dependency: REST fallback -- POST api/projects/delete
# Exit codes: 0 success, 6 approval denied, 7 verification failure, 1 general
#   failure, 2 invalid parameters.
# Output: JSON result.
# Verification: search-after-delete; expect the project key absent from
#   results (no single-object GET exists to check for 404 on).
# Audit: writes one DESTRUCTIVE audit record.
# Security: TLS enforced; approval re-checked immediately before DELETE.
#
# Example:
#   ./delete-project.sh --base-url "https://sonarqube.example.internal" \
#       --project-key my-app --user jdoe --operation-id op-123

set -euo pipefail
SCRIPT_VERSION="1.0.0"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../../../../scripts/common/common.sh
source "$SCRIPT_DIR/../../../../../scripts/common/common.sh"

DRY_RUN=false
BASE_URL=""; PROJECT_KEY=""; ORGANIZATION=""; USER_NAME=""; OPERATION_ID=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --base-url) BASE_URL="$2"; shift 2 ;;
    --project-key) PROJECT_KEY="$2"; shift 2 ;;
    --organization) ORGANIZATION="$2"; shift 2 ;;
    --user) USER_NAME="$2"; shift 2 ;;
    --operation-id) OPERATION_ID="$2"; shift 2 ;;
    --dry-run) DRY_RUN=true; shift ;;
    *) echo "Unknown argument: $1" >&2; exit "$EXIT_INVALID_PARAMETERS" ;;
  esac
done

for v in BASE_URL PROJECT_KEY USER_NAME OPERATION_ID; do
  [[ -n "${!v}" ]] || { echo "ERROR: missing required argument for $v." >&2; exit "$EXIT_INVALID_PARAMETERS"; }
done
[[ "$PROJECT_KEY" =~ ^[A-Za-z0-9_.:-]+$ ]] || { echo "ERROR: invalid project key." >&2; exit "$EXIT_INVALID_PARAMETERS"; }

TARGET="$PROJECT_KEY"
OPERATION_KEY="sonarqube.project.delete"

VALIDATION=$(test_approval_token "$OPERATION_ID" "sonarqube" "$TARGET" "$OPERATION_KEY" "APPROVE DELETE") || true
if [[ "$VALIDATION" != "VALID" ]]; then
  write_audit_log "$OPERATION_ID" "$USER_NAME" "sonarqube" "runtime-detected" "project" "DELETE" "$TARGET" \
    "rest-api" "sonarqube-projects" "delete-project.sh" "$SCRIPT_VERSION" \
    "DESTRUCTIVE" "true" "DENIED" "DENIED" "NOT_APPLICABLE" "${VALIDATION#INVALID: }"
  echo "ERROR: Approval check failed: ${VALIDATION#INVALID: }" >&2
  exit "$EXIT_APPROVAL_DENIED"
fi

if [[ "$DRY_RUN" == "true" ]]; then
  echo "(dry-run) Would DELETE SonarQube project '$TARGET'. No change made."
  exit "$EXIT_SUCCESS"
fi

TOKEN="$(read_local_secret sonarqube)"
DELETE_URI="$BASE_URL/api/projects/delete"
SEARCH_URI="$BASE_URL/api/projects/search?projects=$PROJECT_KEY"
if [[ -n "$ORGANIZATION" ]]; then
  DELETE_URI="$DELETE_URI?organization=$ORGANIZATION"
  SEARCH_URI="$SEARCH_URI&organization=$ORGANIZATION"
fi
BODY="$(build_form_body project "$PROJECT_KEY")"

ERR_FILE="$(mktemp)"
trap 'rm -f "$ERR_FILE"' EXIT
if ! invoke_secure_rest POST "$DELETE_URI" "$TOKEN" "Bearer" "$BODY" "application/x-www-form-urlencoded" >/dev/null 2>"$ERR_FILE"; then
  ERR_MSG="$(cat "$ERR_FILE" 2>/dev/null || echo 'unknown error')"
  write_audit_log "$OPERATION_ID" "$USER_NAME" "sonarqube" "runtime-detected" "project" "DELETE" "$TARGET" \
    "rest-api" "sonarqube-projects" "delete-project.sh" "$SCRIPT_VERSION" \
    "DESTRUCTIVE" "true" "APPROVED" "FAILURE" "UNKNOWN" "$ERR_MSG"
  echo "ERROR: Failed to delete project '$TARGET': $ERR_MSG" >&2
  exit "$EXIT_GENERAL_FAILURE"
fi

set_approval_consumed "$OPERATION_ID"

VERIFICATION="UNKNOWN"; RESULT="UNKNOWN"
if FOUND="$(invoke_secure_rest GET "$SEARCH_URI" "$TOKEN")"; then
  COUNT="$(echo "$FOUND" | jq '.components | length')"
  if [[ "$COUNT" -eq 0 ]]; then VERIFICATION="CONFIRMED"; RESULT="SUCCESS"; else VERIFICATION="FAILED"; fi
else
  VERIFICATION="FAILED"
fi

write_audit_log "$OPERATION_ID" "$USER_NAME" "sonarqube" "runtime-detected" "project" "DELETE" "$TARGET" \
  "rest-api" "sonarqube-projects" "delete-project.sh" "$SCRIPT_VERSION" \
  "DESTRUCTIVE" "true" "APPROVED" "$RESULT" "$VERIFICATION" "null"

jq -n --arg operationId "$OPERATION_ID" --arg target "$TARGET" --arg result "$RESULT" --arg verification "$VERIFICATION" \
  '{operationId:$operationId, target:$target, result:$result, verification:$verification}'

[[ "$VERIFICATION" == "CONFIRMED" ]] || exit "$EXIT_VERIFICATION_FAILURE"
exit "$EXIT_SUCCESS"
