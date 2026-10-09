#!/usr/bin/env bats
# Cross-cutting regression guard for SonarQube (Server + Cloud, Bash side).
# Run: bats tests/sonarqube/sonarqube.bats

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  source "$REPO_ROOT/scripts/common/common.sh"
  rm -f "$REPO_ROOT"/logs/.approvals/op-sonarqube-*.json "$REPO_ROOT"/logs/.approvals/op-sonarqube-*.consumed 2>/dev/null || true
}

teardown() {
  rm -f "$REPO_ROOT"/logs/.approvals/op-sonarqube-*.json "$REPO_ROOT"/logs/.approvals/op-sonarqube-*.consumed 2>/dev/null || true
}

@test "classifies sonarqube.project.delete as DESTRUCTIVE" {
  run get_operation_classification "sonarqube.project.delete"
  [ "$status" -eq 0 ]
  [ "$output" = "DESTRUCTIVE" ]
}

@test "classifies sonarqube.project.create as WRITE" {
  run get_operation_classification "sonarqube.project.create"
  [ "$status" -eq 0 ]
  [ "$output" = "WRITE" ]
}

@test "classifies sonarqube.issue.transition as WRITE" {
  run get_operation_classification "sonarqube.issue.transition"
  [ "$status" -eq 0 ]
  [ "$output" = "WRITE" ]
}

@test "build_form_body URL-encodes values and omits empty ones" {
  run build_form_body issue "AbCd 1234" transition "resolve" assignee ""
  [ "$status" -eq 0 ]
  [ "$output" = "issue=AbCd%201234&transition=resolve" ]
}

@test "sonarqube-projects create-project.sh refuses to execute without a valid approval record" {
  run "$REPO_ROOT/.github/skills/sonarqube-projects/scripts/unix/create-project.sh" \
    --base-url "https://fake.invalid" --project-key test-proj --project-name "Test Project" \
    --user tester --operation-id "op-sonarqube-missing-1"
  [ "$status" -ne 0 ]
}

@test "sonarqube-projects delete-project.sh refuses to execute without a valid approval record" {
  run "$REPO_ROOT/.github/skills/sonarqube-projects/scripts/unix/delete-project.sh" \
    --base-url "https://fake.invalid" --project-key test-proj \
    --user tester --operation-id "op-sonarqube-missing-2"
  [ "$status" -ne 0 ]
}

@test "sonarqube-issues transition-issue.sh refuses to execute without a valid approval record" {
  run "$REPO_ROOT/.github/skills/sonarqube-issues/scripts/unix/transition-issue.sh" \
    --base-url "https://fake.invalid" --issue-key AbCd1234 --transition resolve \
    --user tester --operation-id "op-sonarqube-missing-3"
  [ "$status" -ne 0 ]
}

@test "sonarqube-webhooks delete-webhook.sh refuses to execute without a valid approval record" {
  run "$REPO_ROOT/.github/skills/sonarqube-webhooks/scripts/unix/delete-webhook.sh" \
    --base-url "https://fake.invalid" --webhook-key AbCd1234 \
    --user tester --operation-id "op-sonarqube-missing-4"
  [ "$status" -ne 0 ]
}

@test "an approval issued for one project cannot authorize a delete in a different one" {
  op_id="op-sonarqube-crosscheck-$$"
  new_approval_token "$op_id" "tester" "sonarqube" "project-a" "sonarqube.project.delete" "DESTRUCTIVE" "APPROVE DELETE" >/dev/null
  run test_approval_token "$op_id" "sonarqube" "project-b" "sonarqube.project.delete" "APPROVE DELETE"
  [ "$status" -ne 0 ]
}
