---
name: jfrog-repositories
description: List, inspect, create, and update JFrog Artifactory Self-Managed repositories (local/remote/virtual/federated). Use for requests about repository configuration (not individual artifacts).
license: Proprietary - internal enterprise use
---

## Purpose

Manage Artifactory repository configuration lifecycle.

## Scope

Repository-level configuration. Individual artifacts -> `jfrog-artifacts`
/ `jfrog-cleanup`. Permission targets -> `jfrog-permissions`.

## When to use

"List Artifactory repositories", "Create a new local Maven repository",
"Show config for releases-local".

## When not to use

Artifact-level requests -> `jfrog-artifacts`/`jfrog-cleanup`.

## MCP dependency

Official **JFrog MCP Server**. Verified tool catalog (v0.442, see
`policies/system-policy.yaml`) includes `artifactory_repositories_create`,
`artifactory_repositories_get`, `artifactory_repositories_list`,
`artifactory_repositories_update` — these ARE documented MCP tools for
this exact capability. Still, re-discover tools at connect time rather
than hardcoding availability, since the catalog version may differ on
your deployment (Section 23).

## API fallback

JFrog Artifactory REST API: `GET /artifactory/api/repositories`,
`GET /artifactory/api/repositories/{repoKey}`,
`PUT /artifactory/api/repositories/{repoKey}` (create/update — same verb
for both per Artifactory's documented REST API),
`DELETE /artifactory/api/repositories/{repoKey}` (delete — see note).

## Authentication

JFrog access token (local POC: `.github/local-secrets/jfrog-token.txt`).

## Read operations

List/get repository config: `READ_ONLY`.

## Write operations

- `CREATE repository`: `ADMINISTRATIVE` (Section 16: "CREATE JFrog
  repository" = ADMINISTRATIVE).
- `UPDATE repository config`: `ADMINISTRATIVE`.
- `DELETE repository`: `DESTRUCTIVE` — deletes all artifacts within it;
  requires `APPROVE DELETE` and the proposal must state the artifact
  count/size that will be lost (delegate the count/size lookup to
  `jfrog-cleanup`'s AQL pattern before proposing).

## Approval rules

Standard `human-approval` flow with the matching phrase per operation.

## Security

Repository keys validated against `^[A-Za-z0-9_][A-Za-z0-9_.-]*$`.

## Verification

CREATE/UPDATE -> GET -> compare config. DELETE -> GET -> expect 404.

## Audit

Logged as `system: jfrog`, `resource: repository`.

## Rollback

CREATE/UPDATE: reversible. DELETE: **NOT GUARANTEED**.

## Examples

```
User: Create a local Maven repository named "internal-maven-local".
Agent: PROPOSE (ADMINISTRATIVE) -> APPROVE CREATE -> EXECUTE -> VERIFY -> AUDIT
```
