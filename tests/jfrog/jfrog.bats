#!/usr/bin/env bats
# Cross-cutting regression guard for JFrog Artifactory (Bash side).
# Run: bats tests/jfrog/jfrog.bats

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  source "$REPO_ROOT/scripts/common/common.sh"
  rm -f "$REPO_ROOT"/logs/.approvals/op-jfrog-*.json "$REPO_ROOT"/logs/.approvals/op-jfrog-*.consumed 2>/dev/null || true
}

teardown() {
  rm -f "$REPO_ROOT"/logs/.approvals/op-jfrog-*.json "$REPO_ROOT"/logs/.approvals/op-jfrog-*.consumed 2>/dev/null || true
}

@test "classifies jfrog.artifact.delete as DESTRUCTIVE" {
  run get_operation_classification "jfrog.artifact.delete"
  [ "$status" -eq 0 ]
  [ "$output" = "DESTRUCTIVE" ]
}

@test "jfrog-cleanup delete-artifacts.sh refuses to execute without a valid approval record" {
  run "$REPO_ROOT/.github/skills/jfrog-cleanup/scripts/unix/delete-artifacts.sh" \
    --base-url "https://fake.invalid" --repository releases-local --candidate-path "a/b.jar" \
    --user tester --operation-id "op-jfrog-missing-1"
  [ "$status" -ne 0 ]
}

@test "jfrog-repositories delete-repository.sh refuses to execute without a valid approval record" {
  run "$REPO_ROOT/.github/skills/jfrog-repositories/scripts/unix/delete-repository.sh" \
    --base-url "https://fake.invalid" --repo-key old-unused-local \
    --user tester --operation-id "op-jfrog-missing-2"
  [ "$status" -ne 0 ]
}

@test "an approval issued for one repository cannot authorize a delete in a different one" {
  op_id="op-jfrog-crosscheck-$$"
  new_approval_token "$op_id" "tester" "jfrog" "releases-local" "jfrog.artifact.delete" "DESTRUCTIVE" "APPROVE DELETE" >/dev/null
  run test_approval_token "$op_id" "jfrog" "other-repo-local" "jfrog.artifact.delete" "APPROVE DELETE"
  [ "$status" -ne 0 ]
}
