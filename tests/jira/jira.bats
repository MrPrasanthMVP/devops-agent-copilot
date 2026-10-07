#!/usr/bin/env bats
# Cross-cutting regression guard for Jira Cloud (Bash side).
# Run: bats tests/jira/jira.bats

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  source "$REPO_ROOT/scripts/common/common.sh"
  rm -f "$REPO_ROOT"/logs/.approvals/op-jira-*.json "$REPO_ROOT"/logs/.approvals/op-jira-*.consumed 2>/dev/null || true
}

teardown() {
  rm -f "$REPO_ROOT"/logs/.approvals/op-jira-*.json "$REPO_ROOT"/logs/.approvals/op-jira-*.consumed 2>/dev/null || true
}

@test "classifies jira.issue.delete as DESTRUCTIVE" {
  run get_operation_classification "jira.issue.delete"
  [ "$status" -eq 0 ]
  [ "$output" = "DESTRUCTIVE" ]
}

@test "update-issue-field.sh refuses to execute without a valid approval record" {
  run "$REPO_ROOT/.github/skills/jira-issues/scripts/unix/update-issue-field.sh" \
    --site-url "https://fake.invalid" --issue-key ABC-123 --field-name priority \
    --field-value-json '{"name":"P1"}' --email tester@example.com --api-token "dummy" \
    --user tester --operation-id "op-jira-missing-1"
  [ "$status" -ne 0 ]
}

@test "an approval issued for one issue cannot authorize updating a different one" {
  op_id="op-jira-crosscheck-$$"
  new_approval_token "$op_id" "tester" "jira" "ABC-123" "jira.issue.update" "WRITE" "APPROVE UPDATE" >/dev/null
  run test_approval_token "$op_id" "jira" "ABC-124" "jira.issue.update" "APPROVE UPDATE"
  [ "$status" -ne 0 ]
}
