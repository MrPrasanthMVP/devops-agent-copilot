---
name: jfrog-projects
description: View, create, update, and delete JFrog Platform Projects (the Access-level grouping of repositories/users/roles, distinct from Artifactory repositories). Use for requests about JFrog "Projects" as an organizational unit.
license: Proprietary - internal enterprise use
---

## Purpose

Manage JFrog Platform Projects lifecycle (JFrog Access's project
construct — resource grouping, roles, and repository assignment).

## Scope

Project-level JFrog Access operations. Repository configuration itself
-> `jfrog-repositories`.

## When to use

"Create a JFrog project called 'payments'", "List JFrog projects",
"Move repository X into project Y", "Delete JFrog project Y".

## When not to use

Repository configuration details -> `jfrog-repositories`.

## MCP dependency

Official JFrog MCP Server. Verified v0.442 tool catalog
(`policies/system-policy.yaml`) includes
`access_projects_create`, `access_projects_get`, `access_projects_update`,
`access_projects_create_role`, `access_projects_update_role`,
`access_projects_get_user`, `access_projects_upsert_user`,
`access_projects_list_groups`, `access_projects_upsert_group`,
`access_projects_get_repository`,
`access_projects_move_repository_to_project`,
`access_projects_share_repository_with_all`,
`access_projects_list_projects` — these ARE documented, real MCP tools
for this capability. Still re-discover at connect time per Section 23 to
confirm availability for your deployed server version. No project-delete
tool was found in this catalog version — route delete through the REST
fallback.

## API fallback

JFrog Access REST API: `GET /access/api/v1/projects`,
`GET /access/api/v1/projects/{projectKey}`,
`POST /access/api/v1/projects` (create),
`PUT /access/api/v1/projects/{projectKey}` (update),
`DELETE /access/api/v1/projects/{projectKey}` (delete).

Scripts: `scripts/windows/delete-project.ps1` /
`scripts/unix/delete-project.sh` (DESTRUCTIVE — the only operation on
this Skill confirmed absent from the MCP tool catalog; the
create/update/role/upsert operations above are MCP-covered per the
verified tool list, so no separate fallback script exists for those
yet).

## Authentication

JFrog access token with appropriate Access admin permission.

## Read operations

List/get project, list project users/groups/repositories: `READ_ONLY`.

## Write operations

- `CREATE project`: `ADMINISTRATIVE`.
- `UPDATE project` (roles, user/group upsert, repository
  move/share): `ADMINISTRATIVE`, except user/group permission upserts
  which are `SECURITY_SENSITIVE`.
- `DELETE project`: `DESTRUCTIVE` — requires `APPROVE DELETE`; proposal
  must list repositories currently assigned to the project.

## Approval rules

Standard `human-approval` flow with the matching phrase per operation
type.

## Security

Project keys validated for shape; user/group upserts into a project
follow the same "never grant the requesting identity itself" rule as
`jfrog-permissions`.

## Verification

CREATE/UPDATE -> GET -> compare. DELETE -> GET -> expect 404.

## Audit

Logged as `system: jfrog`, `resource: project`.

## Rollback

CREATE/UPDATE: reversible. DELETE: **NOT GUARANTEED**.

## Examples

```
User: Move repository releases-local into JFrog project "payments".
Agent: READ current assignment -> PROPOSE (risk: ADMINISTRATIVE) ->
       APPROVE ADMIN CHANGE -> EXECUTE (access_projects_move_repository_to_project)
       -> VERIFY -> AUDIT
```
