---
name: github-branches
description: List, create, rename, and delete GitHub repository branches (the branches themselves, not protection rules). Use for requests about branch existence/lifecycle.
license: Proprietary - internal enterprise use
---

## Purpose

Manage branch existence lifecycle (distinct from branch protection
rules).

## Scope

Branch create/rename/delete. Protection configuration ->
`github-branch-protection`. Ruleset configuration -> `github-rulesets`.

## When to use

"List branches in repo X", "Create branch feature/y from main", "Delete
branch old-feature".

## When not to use

Protection/ruleset configuration -> the dedicated Skills.

## MCP dependency

GitHub's official hosted MCP server (Cloud) or self-hosted
`github-mcp-server` (Server). Discover branch-management tools at
connect time.

## API fallback

GitHub REST API (`https://docs.github.com/en/rest/branches/branches`,
`https://docs.github.com/en/rest/git/refs`):
`GET /repos/{owner}/{repo}/branches`,
`POST /repos/{owner}/{repo}/git/refs` (create, `ref: refs/heads/{name}`),
`DELETE /repos/{owner}/{repo}/git/refs/heads/{branch}` (delete).

## Authentication

GitHub token with repository write permission.

## Read operations

List branches: `READ_ONLY`.

## Write operations

- `CREATE branch`: `WRITE`.
- `DELETE branch`: `DESTRUCTIVE` — requires `APPROVE DELETE`; if the
  branch is protected, the API itself rejects the delete and the agent
  reports this rather than attempting a workaround.

## Approval rules

Standard `human-approval` flow. Deleting a branch with unmerged commits
is flagged explicitly in the proposal (commit count ahead of the base
branch), since those commits become unreachable (though not immediately
garbage-collected) once the ref is deleted.

## Security

Branch names validated for shape; no shell/URL injection.

## Verification

CREATE -> GET branch -> confirm existence and SHA. DELETE -> GET -> expect 404.

## Audit

Logged as `system: github`, `resource: branch`.

## Rollback

CREATE: delete it (own DESTRUCTIVE approval). DELETE: recreate the ref at
the last-known SHA if it was captured before deletion and the underlying
commit is still reachable (e.g. via another branch/tag) — otherwise
**NOT GUARANTEED**.

## Examples

```
User: Delete branch old-feature in repo XYZ.
Agent: READ (commits ahead: 3, unmerged) -> PROPOSE (DESTRUCTIVE, impact noted)
       -> APPROVE DELETE -> EXECUTE -> VERIFY (404) -> AUDIT
```
