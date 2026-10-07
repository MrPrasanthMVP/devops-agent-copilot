---
name: jfrog-users
description: View, create, update, and delete JFrog Artifactory local users. Use for requests about JFrog user accounts (not permissions/groups).
license: Proprietary - internal enterprise use
---

## Purpose

Manage Artifactory local user account lifecycle.

## Scope

User accounts only. Access grants -> `jfrog-permissions`. Group
membership structure -> `jfrog-groups`.

## When to use

"Create a JFrog user for jdoe", "List JFrog users", "Delete user jdoe".

## When not to use

Permission grants -> `jfrog-permissions`.

## MCP dependency

Official JFrog MCP Server. The verified v0.442 tool catalog does not
include a user-CRUD tool (the `access_*` tools cover tokens/OIDC/
projects/roles, not classic local users) — route through the REST
fallback unless discovery proves otherwise on your deployment.

## API fallback

JFrog Artifactory REST API: `GET /artifactory/api/security/users`,
`GET /artifactory/api/security/users/{userName}`,
`PUT /artifactory/api/security/users/{userName}` (create/update),
`DELETE /artifactory/api/security/users/{userName}`.

## Authentication

JFrog access token with Artifactory admin permission.

## Read operations

List/get user: `READ_ONLY` (password hashes/tokens are never surfaced —
treated as credentials even if the API technically returns metadata
about them).

## Write operations

- `CREATE user`: `ADMINISTRATIVE`.
- `UPDATE user` (e.g. email, admin flag): `SECURITY_SENSITIVE` if it
  touches admin/privilege flags, otherwise `ADMINISTRATIVE`.
- `DELETE user`: `DESTRUCTIVE` — requires `APPROVE DELETE`.

## Approval rules

Standard `human-approval` flow. Any change to the `admin` flag on a user
is always treated as `SECURITY_SENSITIVE` regardless of direction (grant
or revoke).

## Security

New user creation never sets or displays a password in chat/logs; if the
underlying API requires an initial password, it is generated
server-side or via a secure random generator and communicated only
through an out-of-band channel the human specifies — never echoed by the
agent.

## Verification

CREATE/UPDATE -> GET -> compare (excluding credential fields). DELETE ->
GET -> expect 404.

## Audit

Logged as `system: jfrog`, `resource: user`, with the username as
`target` (never password/token fields).

## Rollback

CREATE/UPDATE: reversible. DELETE: **NOT GUARANTEED**.

## Examples

```
User: Delete JFrog user jdoe.
Agent: PROPOSE (DESTRUCTIVE) -> APPROVE DELETE -> EXECUTE -> VERIFY -> AUDIT
```
