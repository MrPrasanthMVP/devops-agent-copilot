---
name: jira-permissions
description: View and change Jira Cloud project permission schemes and permission grants. Use for requests about who can do what in a Jira project (browse/create/edit/admin permissions).
license: Proprietary - internal enterprise use
---

## Purpose

Inspect and change Jira Cloud project permission schemes.

## Scope

Permission-scheme grants only. Individual issue security levels, if
used, are treated the same way (security-sensitive) but are a distinct
Jira concept from project permission schemes — this Skill covers both
under the same approval rule since both gate "who can do what."

## When to use

"Who can edit issues in project X?", "Grant group Y the 'Administer
Projects' permission in project X".

## When not to use

Issue field edits -> `jira-issues`. Workflow transition conditions ->
`jira-workflows`.

## MCP dependency

Official Atlassian Rovo MCP Server — permission-scheme tools resolved via
`discover` at call time.

## API fallback

Jira Cloud REST API v3: `GET /rest/api/3/permissionscheme`,
`GET /rest/api/3/permissionscheme/{schemeId}`,
`POST /rest/api/3/permissionscheme/{schemeId}/permission` (add grant),
`DELETE /rest/api/3/permissionscheme/{schemeId}/permission/{permissionId}`.

## Authentication

Rovo MCP: OAuth 2.1. REST fallback: shared Atlassian site credential.

## Read operations

List/get scheme and grants: `READ_ONLY`.

## Write operations

Add/remove a permission grant: `SECURITY_SENSITIVE` — always
`APPROVE PERMISSION CHANGE`.

## Approval rules

Proposal shows the exact principal (user/group/role), the exact
permission key, and current vs. proposed state.

## Security

Never grants a permission to the requesting user/agent identity itself
without the same approval gate as any other principal.

## Verification

Add/remove -> `GET` the scheme -> confirm the grant is present/absent.

## Audit

Logged as `system: jira`, `resource: permissions`, `risk: SECURITY_SENSITIVE`.

## Rollback

Revert via the inverse grant/removal — reversible, requires its own
approval.

## Examples

```
User: Grant group jira-admins the Administer Projects permission in project PAY.
Agent: READ current grants -> PROPOSE (risk: SECURITY_SENSITIVE) ->
       APPROVE PERMISSION CHANGE -> EXECUTE -> VERIFY -> AUDIT
```
