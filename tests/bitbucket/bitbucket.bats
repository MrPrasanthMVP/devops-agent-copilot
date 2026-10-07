#!/usr/bin/env bats
# Cross-cutting regression guard for Bitbucket Data Center (Bash side).
# Run: bats tests/bitbucket/bitbucket.bats

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  source "$REPO_ROOT/scripts/common/common.sh"
  rm -f "$REPO_ROOT"/logs/.approvals/op-bb-*.json "$REPO_ROOT"/logs/.approvals/op-bb-*.consumed 2>/dev/null || true
}

teardown() {
  rm -f "$REPO_ROOT"/logs/.approvals/op-bb-*.json "$REPO_ROOT"/logs/.approvals/op-bb-*.consumed 2>/dev/null || true
}

@test "classifies bitbucket.repository.delete as DESTRUCTIVE" {
  run get_operation_classification "bitbucket.repository.delete"
  [ "$status" -eq 0 ]
  [ "$output" = "DESTRUCTIVE" ]
}

@test "delete-repository.sh refuses to execute without a valid approval record" {
  run "$REPO_ROOT/.github/skills/bitbucket-repository-admin/scripts/unix/delete-repository.sh" \
    --base-url "https://fake.invalid" --project-key ABC --repository-slug TEST \
    --user tester --operation-id "op-bb-missing-1"
  [ "$status" -ne 0 ]
}

@test "merge-pull-request.sh refuses to execute without a valid approval record" {
  run "$REPO_ROOT/.github/skills/bitbucket-pull-requests/scripts/unix/merge-pull-request.sh" \
    --base-url "https://fake.invalid" --project-key ABC --repository-slug app \
    --pull-request-id 42 --version 1 --user tester --operation-id "op-bb-missing-2"
  [ "$status" -ne 0 ]
}

@test "an approval issued for one repository cannot authorize deletion of a different one" {
  op_id="op-bb-crosscheck-$$"
  new_approval_token "$op_id" "tester" "bitbucket" "ABC/REPO-A" "bitbucket.repository.delete" "DESTRUCTIVE" "APPROVE DELETE" >/dev/null
  run test_approval_token "$op_id" "bitbucket" "ABC/REPO-B" "bitbucket.repository.delete" "APPROVE DELETE"
  [ "$status" -ne 0 ]
}
