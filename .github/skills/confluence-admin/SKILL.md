---
name: confluence-admin
description: Create, read, update, and archive/delete Confluence Cloud spaces, and inspect site-wide Confluence configuration. Use for requests about Confluence space lifecycle (not individual pages).
license: Proprietary - internal enterprise use
---

## Purpose

Confluence Cloud space-level and site-level administration.

## Scope

Space lifecycle. Page content -> `confluence-pages`. Space/page
permissions -> `confluence-permissions`.

## When to use

"Create a Confluence space called X", "List Confluence spaces",
"Archive space X".

## When not to use

Page-level requests -> `confluence-pages`.

## MCP dependency

Official Atlassian Rovo MCP Server — `listConfluenceSpaces` is a
documented primary read tool; space create/archive tools are resolved
via `discover` at call time (not assumed by name).

## API fallback

Confluence Cloud REST API v2
(`https://developer.atlassian.com/cloud/confluence/rest/v2/`):
`GET /wiki/api/v2/spaces`, `GET /wiki/api/v2/spaces/{id}`,
`POST /wiki/api/v2/spaces` (create — subject to current API
availability; verify before relying on it), archival is typically
exposed as a space status change.

## Authentication

Rovo MCP: OAuth 2.1. REST fallback: shared Atlassian site credential.

## Read operations

List/get space: `READ_ONLY`.

## Write operations

- `CREATE space`: `ADMINISTRATIVE`.
- `ARCHIVE/DELETE space`: `DESTRUCTIVE` — removes/hides all pages within
  it; requires `APPROVE DELETE` and the proposal must state the page
  count affected.

## Approval rules

Standard `human-approval` flow with the matching phrase.

## Security

Space keys validated for shape before use.

## Verification

CREATE -> GET -> confirm existence. ARCHIVE/DELETE -> GET -> confirm
status reflects archived/removed state.

## Audit

Logged as `system: confluence`, `resource: space`.

## Rollback

CREATE: delete the space (own DESTRUCTIVE approval). ARCHIVE: usually
reversible (unarchive) — verify current API support before claiming
this. DELETE (if distinct from archive on your site): **NOT GUARANTEED**.

## Examples

```
User: List all Confluence spaces.
Agent: READ_ONLY -> listConfluenceSpaces -> results, no approval needed.
```
