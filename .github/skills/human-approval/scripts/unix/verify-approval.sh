#!/usr/bin/env bash
# verify-approval.sh
#
# Purpose: Verify a presented operationId has a valid, matching,
#   unconsumed approval record before an executing skill proceeds.
# Supported OS: Linux, macOS (Bash).
# Dependencies: scripts/common/common.sh (curl, jq, sha256sum, openssl)
# Parameters: --operation-id --system --target --operation --expected-approval-type
# Authentication: none.
# Required permissions: read access to logs/.approvals/.
# Approval requirements: N/A - this performs verification, not approval.
# Dry-run: not applicable (read-only).
# API/MCP dependency: none.
# Exit codes: 0 = valid, 6 = invalid/denied, 2 = invalid parameters.
# Output: "VALID" + JSON record on stdout when valid; reason on stderr otherwise.
# Verification: this IS the verification step.
# Audit: does not itself write an audit record (caller does).
# Security: validates HMAC signature and exact target/operation binding.
#
# Example:
#   ./verify-approval.sh --operation-id op-abc123 --system bitbucket \
#     --target "ABC/TEST" --operation bitbucket.repository.delete \
#     --expected-approval-type "APPROVE DELETE"

set -euo pipefail

SCRIPT_VERSION="1.0.0"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../../../../../scripts/common/common.sh
source "$SCRIPT_DIR/../../../../../scripts/common/common.sh"

OPERATION_ID="" SYSTEM="" TARGET="" OPERATION="" EXPECTED_TYPE=""

usage() {
  echo "Usage: $0 --operation-id ID --system SYS --target TGT --operation OP --expected-approval-type TYPE" >&2
  exit "$EXIT_INVALID_PARAMETERS"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --operation-id) OPERATION_ID="$2"; shift 2 ;;
    --system) SYSTEM="$2"; shift 2 ;;
    --target) TARGET="$2"; shift 2 ;;
    --operation) OPERATION="$2"; shift 2 ;;
    --expected-approval-type) EXPECTED_TYPE="$2"; shift 2 ;;
    *) echo "Unknown argument: $1" >&2; usage ;;
  esac
done

[[ -z "$OPERATION_ID" || -z "$SYSTEM" || -z "$TARGET" || -z "$OPERATION" || -z "$EXPECTED_TYPE" ]] && usage

set +e
OUTPUT="$(test_approval_token "$OPERATION_ID" "$SYSTEM" "$TARGET" "$OPERATION" "$EXPECTED_TYPE")"
STATUS=$?
set -e

if [[ "$OUTPUT" == "VALID" && $STATUS -eq 0 ]]; then
  echo "VALID"
  cat "$(repo_root)/logs/.approvals/$OPERATION_ID.json"
  exit "$EXIT_SUCCESS"
else
  echo "$OUTPUT" >&2
  exit "$EXIT_APPROVAL_DENIED"
fi
