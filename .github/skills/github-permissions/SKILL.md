---
name: github-permissions
description: View and change GitHub repository collaborator permissions (direct user access, not via a team). Use for requests about who can read/write/admin a specific repository as an individual collaborator.
license: Proprietary - internal enterprise use
---

## Purpose

Manage individual (non-team) repository collaborator permissions.

## Scope

Direct collaborator grants. Team-based access -> `github-teams`.
Organization-wide defaults -> `github-organizations`.

## When to use

"Add jdoe as a collaborator on repo X with write access", "Who has
direct access to repo X?", "Remove jdoe's access to repo X".

## When not to use

Team-based access -> `github-teams`.

## MCP dependency

GitHub's official hosted MCP server (Cloud) or self-hosted
`github-mcp-server` (Server). Discover collaborator-management tools at
connect time.

## API fallback

GitHub REST API (`https://docs.github.com/en/rest/collaborators/collaborators`):
`GET /repos/{owner}/{repo}/collaborators`,
`PUT /repos/{owner}/{repo}/collaborators/{username}` (add/update
permission), `DELETE /repos/{owner}/{repo}/collaborators/{username}`
(remove).

## Authentication

GitHub token/GitHub App with repository admin permission.

## Read operations

List collaborators, get a user's permission level: `READ_ONLY`.

## Write operations

Add/update/remove a collaborator's permission: `SECURITY_SENSITIVE` —
always `APPROVE PERMISSION CHANGE`.

## Approval rules

Proposal shows the exact username, exact permission level
(read/triage/write/maintain/admin), current vs. proposed.

## Security

Never grants the requesting identity itself access without the same
gate as any other principal.

## Verification

Change -> `GET` the collaborator's permission -> confirm expected level
(or absence, for removal).

## Audit

Logged as `system: github`, `resource: permissions`,
`risk: SECURITY_SENSITIVE`.

## Rollback

Revert via the inverse grant/removal — reversible, requires its own
approval.

## Examples

```
User: Add jdoe as a collaborator on repo billing-service with write access.
Agent: READ current (none) -> PROPOSE (proposed: write, risk: SECURITY_SENSITIVE)
       -> APPROVE PERMISSION CHANGE -> EXECUTE -> VERIFY -> AUDIT
```
