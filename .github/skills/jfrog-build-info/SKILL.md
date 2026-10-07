---
name: jfrog-build-info
description: Query JFrog Artifactory build information (CI build records, build runs, published build artifacts/dependencies). Use for requests about CI build metadata published to Artifactory -- read-only.
license: Proprietary - internal enterprise use
---

## Purpose

Read-only lookup of CI build records published to Artifactory's
Build-Info service.

## Scope

Build metadata lookup only. This Skill does not publish, promote, or
delete build info (publishing is normally done by the CI pipeline
itself via `jfrog-cli`, outside this framework's scope; promotion is an
AppTrust/release-lifecycle operation that would need its own explicitly
approved Skill if required in the future — not implemented here).

## When to use

"List builds for project X", "Show build runs for build Y", "What
artifacts/dependencies did build Y version Z produce?".

## When not to use

Promoting or releasing a build/application version -> not implemented in
this framework (see AppTrust note in `policies/system-policy.yaml`'s
JFrog MCP tool catalog, which does list `apptrust_promote_version`/
`apptrust_release_version` as discoverable MCP tools — if your
organization needs this, it requires a new Skill with its own approval
treatment, since promotion/release are `ADMINISTRATIVE`/`WRITE`
operations with real deployment impact).

## MCP dependency

Official JFrog MCP Server. Verified v0.442 tool catalog includes
`artifactory_builds_list_builds`, `artifactory_builds_list_build_runs`,
`artifactory_builds_get_info` — documented, real MCP tools for exactly
this capability.

## API fallback

JFrog Artifactory REST API: `GET /artifactory/api/build`,
`GET /artifactory/api/build/{buildName}`,
`GET /artifactory/api/build/{buildName}/{buildNumber}`.

## Authentication

JFrog access token with read permission on the build-info namespace.

## Read operations

All operations in this Skill are `READ_ONLY`.

## Write operations

None implemented.

## Approval rules

Not applicable (read-only Skill).

## Security

Build info (env vars, properties) retrieved from Artifactory can contain
sensitive values if the publishing CI job embedded them — the agent
redacts anything credential-shaped before displaying or logging build
info, same as the global redaction rule in `policies/audit-policy.yaml`.

## Verification

Not applicable (read-only).

## Audit

Each lookup is logged (`risk: READ_ONLY`).

## Rollback

Not applicable.

## Examples

```
User: Show the latest build info for "payments-service".
Agent: READ_ONLY -> artifactory_builds_get_info -> reports directly, no approval needed.
```
