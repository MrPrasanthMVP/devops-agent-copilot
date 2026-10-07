---
name: github-organizations
description: View and change GitHub organization-level settings (membership defaults, default repository permission, base permissions). Use for org-wide (not enterprise-wide, not single-repo) GitHub administration.
license: Proprietary - internal enterprise use
---

## Purpose

Organization-level GitHub administration.

## Scope

Single-organization settings. Enterprise-wide -> `github-enterprise-admin`.
Repository-level -> `github-repositories`. Team structure ->
`github-teams`.

## When to use

"What's the default repository permission for org X?", "Change org X's
default member permission to read".

## When not to use

Enterprise-wide or repo-scoped requests -> the dedicated Skill.

## MCP dependency

GitHub's official hosted MCP server (Cloud) or self-hosted
`github-mcp-server` (Server). Discover organization-admin tools at
connect time.

## API fallback

GitHub REST API (`https://docs.github.com/en/rest/orgs/orgs`):
`GET /orgs/{org}`, `PATCH /orgs/{org}` (default_repository_permission,
members_can_create_repositories, etc.).

## Authentication

GitHub token/GitHub App with organization admin scope.

## Read operations

Get organization settings: `READ_ONLY`.

## Write operations

Change organization settings: `ADMINISTRATIVE`, except changes that
broaden default member permissions (e.g. default_repository_permission
read -> write) which are `SECURITY_SENSITIVE`.

## Approval rules

Standard `human-approval` flow; proposal shows current vs. proposed
value for the exact setting.

## Security

No credential exposure; gated due to org-wide governance impact.

## Verification

Update -> GET -> compare.

## Audit

Logged as `system: github`, `resource: organization`.

## Rollback

Revert to the previously-read value — reversible, requires its own
approval.

## Examples

```
User: Change org "my-org"'s default repository permission to read.
Agent: READ current (write) -> PROPOSE (proposed: read, risk: SECURITY_SENSITIVE)
       -> APPROVE PERMISSION CHANGE -> EXECUTE -> VERIFY -> AUDIT
```
