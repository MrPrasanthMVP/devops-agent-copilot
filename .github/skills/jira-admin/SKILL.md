---
name: jira-admin
description: Create, read, update, and delete Jira Cloud projects, and inspect instance-level Jira configuration. Use for requests about Jira project lifecycle or site-wide Jira administration (not individual issues).
license: Proprietary - internal enterprise use
---

## Purpose

Jira Cloud project-level and instance-level administration.

## Scope

Project lifecycle (create/configure/delete) and instance settings
inspection. Individual issues -> `jira-issues`. Permission schemes ->
`jira-permissions`. Workflow definitions -> `jira-workflows`.

## When to use

"Create a Jira project", "List Jira projects", "Delete project X",
"What project types are available?".

## When not to use

Issue-level requests -> `jira-issues`.

## MCP dependency

Official Atlassian Rovo MCP Server. Project tools are resolved via
`discover`/`executeRead`/`executeWrite` (the documented primaries cover
issues; project administration tools are part of the broader catalog
Rovo exposes for Jira and must be located via `discover` at call time —
not assumed by name here).

## API fallback

Jira Cloud REST API v3
(`https://developer.atlassian.com/cloud/jira/platform/rest/v3/`):
`GET /rest/api/3/project`, `GET /rest/api/3/project/{key}`,
`POST /rest/api/3/project`, `PUT /rest/api/3/project/{key}`,
`DELETE /rest/api/3/project/{key}`.

## Authentication

Rovo MCP: OAuth 2.1. REST fallback: shared Atlassian site credential
(`jira-email.txt` + `jira-token.txt`).

## Read operations

List/get project, list project types: `READ_ONLY`.

## Write operations

- `CREATE project`: `ADMINISTRATIVE`.
- `UPDATE project`: `WRITE`.
- `DELETE project`: `DESTRUCTIVE` — deletes all issues in the project;
  requires `APPROVE DELETE` and the proposal must state the issue count
  that will be lost.

## Approval rules

Standard `human-approval` flow with the matching phrase per operation
type above.

## Security

Project keys validated for shape before use in any URL/tool call.

## Verification

CREATE/UPDATE -> GET -> compare. DELETE -> GET -> expect 404.

## Audit

Logged as `system: jira`, `resource: project`.

## Rollback

CREATE/UPDATE: reversible. DELETE: **NOT GUARANTEED** — depends on your
Atlassian plan's project-trash/retention window, not assumed by this
framework.

## Examples

```
User: Create a Jira project called "Payments" with key PAY.
Agent: PROPOSE (ADMINISTRATIVE) -> APPROVE CREATE -> EXECUTE -> VERIFY -> AUDIT
```
