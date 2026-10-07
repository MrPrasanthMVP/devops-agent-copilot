---
name: jfrog-groups
description: View, create, update, and delete JFrog Artifactory groups, and manage user membership within them. Use for requests about JFrog group structure (not permission grants themselves).
license: Proprietary - internal enterprise use
---

## Purpose

Manage Artifactory group lifecycle and membership.

## Scope

Group CRUD and membership. Permission grants to a group ->
`jfrog-permissions`.

## When to use

"Create a JFrog group called build-team", "Add jdoe to group build-team",
"Delete group build-team".

## When not to use

Granting the group access to a repository -> `jfrog-permissions`.

## MCP dependency

Official JFrog MCP Server. No group-CRUD tool found in the verified
v0.442 catalog — route through REST fallback unless discovery proves
otherwise.

## API fallback

JFrog Access REST API: `GET /access/api/v2/groups/{group_name}` (read),
`PUT /access/api/v2/groups/{group_name}` (create/update),
`DELETE /access/api/v2/groups/{group_name}` (delete). Membership is
managed via the user's `groups` array
(`GET` then `PATCH /access/api/v2/users/{username}`), consistent with
`jfrog-users`' use of the same Access API v2 user endpoints.

Scripts: `scripts/windows/get-group.ps1` / `scripts/unix/get-group.sh`
(READ_ONLY), `scripts/windows/create-group.ps1` /
`scripts/unix/create-group.sh` (ADMINISTRATIVE, create/replace),
`scripts/windows/delete-group.ps1` / `scripts/unix/delete-group.sh`
(DESTRUCTIVE), `scripts/windows/add-group-member.ps1` /
`scripts/unix/add-group-member.sh` (SECURITY_SENSITIVE).

## Authentication

JFrog access token with Artifactory admin permission.

## Read operations

List/get group, list members: `READ_ONLY`.

## Write operations

- `CREATE/UPDATE group`: `ADMINISTRATIVE`.
- `DELETE group`: `DESTRUCTIVE` — any permission targets referencing the
  group are affected; requires `APPROVE DELETE` and the proposal must
  list affected permission targets.
- `ADD/REMOVE member`: `SECURITY_SENSITIVE` (changes effective access for
  that user via whatever the group is granted).

## Approval rules

Standard `human-approval` flow with the matching phrase per operation.

## Security

Membership changes validated against the actual user existing first
(no silent no-op that looks like success).

## Verification

CREATE/UPDATE/membership change -> GET -> compare. DELETE -> GET ->
expect 404.

## Audit

Logged as `system: jfrog`, `resource: group`.

## Rollback

CREATE/UPDATE/membership: reversible. DELETE: **NOT GUARANTEED**
(permission targets referencing the deleted group may need manual
review).

## Examples

```
User: Add jdoe to group build-team.
Agent: READ current membership -> PROPOSE (risk: SECURITY_SENSITIVE) ->
       APPROVE PERMISSION CHANGE -> EXECUTE -> VERIFY -> AUDIT
```
