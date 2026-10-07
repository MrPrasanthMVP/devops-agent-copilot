#!/usr/bin/env bats
# Bats tests for the human-approval skill's binding guarantees.
# Run: bats .github/skills/human-approval/tests/approval_binding.bats

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../../../.." && pwd)"
  source "$REPO_ROOT/scripts/common/common.sh"
  rm -f "$REPO_ROOT"/logs/.approvals/op-test-*.json "$REPO_ROOT"/logs/.approvals/op-test-*.consumed 2>/dev/null || true
}

teardown() {
  rm -f "$REPO_ROOT"/logs/.approvals/op-test-*.json "$REPO_ROOT"/logs/.approvals/op-test-*.consumed 2>/dev/null || true
}

@test "rejects execution when no approval record exists" {
  run test_approval_token "op-test-nonexistent" "bitbucket" "ABC/TEST" "bitbucket.repository.delete" "APPROVE DELETE"
  [ "$status" -ne 0 ]
}

@test "accepts an approval that exactly matches system/target/operation" {
  op_id="op-test-match-$$"
  new_approval_token "$op_id" "tester" "bitbucket" "ABC/TEST" "bitbucket.repository.delete" "DESTRUCTIVE" "APPROVE DELETE" >/dev/null
  run test_approval_token "$op_id" "bitbucket" "ABC/TEST" "bitbucket.repository.delete" "APPROVE DELETE"
  [ "$status" -eq 0 ]
  [ "$output" = "VALID" ]
}

@test "rejects an approval presented against a DIFFERENT target" {
  op_id="op-test-crosstarget-$$"
  new_approval_token "$op_id" "tester" "jfrog" "releases-local/app/A.jar" "jfrog.artifact.delete" "DESTRUCTIVE" "APPROVE DELETE" >/dev/null
  run test_approval_token "$op_id" "jfrog" "releases-local/app/B.jar" "jfrog.artifact.delete" "APPROVE DELETE"
  [ "$status" -ne 0 ]
}

@test "rejects a consumed approval on reuse" {
  op_id="op-test-reuse-$$"
  new_approval_token "$op_id" "tester" "github" "org/repo" "github.repository.delete" "DESTRUCTIVE" "APPROVE DELETE" >/dev/null
  set_approval_consumed "$op_id"
  run test_approval_token "$op_id" "github" "org/repo" "github.repository.delete" "APPROVE DELETE"
  [ "$status" -ne 0 ]
}
