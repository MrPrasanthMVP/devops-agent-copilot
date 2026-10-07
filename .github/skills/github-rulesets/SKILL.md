---
name: github-rulesets
description: View and change GitHub repository or organization rulesets (the modern alternative/complement to classic branch protection -- push rules, required workflows, tag protection, bypass lists). Use for requests mentioning "rulesets" explicitly, or for governance needs classic branch protection cannot express.
license: Proprietary - internal enterprise use
---

## Purpose

Manage GitHub Rulesets at repository or organization scope.

## Scope

Ruleset CRUD. Classic branch protection -> `github-branch-protection`
(the two mechanisms can coexist; this Skill does not assume one replaces
the other for a given repository without checking).

## When to use

"Show rulesets for repo X", "Create a ruleset requiring linear history on
main", "Add a bypass actor to ruleset Y".

## When not to use

If the repository/org is confirmed to use only classic branch protection
-> `github-branch-protection`.

## MCP dependency

GitHub's official hosted MCP server (Cloud) or self-hosted
`github-mcp-server` (Server). Discover ruleset-management tools at
connect time.

## API fallback

GitHub REST API (`https://docs.github.com/en/rest/repos/rules`,
`https://docs.github.com/en/rest/orgs/rules`):
`GET /repos/{owner}/{repo}/rulesets`,
`GET /repos/{owner}/{repo}/rulesets/{ruleset_id}`,
`POST /repos/{owner}/{repo}/rulesets` (create),
`PUT /repos/{owner}/{repo}/rulesets/{ruleset_id}` (update),
`DELETE /repos/{owner}/{repo}/rulesets/{ruleset_id}` (delete). Org-level
equivalents exist under `/orgs/{org}/rulesets`.

## Authentication

GitHub token/GitHub App with repository or organization admin permission
as appropriate to the ruleset's scope.

## Read operations

List/get ruleset: `READ_ONLY`.

## Write operations

- `CREATE/UPDATE ruleset`: `ADMINISTRATIVE`.
- `DELETE ruleset`: `DESTRUCTIVE` — requires `APPROVE DELETE`.
- Any ruleset change that adds a **bypass actor** (an identity/team that
  can bypass the rule) is `SECURITY_SENSITIVE` regardless of the rest of
  the change, since it creates an exception to governance.

## Approval rules

Standard `human-approval` flow with the matching phrase; bypass-actor
changes always escalate to `APPROVE PERMISSION CHANGE` in addition to
whatever phrase the base operation would otherwise need.

## Security

Ruleset target patterns (branch/tag name patterns) validated for shape.

## Verification

CREATE/UPDATE -> GET -> compare full ruleset object (rulesets, like
classic protection, can be a full-object API — verify current
documentation for PATCH vs. PUT semantics before assuming either).
DELETE -> GET -> expect 404.

## Audit

Logged as `system: github`, `resource: ruleset`.

## Rollback

CREATE/UPDATE: reversible via inverse operation. DELETE: **NOT
GUARANTEED** unless the prior full ruleset definition was captured
before deletion (then recreatable as a new approved CREATE).

## Examples

```
User: Create a ruleset requiring linear history on main in repo XYZ.
Agent: PROPOSE (ADMINISTRATIVE) -> APPROVE ADMIN CHANGE -> EXECUTE -> VERIFY -> AUDIT
```
