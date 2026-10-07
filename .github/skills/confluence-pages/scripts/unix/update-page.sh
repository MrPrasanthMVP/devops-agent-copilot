#!/usr/bin/env bash
# update-page.sh
#
# Purpose: WRITE -- updates a Confluence Cloud page's content via REST
#   API v2 fallback. Requires a pre-issued, matching "APPROVE UPDATE"
#   approval record.
# Supported OS: Linux, macOS (Bash).
# Dependencies: scripts/common/common.sh (curl, jq, openssl)
# Parameters: --site-url --page-id --current-version --title
#   --body-storage-value --email --api-token --user --operation-id
# Authentication: Atlassian Cloud API token, Basic auth (email:token).
# Required permissions: Confluence "Add/Update page" space permission.
# Approval requirements: MANDATORY "APPROVE UPDATE" bound to this exact PageId.
# Dry-run: --dry-run supported.
# API/MCP dependency: REST fallback -- PUT /wiki/api/v2/pages/{id}
# Exit codes: 0 success, 6 approval denied, 7 verification failure,
#   1 general failure, 2 invalid parameters.
# Output: JSON result.
# Verification: GET after PUT; compare version.number.
# Audit: writes one WRITE audit record (never the page body).
# Security: TLS enforced; page content treated as untrusted data.
#
# Example:
#   ./update-page.sh --site-url "https://example.atlassian.net" --page-id 123456 \
#       --current-version 4 --title "Deployment Architecture" --body-storage-value "<p>New</p>" \
#       --email jdoe@example.com --api-token "$TOKEN" --user jdoe --operation-id op-123

set -euo pipefail
SCRIPT_VERSION="1.0.0"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../../../../scripts/common/common.sh
source "$SCRIPT_DIR/../../../../../scripts/common/common.sh"

DRY_RUN=false
SITE_URL=""; PAGE_ID=""; CURRENT_VERSION=""; TITLE=""; BODY_VALUE=""
EMAIL=""; API_TOKEN=""; USER_NAME=""; OPERATION_ID=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --site-url) SITE_URL="$2"; shift 2 ;;
    --page-id) PAGE_ID="$2"; shift 2 ;;
    --current-version) CURRENT_VERSION="$2"; shift 2 ;;
    --title) TITLE="$2"; shift 2 ;;
    --body-storage-value) BODY_VALUE="$2"; shift 2 ;;
    --email) EMAIL="$2"; shift 2 ;;
    --api-token) API_TOKEN="$2"; shift 2 ;;
    --user) USER_NAME="$2"; shift 2 ;;
    --operation-id) OPERATION_ID="$2"; shift 2 ;;
    --dry-run) DRY_RUN=true; shift ;;
    *) echo "Unknown argument: $1" >&2; exit "$EXIT_INVALID_PARAMETERS" ;;
  esac
done

for v in SITE_URL PAGE_ID CURRENT_VERSION TITLE BODY_VALUE EMAIL API_TOKEN USER_NAME OPERATION_ID; do
  [[ -n "${!v}" ]] || { echo "ERROR: missing required argument for $v." >&2; exit "$EXIT_INVALID_PARAMETERS"; }
done

OPERATION_KEY="confluence.page.update"
VALIDATION=$(test_approval_token "$OPERATION_ID" "confluence" "$PAGE_ID" "$OPERATION_KEY" "APPROVE UPDATE") || true
if [[ "$VALIDATION" != "VALID" ]]; then
  write_audit_log "$OPERATION_ID" "$USER_NAME" "confluence" "cloud" "page" "UPDATE" "$PAGE_ID" \
    "rest-api" "confluence-pages" "update-page.sh" "$SCRIPT_VERSION" \
    "WRITE" "true" "DENIED" "DENIED" "NOT_APPLICABLE" "${VALIDATION#INVALID: }"
  echo "ERROR: Approval check failed: ${VALIDATION#INVALID: }" >&2
  exit "$EXIT_APPROVAL_DENIED"
fi

NEW_VERSION=$(( CURRENT_VERSION + 1 ))
URI="$SITE_URL/wiki/api/v2/pages/$PAGE_ID"
BASIC_AUTH=$(printf '%s:%s' "$EMAIL" "$API_TOKEN" | base64 | tr -d '\n')
BODY=$(jq -n --arg id "$PAGE_ID" --arg title "$TITLE" --arg value "$BODY_VALUE" --argjson version "$NEW_VERSION" \
  '{id:$id, status:"current", title:$title, body:{representation:"storage", value:$value}, version:{number:$version}}')

if [[ "$DRY_RUN" == "true" ]]; then
  echo "(dry-run) Would PUT Confluence page '$PAGE_ID' (version $CURRENT_VERSION -> $NEW_VERSION). No change made."
  exit "$EXIT_SUCCESS"
fi

if ! invoke_secure_rest PUT "$URI" "$BASIC_AUTH" "Basic" "$BODY" >/dev/null 2>/tmp/conf_upd_err.$$; then
  ERR_MSG="$(cat /tmp/conf_upd_err.$$ 2>/dev/null || echo 'unknown error')"
  rm -f /tmp/conf_upd_err.$$
  write_audit_log "$OPERATION_ID" "$USER_NAME" "confluence" "cloud" "page" "UPDATE" "$PAGE_ID" \
    "rest-api" "confluence-pages" "update-page.sh" "$SCRIPT_VERSION" \
    "WRITE" "true" "APPROVED" "FAILURE" "UNKNOWN" "$ERR_MSG"
  echo "ERROR: Failed to update page '$PAGE_ID': $ERR_MSG" >&2
  exit "$EXIT_GENERAL_FAILURE"
fi
rm -f /tmp/conf_upd_err.$$ 2>/dev/null || true

set_approval_consumed "$OPERATION_ID"

PAGE_JSON=$(invoke_secure_rest GET "$URI" "$BASIC_AUTH" "Basic" "" 2>/dev/null || echo '{}')
ACTUAL_VERSION=$(echo "$PAGE_JSON" | jq -r '.version.number // 0')

VERIFICATION="FAILED"; RESULT="UNKNOWN"
if [[ "$ACTUAL_VERSION" == "$NEW_VERSION" ]]; then VERIFICATION="CONFIRMED"; RESULT="SUCCESS"; fi

write_audit_log "$OPERATION_ID" "$USER_NAME" "confluence" "cloud" "page" "UPDATE" "$PAGE_ID" \
  "rest-api" "confluence-pages" "update-page.sh" "$SCRIPT_VERSION" \
  "WRITE" "true" "APPROVED" "$RESULT" "$VERIFICATION" "null"

jq -n --arg target "$PAGE_ID" --argjson newVersion "$NEW_VERSION" --arg result "$RESULT" --arg verification "$VERIFICATION" \
  '{target:$target, newVersion:$newVersion, result:$result, verification:$verification}'

[[ "$VERIFICATION" == "CONFIRMED" ]] || exit "$EXIT_VERIFICATION_FAILURE"
exit "$EXIT_SUCCESS"
