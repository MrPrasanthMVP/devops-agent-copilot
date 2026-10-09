---
name: sonarqube-projects
description: List, read, create, and delete SonarQube projects, on BOTH SonarQube Server/Community Build (self-managed) and SonarQube Cloud. Use for any request to see what projects exist, inspect a project, provision a new project, or permanently remove one.
license: Proprietary - internal enterprise use
---

## Purpose

Manage the lifecycle of SonarQube projects: list/search, read, create, and
delete, with full approval, verification, and audit coverage, across
**both supported deployments**.

## Scope

Project lifecycle only. Quality gate association is
`sonarqube-quality-gates`; issue triage is `sonarqube-issues`.

## When to use

- "What SonarQube projects exist?" / "Show me project X"
- "Create a SonarQube project for repo Y"
- "Delete SonarQube project Z"

## When not to use

- Quality gate status/selection -> `sonarqube-quality-gates`.
- Issue search/assign/transition -> `sonarqube-issues`.

## Deployment (Server vs Cloud)

This framework supports **both** SonarQube deployments
(`policies/versions-and-sources.yaml#sonarqube`):

- **SonarQube Server / Community Build** (self-managed, on-prem): pass
  `-BaseUrl` as your instance URL (e.g. `https://sonarqube.example.internal`).
  `-Organization` is not used.
- **SonarQube Cloud** (SaaS): pass `-BaseUrl "https://sonarcloud.io"`
  (or `https://sonarqube.us` for the US region) **and** `-Organization
  <your-org-key>` — Cloud requires the organization on every call.

Every script in this Skill accepts both parameters; `-Organization` is
optional and simply omitted for Server.

## MCP dependency

Primary: **official SonarQube MCP Server** (SonarSource, container image
`sonarsource/sonarqube-mcp`; see `.mcp.json` / `.vscode/mcp.json`;
verified tool catalog: `docs.sonarsource.com/sonarqube-mcp-server/reference/tools`).
It supports both deployments via `SONARQUBE_URL` (Server) or
`SONARQUBE_ORG` (Cloud) environment variables. Verified tools for this
Skill:

- `search_my_sonarqube_projects` (params: `pageIndex`, `pageSize`, `q`) —
  covers LIST/GET (GET = search filtered to one project key).

**Confirmed absent from the verified MCP catalog — routes to REST
fallback:** project CREATE and DELETE. There is no `create_project` or
`delete_project` (or equivalent) MCP tool; both `project.create` and
`project.delete` are REST-fallback-only.

## API fallback

SonarQube Web API (`policies/versions-and-sources.yaml#sonarqube.official_docs.web_api`):

- `GET api/projects/search` — list/search (params: `q`, `projects`, `organization` for Cloud)
- `POST api/projects/create` — create (params: `project`, `name`, `visibility`, `organization` for Cloud)
- `POST api/projects/delete` — delete (params: `project`, `organization` for Cloud)

Scripts: `scripts/windows/list-projects.ps1`, `scripts/unix/list-projects.sh` (READ_ONLY);
`scripts/windows/get-project.ps1`, `scripts/unix/get-project.sh` (READ_ONLY);
`scripts/windows/create-project.ps1`, `scripts/unix/create-project.sh` (WRITE);
`scripts/windows/delete-project.ps1`, `scripts/unix/delete-project.sh` (DESTRUCTIVE).

## Authentication

SonarQube user token (local POC: `.github/local-secrets/sonarqube-token.txt`;
production: OAuth/credential broker — Section 12). Sent as
`Authorization: Bearer <token>`. Never logged or printed. Works
identically for Server and Cloud — only the base URL (and Cloud's
organization) differs.

## Read operations

List/search projects, get one project — both `READ_ONLY`, executed
directly, no approval required.

## Write operations

- `CREATE project` — `WRITE`, requires `APPROVE CREATE`.
- `DELETE project` — `DESTRUCTIVE`, requires `APPROVE DELETE`.

## Approval rules

Every write calls `.github/skills/human-approval/scripts/*/request-approval.*`
to propose, waits for the exact phrase, then `confirm-approval.*` mints a
signed token. `create-project.ps1`/`.sh` and `delete-project.ps1`/`.sh`
import `scripts/common/Common.psm1` / source `common.sh` and call
`Test-ApprovalToken` / `test_approval_token` directly (binding:
system=sonarqube, target=`<projectKey>`, operation=`sonarqube.project.create`
or `sonarqube.project.delete`) immediately before executing. DELETE
always requires `APPROVE DELETE` — no generic affirmation suffices.

## Security

TLS certificate validation always on; no `curl -k`/`-SkipCertificateCheck`.
No `Invoke-Expression`/`iex`/`eval`. Project keys are validated against
`^[A-Za-z0-9_.:-]+$` before being placed in a URL/body.

## Verification

- CREATE -> search for the project key -> confirm it is present.
- DELETE -> search for the project key -> expect it **absent** from
  results. SonarQube has no single-object project GET, so absence from
  search (not an HTTP 404) is the verification signal. If the search
  still returns the project, or the call errors ambiguously, report
  `STATUS = UNKNOWN` — never claim success without confirmed absence.

## Audit

Every call appends to `logs/enterprise-devops-audit.jsonl` with
`system: sonarqube`, `skill: sonarqube-projects`, the script path used,
and `executionMechanism` set to `mcp` or `rest-api` as appropriate.

## Rollback

- CREATE: rollback = delete the newly created project (itself a
  DESTRUCTIVE operation requiring its own approval).
- DELETE: rollback = **NOT GUARANTEED**. SonarQube does not expose an
  official "undelete project" API; recovery, if any, depends on your
  backup/restore procedures, not this framework.

## Examples

```
User: What SonarQube projects exist?
Agent: READ_ONLY -> executes directly via MCP (or REST fallback) -> lists projects.

User: Create a SonarQube project for repo payments-api.
Agent: PROPOSE (project: payments-api, risk: WRITE) -> APPROVE CREATE
       -> EXECUTE -> VERIFY (search confirms present) -> AUDIT -> REPORT

User: Delete SonarQube project old-service.
Agent: PROPOSED OPERATION (risk: DESTRUCTIVE, impact: permanent, irreversible)
       -> requires: APPROVE DELETE -> EXECUTE -> VERIFY (search confirms absent) -> AUDIT -> REPORT
```
