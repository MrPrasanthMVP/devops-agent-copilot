---
name: jfrog-artifacts
description: Find and inspect JFrog Artifactory artifacts and their metadata (non-destructive) -- search by name/path, view properties, checksums, and download stats. Use for read-only artifact lookups; use jfrog-cleanup for any deletion.
license: Proprietary - internal enterprise use
---

## Purpose

Non-destructive artifact discovery and metadata inspection.

## Scope

Read-only artifact lookup only. Any deletion, even of a single artifact
-> `jfrog-cleanup` (which carries the mandatory find/summarize/approve
pipeline). Repository-level config -> `jfrog-repositories`.

## When to use

"Find artifacts matching app-*.jar in releases-local", "Show properties
for com/example/app/1.0/app.jar", "What are the checksums for this
artifact?".

## When not to use

Any delete request -> `jfrog-cleanup`.

## MCP dependency

Official JFrog MCP Server — `artifactory_artifacts_get_summary` is a
verified tool (v0.442) for artifact summary lookups. Broader search
tools are discovered at connect time.

## API fallback

- `POST /artifactory/api/search/aql` — flexible search (name/path/
  properties/checksum).
- `GET /artifactory/api/storage/{repoKey}/{itemPath}?properties` — item
  info + properties.
- `GET /artifactory/api/storage/{repoKey}/{itemPath}?stats` — download
  stats.

## Authentication

JFrog access token.

## Read operations

All operations in this Skill are `READ_ONLY`.

## Write operations

None. This Skill never mutates anything — see `jfrog-cleanup` for
deletion.

## Approval rules

Not applicable (read-only Skill).

## Security

Search queries/paths validated and bounded (no unbounded wildcard that
could enumerate the entire instance without the user asking for exactly
that).

## Verification

Not applicable (read-only).

## Audit

Each lookup is still logged (`risk: READ_ONLY`) for traceability.

## Rollback

Not applicable.

## Examples

```
User: Show properties for com/example/app/1.0/app.jar in releases-local.
Agent: READ_ONLY -> GET storage API with ?properties -> returns directly.
```
