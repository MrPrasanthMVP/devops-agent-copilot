---
name: bitbucket-permissions
description: View and change Bitbucket Data Center project- and repository-level permissions (user/group grants of PROJECT_READ/WRITE/ADMIN, REPO_READ/WRITE/ADMIN). Use for any request to grant, change, or revoke Bitbucket access.
license: Proprietary - internal enterprise use
---

## Purpose

Inspect and change who can read/write/administer Bitbucket projects and
repositories.

## Scope

User/group permission grants at project and repository scope. Branch-level
restrictions (who can push to `main`) -> `bitbucket-branch-permissions`.

## When to use

"Who has access to repository X?", "Grant user jdoe write access to
project ABC", "Remove group dev-team from repository XYZ".

## When not to use

Branch restriction rules -> `bitbucket-branch-permissions`. Merge-check
configuration -> `bitbucket-merge-checks`.

## MCP dependency

Official "MCP for Bitbucket DC" — discover permission-related tools at
connect time. The server's own documentation notes tool availability is
whitelisted per the caller's REST permissions, so a lower-privileged
caller may see fewer permission-management tools than an admin caller.

## API fallback

- `GET /rest/api/1.0/projects/{projectKey}/permissions/users` /
  `.../groups` — list grants
- `PUT /rest/api/1.0/projects/{projectKey}/permissions/users?name=&permission=` — grant/change (project)
- `DELETE /rest/api/1.0/projects/{projectKey}/permissions/users?name=` — revoke (project)
- `PUT` / `DELETE` equivalents under
  `/rest/api/1.0/projects/{projectKey}/repos/{repositorySlug}/permissions/users|groups`
  for repository-level grants.

Reference: `https://developer.atlassian.com/server/bitbucket/rest/`.

## Authentication

Bitbucket HTTP access token with admin permission on the target
project/repository.

## Read operations

List current grants: `READ_ONLY`.

## Write operations

Grant/change/revoke any user or group permission: `SECURITY_SENSITIVE` —
always requires `APPROVE PERMISSION CHANGE`.

## Approval rules

The PROPOSED OPERATION must show the exact current permission (or "none")
and the exact proposed permission for the named principal, never a vague
summary. `APPROVE PERMISSION CHANGE` is required even for what looks like
a downgrade (e.g. ADMIN -> WRITE) — any permission change is security
sensitive.

## Security

Principal names (users/groups) are validated and passed as query
parameters, never concatenated into a shell command. No privilege
escalation shortcut: the agent never grants a permission to itself or to
the requesting user without the same approval gate applied to any other
principal.

## Verification

After any grant/revoke, re-`GET` the permissions list and confirm the
named principal now has exactly the proposed permission (or is absent, for
revoke).

## Audit

Logged as `resource: permissions`, `risk: SECURITY_SENSITIVE`, including
the principal name but never any credential.

## Rollback

Revert to the previously-read permission value — reversible as another
approved `SECURITY_SENSITIVE` change, not automatic.

## Examples

```
User: Grant user jdoe write access to repository XYZ in project ABC.
Agent: READ current grant (none) -> PROPOSE (current: none, proposed: REPO_WRITE,
       risk: SECURITY_SENSITIVE) -> APPROVE PERMISSION CHANGE -> EXECUTE ->
       VERIFY -> AUDIT
```
