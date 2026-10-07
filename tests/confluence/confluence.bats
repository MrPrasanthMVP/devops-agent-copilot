#!/usr/bin/env bats
# Cross-cutting regression guard for Confluence Cloud (Bash side).
# Run: bats tests/confluence/confluence.bats

setup() {
  REPO_ROOT="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  source "$REPO_ROOT/scripts/common/common.sh"
  rm -f "$REPO_ROOT"/logs/.approvals/op-conf-*.json "$REPO_ROOT"/logs/.approvals/op-conf-*.consumed 2>/dev/null || true
}

teardown() {
  rm -f "$REPO_ROOT"/logs/.approvals/op-conf-*.json "$REPO_ROOT"/logs/.approvals/op-conf-*.consumed 2>/dev/null || true
}

@test "classifies confluence.permissions.update as SECURITY_SENSITIVE" {
  run get_operation_classification "confluence.permissions.update"
  [ "$status" -eq 0 ]
  [ "$output" = "SECURITY_SENSITIVE" ]
}

@test "update-page.sh refuses to execute without a valid approval record" {
  run "$REPO_ROOT/.github/skills/confluence-pages/scripts/unix/update-page.sh" \
    --site-url "https://fake.invalid" --page-id 123456 --current-version 4 \
    --title "Test Page" --body-storage-value "<p>new</p>" --email tester@example.com \
    --api-token "dummy" --user tester --operation-id "op-conf-missing-1"
  [ "$status" -ne 0 ]
}

@test "an approval issued for one page cannot authorize updating a different one" {
  op_id="op-conf-crosscheck-$$"
  new_approval_token "$op_id" "tester" "confluence" "123456" "confluence.page.update" "WRITE" "APPROVE UPDATE" >/dev/null
  run test_approval_token "$op_id" "confluence" "999999" "confluence.page.update" "APPROVE UPDATE"
  [ "$status" -ne 0 ]
}
