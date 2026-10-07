#!/usr/bin/env bash
# upload-artifact.sh - WRITE: Uploads (deploys) a local file as an
# artifact. Requires a pre-issued "APPROVE CREATE" approval record.
#
# Purpose: Execute the CREATE/deploy stage for a new artifact.
# Supported OS: Linux, macOS (Bash).
# Dependencies: scripts/common/common.sh, sha256sum
# Parameters: --base-url --repo-key --item-path --local-file --user
#   --operation-id [--dry-run]
# Authentication: JFrog access token (POC: local-secrets).
# Required permissions: deploy permission on the target repository.
# Approval requirements: MANDATORY "APPROVE CREATE". If an artifact
#   already exists at the target path, the proposal must flag it as an
#   overwrite before approval is sought.
# Dry-run: --dry-run supported.
# API/MCP dependency: REST fallback (PUT /artifactory/{repoKey}/{itemPath}).
# Exit codes: 0 success, 6 approval denied, 7 verification failure, 1 general failure.
# Output: JSON result.
# Verification: GET storage info after PUT; confirm sha256 checksum matches.
# Audit: writes one WRITE audit record.
# Security: TLS enforced; --item-path rejected if it contains "..";
#   approval re-checked immediately before PUT.
#
# Example:
#   ./upload-artifact.sh --base-url https://jfrog.example.com \
#     --repo-key libs-release-local --item-path "com/example/app/2.0/app.jar" \
#     --local-file ./build/app.jar --user jdoe --operation-id op-123

set -euo pipefail
SCRIPT_VERSION="1.0.0"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../../../../scripts/common/common.sh"

BASE_URL="" REPO_KEY="" ITEM_PATH="" LOCAL_FILE="" USER_NAME="" OPERATION_ID="" DRY_RUN=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --base-url) BASE_URL="$2"; shift 2 ;;
    --repo-key) REPO_KEY="$2"; shift 2 ;;
    --item-path) ITEM_PATH="$2"; shift 2 ;;
    --local-file) LOCAL_FILE="$2"; shift 2 ;;
    --user) USER_NAME="$2"; shift 2 ;;
    --operation-id) OPERATION_ID="$2"; shift 2 ;;
    --dry-run) DRY_RUN=true; shift ;;
    *) echo "Unknown argument: $1" >&2; exit "$EXIT_INVALID_PARAMETERS" ;;
  esac
done
[[ -z "$BASE_URL" || -z "$REPO_KEY" || -z "$ITEM_PATH" || -z "$LOCAL_FILE" || -z "$USER_NAME" || -z "$OPERATION_ID" ]] && { echo "Missing required arguments" >&2; exit "$EXIT_INVALID_PARAMETERS"; }
[[ "$ITEM_PATH" == *".."* ]] && { echo "ERROR: --item-path must not contain '..'" >&2; exit "$EXIT_INVALID_PARAMETERS"; }
[[ ! -f "$LOCAL_FILE" ]] && { echo "ERROR: --local-file '$LOCAL_FILE' does not exist." >&2; exit "$EXIT_INVALID_PARAMETERS"; }

TARGET="$REPO_KEY/$ITEM_PATH"
OPERATION_KEY="jfrog.artifact.upload"

set +e
APPROVAL_OUTPUT="$(test_approval_token "$OPERATION_ID" "jfrog" "$TARGET" "$OPERATION_KEY" "APPROVE CREATE")"
APPROVAL_STATUS=$?
set -e

if [[ $APPROVAL_STATUS -ne 0 ]]; then
  write_audit_log "$OPERATION_ID" "$USER_NAME" "jfrog" "runtime-detected" "artifact" "CREATE" "$TARGET" \
    "rest-api" "jfrog-artifacts" "upload-artifact.sh" "$SCRIPT_VERSION" \
    "WRITE" true "DENIED" "DENIED" "NOT_APPLICABLE" "$APPROVAL_OUTPUT"
  echo "$APPROVAL_OUTPUT" >&2
  exit "$EXIT_APPROVAL_DENIED"
fi

if [[ "$DRY_RUN" == true ]]; then
  echo "(dry-run) Would UPLOAD artifact to '$TARGET'. No change made."
  exit "$EXIT_SUCCESS"
fi

UPLOAD_URI="$BASE_URL/artifactory/$REPO_KEY/$ITEM_PATH"
STORAGE_URI="$BASE_URL/artifactory/api/storage/$REPO_KEY/$ITEM_PATH"
TOKEN="$(read_local_secret jfrog)"
LOCAL_HASH="$(sha256sum "$LOCAL_FILE" | awk '{print $1}')"

if curl --fail --silent --show-error --location --max-time 120 \
  -X PUT "$UPLOAD_URI" -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/octet-stream" --data-binary "@$LOCAL_FILE" >/dev/null; then

  set_approval_consumed "$OPERATION_ID"
  VERIFICATION="FAILED"; RESULT="UNKNOWN"
  if INFO="$(invoke_secure_rest GET "$STORAGE_URI" "$TOKEN")"; then
    REMOTE_HASH="$(echo "$INFO" | jq -r '.checksums.sha256 // empty')"
    if [[ "$REMOTE_HASH" == "$LOCAL_HASH" ]]; then VERIFICATION="CONFIRMED"; RESULT="SUCCESS"; fi
  fi

  write_audit_log "$OPERATION_ID" "$USER_NAME" "jfrog" "runtime-detected" "artifact" "CREATE" "$TARGET" \
    "rest-api" "jfrog-artifacts" "upload-artifact.sh" "$SCRIPT_VERSION" \
    "WRITE" true "APPROVED" "$RESULT" "$VERIFICATION" "null"

  jq -nc --arg o "$OPERATION_ID" --arg t "$TARGET" --arg r "$RESULT" --arg v "$VERIFICATION" \
    '{operationId:$o,target:$t,result:$r,verification:$v}'

  [[ "$VERIFICATION" != "CONFIRMED" ]] && exit "$EXIT_VERIFICATION_FAILURE"
  exit "$EXIT_SUCCESS"
else
  write_audit_log "$OPERATION_ID" "$USER_NAME" "jfrog" "runtime-detected" "artifact" "CREATE" "$TARGET" \
    "rest-api" "jfrog-artifacts" "upload-artifact.sh" "$SCRIPT_VERSION" \
    "WRITE" true "APPROVED" "FAILURE" "UNKNOWN" "upload request failed"
  echo "ERROR: failed to upload artifact to '$TARGET'" >&2
  exit "$EXIT_GENERAL_FAILURE"
fi
