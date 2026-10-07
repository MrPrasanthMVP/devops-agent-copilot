---
name: bitbucket-project-admin
description: Create, read, update, and delete Bitbucket Data Center 9.4.5 projects. Use for requests about creating, renaming, or deleting a Bitbucket project, or listing/inspecting project-level settings.
license: Proprietary - internal enterprise use
---

## Purpose

Manage Bitbucket Data Center project lifecycle (the container above
repositories).

## Scope

Project-level only. Repository lifecycle -> `bitbucket-repository-admin`.
Project-level permissions -> `bitbucket-permissions`.

## When to use

"List Bitbucket projects", "Create project X", "Rename project X",
"Delete project X".

## When not to use

Repository-, branch-, or PR-level requests.

## MCP dependency

Official "MCP for Bitbucket DC" — discover tools for project
list/get/create/update/delete at connect time (Section 23). Do not
assume a specific tool name.

## API fallback

Bitbucket Server/Data Center REST API 1.0 (9.4.5 — not 10.x):

- `GET /rest/api/1.0/projects` — list
- `GET /rest/api/1.0/projects/{projectKey}` — read
- `POST /rest/api/1.0/projects` — create
- `PUT /rest/api/1.0/projects/{projectKey}` — update (e.g. name/description)
- `DELETE /rest/api/1.0/projects/{projectKey}` — delete

Reference: `https://developer.atlassian.com/server/bitbucket/rest/`.

## Authentication

Bitbucket HTTP access token; project creation/deletion require Bitbucket
admin or appropriate project-admin permission.

## Read operations

List/get project: `READ_ONLY`.

## Write operations

- `CREATE project`: `ADMINISTRATIVE`.
- `UPDATE project` (rename/description): `WRITE`.
- `DELETE project`: `DESTRUCTIVE` — deletes all repositories within it;
  requires `APPROVE DELETE` and must enumerate all contained repositories
  in the PROPOSED OPERATION impact statement before approval is
  requested.

## Approval rules

Standard `human-approval` flow. DELETE project is treated as high-blast-
radius: the proposal must show the full list of repositories that will
be deleted as a side effect, not just the project key.

## Security

Validate `projectKey` against `^[A-Za-z0-9_.-]+$` before use in any URL.
No TLS bypass. No shell injection via project name fields passed to
scripts (always passed as quoted parameters, never interpolated into a
shell/PowerShell command string).

## Verification

CREATE/UPDATE -> GET -> compare. DELETE -> GET -> expect 404 for the
project AND for each previously-listed child repository.

## Audit

Logged as `system: bitbucket`, `resource: project`.

## Rollback

CREATE/UPDATE: reversible via inverse operation. DELETE: **NOT
GUARANTEED** — deletes all child repositories; recovery depends on
backup/restore, not this framework.

## Examples

```
User: Create a project called "Payments Platform" with key PAY.
Agent: PROPOSE (ADMINISTRATIVE) -> APPROVE CREATE -> EXECUTE -> VERIFY -> AUDIT

User: Delete project PAY.
Agent: READ (list all repos under PAY) -> PROPOSE (DESTRUCTIVE, impact: "Deletes
       project PAY and its N repositories: ...") -> APPROVE DELETE -> EXECUTE ->
       VERIFY (404 on project + each repo) -> AUDIT
```
