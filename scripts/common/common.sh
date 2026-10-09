#!/usr/bin/env bash
# common.sh
# Shared Bash helper library for the Enterprise DevOps Copilot Control
# Framework. Every operational script under
# .github/skills/*/scripts/unix/*.sh sources this file so that approval
# verification, audit logging, exit-code semantics, and secure HTTP
# behavior are IDENTICAL across every skill and IDENTICAL in meaning to
# scripts/common/Common.psm1.
#
# Do not duplicate this logic inside individual skill scripts.
# Do not weaken any security control in this file to make a single
# skill's script "work" - fix the caller instead.

set -euo pipefail

COMMON_SH_VERSION="1.0.0"

for dep in curl jq sha256sum; do
  if ! command -v "$dep" >/dev/null 2>&1; then
    echo "ERROR: required dependency '$dep' not found on PATH." >&2
    exit 10
  fi
done

# ----------------------------------------------------------------------------
# Section 31 - Standard exit codes (must match scripts/common/Common.psm1)
# ----------------------------------------------------------------------------
EXIT_SUCCESS=0
EXIT_GENERAL_FAILURE=1
EXIT_INVALID_PARAMETERS=2
EXIT_AUTHENTICATION_FAILURE=3
EXIT_AUTHORIZATION_FAILURE=4
EXIT_APPROVAL_REQUIRED=5
EXIT_APPROVAL_DENIED=6
EXIT_VERIFICATION_FAILURE=7
EXIT_TARGET_NOT_FOUND=8
EXIT_UNSUPPORTED_OPERATION=9
EXIT_CONFIGURATION_ERROR=10

repo_root() {
  # scripts/common/common.sh -> repo root is two levels up.
  local here
  here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  (cd "$here/../.." && pwd)
}

new_operation_id() {
  local raw
  if command -v uuidgen >/dev/null 2>&1; then
    raw="$(uuidgen | tr -d '-' | tr '[:upper:]' '[:lower:]' | cut -c1-12)"
  else
    raw="$(head -c 16 /dev/urandom | od -An -tx1 | tr -d ' \n' | cut -c1-12)"
  fi
  echo "op-$raw"
}

# ----------------------------------------------------------------------------
# Secret handling (Section 11 / 28 / 35 - never print, never log credentials)
# ----------------------------------------------------------------------------
read_local_secret() {
  # Usage: read_local_secret <bitbucket|jfrog|github|sonarqube>
  local system="$1"
  local root path
  root="$(repo_root)"
  path="$root/.github/local-secrets/${system}-token.txt"

  if [[ ! -f "$path" ]]; then
    echo "ERROR: local secret file not found for '$system'. Copy .github/local-secrets/${system}-token.txt.example to ${system}-token.txt and populate it. POC-only mechanism - see SECURITY.md." >&2
    exit "$EXIT_CONFIGURATION_ERROR"
  fi

  local value
  value="$(tr -d '\r\n' < "$path")"
  if [[ -z "$value" || "$value" == REPLACE_WITH_* ]]; then
    echo "ERROR: local secret file for '$system' has not been populated with a real credential." >&2
    exit "$EXIT_CONFIGURATION_ERROR"
  fi
  printf '%s' "$value"
}

redact_json() {
  # Redacts sensitive keys from a JSON blob on stdin before logging/printing.
  jq 'walk(if type == "object" then
        with_entries(if (.key | test("(?i)(password|token|secret|authorization|cookie|private[_-]?key|client[_-]?secret|refresh[_-]?token|api[_-]?key)")) then .value = "***REDACTED***" else . end)
      else . end)'
}

# ----------------------------------------------------------------------------
# Approval token binding (Section 32)
# ----------------------------------------------------------------------------
_approval_signing_key() {
  local root key_path
  root="$(repo_root)"
  key_path="$root/.github/local-secrets/approval-signing-key.txt"
  if [[ ! -f "$key_path" ]]; then
    echo "POC-ONLY-NON-PRODUCTION-SIGNING-KEY-$(date -u +%Y%m%d)" > "$key_path"
  fi
  tr -d '\r\n' < "$key_path"
}

_approval_sign() {
  # Usage: _approval_sign <canonical-json-payload>
  local payload="$1" key
  key="$(_approval_signing_key)"
  printf '%s' "$payload" | openssl dgst -sha256 -hmac "$key" -binary 2>/dev/null | base64 | tr -d '\n'
}

new_approval_token() {
  # Usage: new_approval_token <operationId> <user> <system> <target> <operation> <risk> <approvalType>
  local operation_id="$1" user="$2" system="$3" target="$4" operation="$5" risk="$6" approval_type="$7"
  local root dir issued_at payload signature record
  root="$(repo_root)"
  dir="$root/logs/.approvals"
  mkdir -p "$dir"
  issued_at="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

  payload=$(jq -nc \
    --arg operationId "$operation_id" --arg user "$user" --arg system "$system" \
    --arg target "$target" --arg operation "$operation" --arg risk "$risk" \
    --arg approvalType "$approval_type" --arg issuedAt "$issued_at" \
    '{operationId:$operationId,user:$user,system:$system,target:$target,operation:$operation,risk:$risk,approvalType:$approvalType,issuedAt:$issuedAt}')

  signature="$(_approval_sign "$payload")"
  record="$(printf '%s' "$payload" | jq --arg sig "$signature" '. + {signature:$sig}')"
  printf '%s' "$record" > "$dir/$operation_id.json"
  printf '%s' "$record"
}

test_approval_token() {
  # Usage: test_approval_token <operationId> <system> <target> <operation> <expectedApprovalType>
  # Prints "VALID" or "INVALID: <reason>" to stdout.
  local operation_id="$1" system="$2" target="$3" operation="$4" expected_type="$5"
  local root approval_path record signature unsigned expected_sig consumed_path
  root="$(repo_root)"
  approval_path="$root/logs/.approvals/$operation_id.json"

  if [[ ! -f "$approval_path" ]]; then
    echo "INVALID: No approval record found for operationId '$operation_id'."
    return 1
  fi

  record="$(cat "$approval_path")"
  signature="$(echo "$record" | jq -r '.signature')"
  unsigned="$(echo "$record" | jq -c '{operationId,user,system,target,operation,risk,approvalType,issuedAt}')"
  expected_sig="$(_approval_sign "$unsigned")"

  if [[ "$signature" != "$expected_sig" ]]; then
    echo "INVALID: Approval signature mismatch - possible tampering."
    return 1
  fi

  local rec_system rec_target rec_operation rec_approval_type
  rec_system="$(echo "$record" | jq -r '.system')"
  rec_target="$(echo "$record" | jq -r '.target')"
  rec_operation="$(echo "$record" | jq -r '.operation')"
  rec_approval_type="$(echo "$record" | jq -r '.approvalType')"

  if [[ "$rec_system" != "$system" || "$rec_target" != "$target" || "$rec_operation" != "$operation" ]]; then
    echo "INVALID: Approval record does not match the requested system/target/operation."
    return 1
  fi

  if [[ "$rec_approval_type" != "$expected_type" ]]; then
    echo "INVALID: Approval type '$rec_approval_type' does not satisfy required approval type '$expected_type'."
    return 1
  fi

  consumed_path="$root/logs/.approvals/$operation_id.consumed"
  if [[ -f "$consumed_path" ]]; then
    echo "INVALID: Approval has already been consumed by a prior execution."
    return 1
  fi

  echo "VALID"
  return 0
}

set_approval_consumed() {
  local operation_id="$1" root
  root="$(repo_root)"
  date -u +%Y-%m-%dT%H:%M:%SZ > "$root/logs/.approvals/$operation_id.consumed"
}

# ----------------------------------------------------------------------------
# Audit logging (Section 35 / 36)
# ----------------------------------------------------------------------------
write_audit_log() {
  # Usage: write_audit_log <operationId> <user> <system> <systemVersion> \
  #   <resource> <operation> <target> <executionMechanism> <skill> \
  #   <script|null> <scriptVersion|null> <risk> <approvalRequired:true|false> \
  #   <approvalStatus> <result> <verification> <error|null>
  local operation_id="$1" user="$2" system="$3" system_version="$4" resource="$5" \
        operation="$6" target="$7" execution_mechanism="$8" skill="$9" \
        script="${10}" script_version="${11}" risk="${12}" approval_required="${13}" \
        approval_status="${14}" result="${15}" verification="${16}" error="${17:-null}"

  local root logs_dir log_path timestamp record
  root="$(repo_root)"
  logs_dir="$root/logs"
  mkdir -p "$logs_dir"
  log_path="$logs_dir/enterprise-devops-audit.jsonl"
  timestamp="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

  record=$(jq -nc \
    --arg timestamp "$timestamp" --arg operationId "$operation_id" --arg user "$user" \
    --arg system "$system" --arg systemVersion "$system_version" --arg resource "$resource" \
    --arg operation "$operation" --arg target "$target" --arg executionMechanism "$execution_mechanism" \
    --arg skill "$skill" --arg script "$script" --arg scriptVersion "$script_version" \
    --arg risk "$risk" --argjson approvalRequired "$approval_required" --arg approvalStatus "$approval_status" \
    --arg result "$result" --arg verification "$verification" --arg error "$error" \
    '{timestamp:$timestamp,operationId:$operationId,user:$user,system:$system,systemVersion:$systemVersion,
      resource:$resource,operation:$operation,target:$target,executionMechanism:$executionMechanism,
      skill:$skill,
      script:(if $script == "null" then null else $script end),
      scriptVersion:(if $scriptVersion == "null" then null else $scriptVersion end),
      risk:$risk,approvalRequired:$approvalRequired,approvalStatus:$approvalStatus,
      result:$result,verification:$verification,
      error:(if $error == "null" then null else $error end)}')

  echo "$record" | redact_json >> "$log_path"
}

# ----------------------------------------------------------------------------
# Secure HTTP (Section 28 / 29 - TLS verification must never be disabled)
# ----------------------------------------------------------------------------
invoke_secure_rest() {
  # Usage: invoke_secure_rest <METHOD> <URL> [token] [authScheme] [body] [contentType]
  # contentType defaults to application/json -- every existing caller
  # (Bitbucket, JFrog, Jira, Confluence, GitHub) is unaffected. Pass
  # "application/x-www-form-urlencoded" (with a body built by
  # build_form_body, below) for SonarQube's v1 Web API, which -- unlike
  # every other system in this framework -- does NOT accept a JSON POST
  # body; only api/v2/* SonarQube endpoints do.
  local method="$1" url="$2" token="${3:-}" auth_scheme="${4:-Bearer}" body="${5:-}" content_type="${6:-application/json}"

  if [[ "$url" != https://* ]]; then
    echo "ERROR: refusing to call a non-HTTPS endpoint: $url" >&2
    return "$EXIT_CONFIGURATION_ERROR"
  fi

  local -a curl_args=(--fail --silent --show-error --location --max-time 30 -X "$method")
  curl_args+=(-H "Accept: application/json")
  if [[ -n "$token" ]]; then
    curl_args+=(-H "Authorization: ${auth_scheme} ${token}")
  fi
  if [[ -n "$body" ]]; then
    curl_args+=(-H "Content-Type: ${content_type}" --data "$body")
  fi
  curl_args+=("$url")

  # Never add -k / --insecure here. TLS verification stays enabled.
  curl "${curl_args[@]}"
}

build_form_body() {
  # Usage: build_form_body key1 val1 [key2 val2 ...]
  # Builds an application/x-www-form-urlencoded string (key=value&key=value),
  # URL-encoding each value via jq's @uri filter. Pairs whose value is empty
  # are omitted entirely (mirrors Invoke-SecureRestMethod -BodyEncoding Form
  # in Common.psm1 skipping null/empty values).
  local out="" key val encoded
  while [[ $# -gt 0 ]]; do
    key="$1" val="${2:-}"
    shift 2 || shift $#
    [[ -z "$val" ]] && continue
    encoded="$(jq -rn --arg v "$val" '$v|@uri')"
    if [[ -n "$out" ]]; then out+="&"; fi
    out+="${key}=${encoded}"
  done
  echo "$out"
}

get_operation_classification() {
  # Usage: get_operation_classification <system.resource.operation>
  local key="$1" root json_path
  root="$(repo_root)"
  json_path="$root/policies/operation-classification.json"
  if [[ ! -f "$json_path" ]]; then
    echo "ERROR: policies/operation-classification.json not found." >&2
    return "$EXIT_CONFIGURATION_ERROR"
  fi
  local entry
  entry="$(jq -r --arg k "$key" '.operations[$k] // empty' "$json_path")"
  if [[ -z "$entry" ]]; then
    echo "ERROR: Operation '$key' is not classified. Refusing to proceed without an explicit classification (fail closed)." >&2
    return "$EXIT_CONFIGURATION_ERROR"
  fi
  echo "$entry"
}
