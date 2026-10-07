---
name: github-teams
description: Create, read, update, and delete GitHub organization teams, and manage team membership and team-to-repository access. Use for requests about GitHub team structure or membership.
license: Proprietary - internal enterprise use
---

## Purpose

Manage GitHub team lifecycle, membership, and repository access grants.

## Scope

Team CRUD, membership, and team-repo permission grants. Individual
collaborator (non-team) permissions -> `github-permissions`.

## When to use

"Create a team called 'platform'", "Add jdoe to team platform", "Grant
team platform write access to repo X".

## When not to use

Individual collaborator grants not via a team -> `github-permissions`.

## MCP dependency

GitHub's official hosted MCP server (Cloud) or self-hosted
`github-mcp-server` (Server). Discover team-management tools at connect
time.

## API fallback

GitHub REST API (`https://docs.github.com/en/rest/teams/teams`,
`https://docs.github.com/en/rest/teams/members`):
`GET /orgs/{org}/teams`, `POST /orgs/{org}/teams`,
`PATCH /orgs/{org}/teams/{team_slug}`,
`DELETE /orgs/{org}/teams/{team_slug}`,
`PUT /orgs/{org}/teams/{team_slug}/memberships/{username}`,
`PUT /orgs/{org}/teams/{team_slug}/repos/{owner}/{repo}` (grant repo access).

## Authentication

GitHub token/GitHub App with organization admin scope (or team
maintainer for membership changes within that team).

## Read operations

List/get team, list members, list team repos: `READ_ONLY`.

## Write operations

- `CREATE/UPDATE team`: `ADMINISTRATIVE`.
- `DELETE team`: `DESTRUCTIVE` — requires `APPROVE DELETE`; proposal
  lists affected members and repository access grants that will be
  removed.
- `ADD/REMOVE member`, `GRANT/REVOKE team repo access`:
  `SECURITY_SENSITIVE`.

## Approval rules

Standard `human-approval` flow with the matching phrase per operation.

## Security

Never adds the requesting identity itself to a team or grants it repo
access without the same approval gate as any other principal.

## Verification

CREATE/UPDATE/membership/access change -> GET -> compare. DELETE -> GET
-> expect 404.

## Audit

Logged as `system: github`, `resource: team`.

## Rollback

CREATE/UPDATE/membership/access: reversible. DELETE: **NOT GUARANTEED**
(team structure/history is not restorable via a simple inverse call).

## Examples

```
User: Grant team platform write access to repo billing-service.
Agent: READ current access -> PROPOSE (risk: SECURITY_SENSITIVE) ->
       APPROVE PERMISSION CHANGE -> EXECUTE -> VERIFY -> AUDIT
```
