#!/usr/bin/env bash
# validate-security.sh
#
# Purpose: Scans the repository for security-policy violations: forbidden
#   script patterns, disabled TLS verification, and committed secrets
#   (requirement.md Sections 27, 28, 29, 11).
# Supported OS: Linux, macOS (Bash).
# Dependencies: grep
# Parameters: none.
# Authentication: none.
# Required permissions: read access to the repository tree.
# Approval requirements: none (read-only validation).
# Dry-run: not applicable.
# API/MCP dependency: none.
# Exit codes: 0 = no violations found, 1 = one or more violations found.
# Output: human-readable PASS/FAIL list with file:line references.
# Verification: this script IS a verification step for CI.
# Audit: not audited (no mutation).
# Security: performs no network/credential access itself.
#
# Example: ./scripts/validation/validate-security.sh

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

FAILURES=0

check_pattern() {
  local label="$1" pattern="$2" glob="$3"
  local hits
  hits="$(grep -rniE --include="$glob" --exclude-dir=.git --exclude-dir=node_modules \
    --exclude="validate-security.ps1" --exclude="validate-security.sh" "$pattern" "$REPO_ROOT" || true)"
  if [[ -n "$hits" ]]; then
    echo "$hits" | while IFS= read -r line; do echo "FAIL  [$label] $line"; done
    FAILURES=$((FAILURES + 1))
  else
    echo "PASS  [$label] no occurrences found"
  fi
}

check_pattern "Invoke-Expression/iex" 'Invoke-Expression|(^|[^a-zA-Z])iex[[:space:]]' "*.ps1"
check_pattern "TLS verification disabled (PowerShell)" '\-SkipCertificateCheck' "*.ps1"
check_pattern "eval on quoted string (Bash)" 'eval[[:space:]]+["\x27]' "*.sh"
check_pattern "curl TLS verification disabled" 'curl[[:space:]]+(-k\b|--insecure)' "*.sh"

CRED_HITS="$(grep -rniE --include="*.ps1" --include="*.sh" --include="*.json" --include="*.yaml" --include="*.yml" --include="*.md" \
  --exclude-dir=.git --exclude-dir=node_modules --exclude="*.example" \
  '(password|secret|api[_-]?key)[[:space:]]*=[[:space:]]*["\x27][^"\x27]{8,}["\x27]' "$REPO_ROOT" 2>/dev/null | grep -v '/local-secrets/' || true)"

if [[ -n "$CRED_HITS" ]]; then
  echo "$CRED_HITS" | while IFS= read -r line; do echo "FAIL  [possible hardcoded credential] $line"; done
  FAILURES=$((FAILURES + 1))
else
  echo "PASS  [possible hardcoded credential] no occurrences found"
fi

for name in bitbucket-token.txt jfrog-token.txt github-token.txt; do
  path="$REPO_ROOT/.github/local-secrets/$name"
  if [[ -f "$path" ]]; then
    echo "WARN  Real local secret file present on disk (ensure it is gitignored, never committed): $path"
  fi
done

if [[ $FAILURES -gt 0 ]]; then
  echo "Security validation FAILED: $FAILURES violation(s)." >&2
  exit 1
fi

echo "Security validation PASSED."
exit 0
