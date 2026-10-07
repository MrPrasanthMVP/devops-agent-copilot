#!/usr/bin/env bats
# Cross-cutting regression guard for GitHub Enterprise (Bash side).
# Run: bats tests/github/github.bats

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  source "$REPO_ROOT/scripts/common/common.sh"
  rm -f "$REPO_ROOT"/logs/.approvals/op-gh-*.json "$REPO_ROOT"/logs/.approvals/op-gh-*.consumed 2>/dev/null || true
}

teardown() {
  rm -f "$REPO_ROOT"/logs/.approvals/op-gh-*.json "$REPO_ROOT"/logs/.approvals/op-gh-*.consumed 2>/dev/null || true
}

@test "classifies github.repository.delete as DESTRUCTIVE" {
  run get_operation_classification "github.repository.delete"
  [ "$status" -eq 0 ]
  [ "$output" = "DESTRUCTIVE" ]
}

@test "update-branch-protection.sh refuses to execute without a valid approval record" {
  run "$REPO_ROOT/.github/skills/github-branch-protection/scripts/unix/update-branch-protection.sh" \
    --api-base-url "https://fake.invalid" --owner org --repo repo --branch main \
    --required-approving-review-count 2 --enforce-admins true \
    --user tester --operation-id "op-gh-missing-1"
  [ "$status" -ne 0 ]
}

@test "an approval issued for one branch cannot authorize updating a different one" {
  op_id="op-gh-crosscheck-$$"
  new_approval_token "$op_id" "tester" "github" "org/repo@main" "github.branch_protection.update" "ADMINISTRATIVE" "APPROVE BRANCH PROTECTION" >/dev/null
  run test_approval_token "$op_id" "github" "org/repo@develop" "github.branch_protection.update" "APPROVE BRANCH PROTECTION"
  [ "$status" -ne 0 ]
}
