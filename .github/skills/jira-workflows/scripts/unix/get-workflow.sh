#!/usr/bin/env bash
# get-workflow.sh - READ_ONLY: Searches/retrieves Jira Cloud workflow definitions.
# Supported OS: Linux, macOS. Dependencies: scripts/common/common.sh
# Parameters: --site-url --workflow-name --email --api-token --user
# Authentication: Jira Cloud basic auth. Required permissions: "Administer Jira".
# Approval requirements: NONE. API/MCP dependency: REST fallback
#   (GET /rest/api/3/workflow/search); prefer discovered Rovo MCP tool.
# Exit codes: 0 success, 1 general failure. Output: workflow JSON.
# Verification: N/A. Audit: one READ record. Security: TLS enforced, no logged token.
#
# Example: ./get-workflow.sh --site-url https://example.atlassian.net \
#   --workflow-name "Software Simplified Workflow" --email jdoe@example.com \
#   --api-token "$JIRA_API_TOKEN" --user jdoe

set -euo pipefail
SCRIPT_VERSION="1.0.0"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../../../../scripts/common/common.sh"

SITE_URL="" WORKFLOW_NAME="" EMAIL="" API_TOKEN="" USER_NAME=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --site-url) SITE_URL="$2"; shift 2 ;;
    --workflow-name) WORKFLOW_NAME="$2"; shift 2 ;;
    --email) EMAIL="$2"; shift 2 ;;
    --api-token) API_TOKEN="$2"; shift 2 ;;
    --user) USER_NAME="$2"; shift 2 ;;
    *) echo "Unknown argument: $1" >&2; exit "$EXIT_INVALID_PARAMETERS" ;;
  esac
done
[[ -z "$SITE_URL" || -z "$WORKFLOW_NAME" || -z "$EMAIL" || -z "$API_TOKEN" || -z "$USER_NAME" ]] && { echo "Missing required arguments" >&2; exit "$EXIT_INVALID_PARAMETERS"; }

OPERATION_ID="$(new_operation_id)"
ENCODED_NAME="$(jq -rn --arg n "$WORKFLOW_NAME" '$n|@uri')"
URI="$SITE_URL/rest/api/3/workflow/search?workflowName=$ENCODED_NAME"
BASIC="$(printf '%s:%s' "$EMAIL" "$API_TOKEN" | base64 | tr -d '\n')"

if RESPONSE="$(invoke_secure_rest GET "$URI" "$BASIC" "Basic")"; then
  write_audit_log "$OPERATION_ID" "$USER_NAME" "jira" "cloud" "workflow" "GET" "$WORKFLOW_NAME" \
    "rest-api" "jira-workflows" "get-workflow.sh" "$SCRIPT_VERSION" \
    "READ_ONLY" false "NOT_REQUIRED" "SUCCESS" "NOT_APPLICABLE" "null"
  echo "$RESPONSE"
  exit "$EXIT_SUCCESS"
else
  write_audit_log "$OPERATION_ID" "$USER_NAME" "jira" "cloud" "workflow" "GET" "$WORKFLOW_NAME" \
    "rest-api" "jira-workflows" "get-workflow.sh" "$SCRIPT_VERSION" \
    "READ_ONLY" false "NOT_REQUIRED" "FAILURE" "NOT_APPLICABLE" "request failed"
  echo "ERROR: failed to retrieve workflow '$WORKFLOW_NAME'" >&2
  exit "$EXIT_GENERAL_FAILURE"
fi
