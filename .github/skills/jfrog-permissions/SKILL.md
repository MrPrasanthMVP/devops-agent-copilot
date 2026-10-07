---
name: jfrog-permissions
description: View and change JFrog Artifactory permission targets (which users/groups can read/write/delete/manage in which repositories). Use for requests about JFrog access control.
license: Proprietary - internal enterprise use
---

## Purpose

Inspect and change Artifactory permission targets.

## Scope

Permission-target grants only. User/group existence -> `jfrog-users` /
`jfrog-groups`.

## When to use

"Who can write to releases-local?", "Grant group build-team write access
to releases-local".

## When not to use

Creating the user/group itself -> `jfrog-users`/`jfrog-groups`.

## MCP dependency

Official JFrog MCP Server. The verified v0.442 tool catalog
(`policies/system-policy.yaml`) does **not** include a permission-target
CRUD tool — `access_projects_*` tools manage JFrog Access *project*
roles, which is a related but distinct concept from classic Artifactory
permission targets. Route permission-target changes through the REST
fallback unless a newer MCP catalog on your deployment proves otherwise
at discovery time.

## API fallback

JFrog Access/Artifactory REST API — permission targets:
`GET /artifactory/api/v2/security/permissions`,
`GET /artifactory/api/v2/security/permissions/{permissionTargetName}`,
`PUT /artifactory/api/v2/security/permissions/{permissionTargetName}`
(create/update), `DELETE .../{permissionTargetName}`.

## Authentication

JFrog access token with Artifactory admin permission.

## Read operations

List/get permission target: `READ_ONLY`.

## Write operations

Create/update/delete a permission target, or change its
principal/permission grants: `SECURITY_SENSITIVE` — always
`APPROVE PERMISSION CHANGE`.

## Approval rules

Proposal shows the exact principal (user/group), exact repository
scope, exact permissions (read/write/annotate/delete/manage), current
vs. proposed.

## Security

Never grants the requesting identity itself a permission without the
same gate.

## Verification

Change -> `GET` the permission target -> confirm expected grants.

## Audit

Logged as `system: jfrog`, `resource: permissions`,
`risk: SECURITY_SENSITIVE`.

## Rollback

Revert via inverse grant — reversible, requires its own approval.

## Examples

```
User: Grant group build-team write access to releases-local.
Agent: READ current permission target -> PROPOSE (risk: SECURITY_SENSITIVE)
       -> APPROVE PERMISSION CHANGE -> EXECUTE -> VERIFY -> AUDIT
```
