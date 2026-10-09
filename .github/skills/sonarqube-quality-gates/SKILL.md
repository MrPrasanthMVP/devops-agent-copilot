---
name: sonarqube-quality-gates
description: List quality gates, get a SonarQube project's quality gate status, and associate a project with a quality gate, on BOTH SonarQube Server/Community Build (self-managed) and SonarQube Cloud. Use for any request about pass/fail quality gate status or which gate governs a project.
license: Proprietary - internal enterprise use
---

## Purpose

Inspect and manage SonarQube quality gates: list gates, read a project's
current pass/fail status, and change which gate a project is bound to —
with full approval, verification, and audit coverage, across **both
supported deployments**.

## Scope

Quality gate operations only. Project lifecycle is `sonarqube-projects`;
issue triage is `sonarqube-issues`.

## When to use

- "Is project X passing its quality gate?"
- "What quality gates exist?"
- "Set project X's quality gate to Y"

## When not to use

- Project create/delete -> `sonarqube-projects`.
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
Verified tools for this Skill:

- `get_project_quality_gate_status` (params: `projectKey`, `analysisId`,
  `branch`, `projectId`, `pullRequest`) — covers GET quality gate status.
- `list_quality_gates` (no params) — covers LIST quality gates.

**Confirmed absent from the verified MCP catalog — routes to REST
fallback:** associating/selecting a quality gate for a project. There is
no `select_quality_gate` (or equivalent) MCP tool; `quality_gate.select`
is REST-fallback-only via `POST api/qualitygates/select`.

## API fallback

SonarQube Web API (`policies/versions-and-sources.yaml#sonarqube.official_docs.web_api`):

- `GET api/qualitygates/list` — list all quality gates (params: `organization` for Cloud)
- `GET api/qualitygates/project_status` — get status (params: `projectKey`, `branch`, `organization` for Cloud)
- `POST api/qualitygates/select` — associate a project with a gate (params: `projectKey`, `gateName`, `organization` for Cloud)

Scripts: `scripts/windows/list-quality-gates.ps1`, `scripts/unix/list-quality-gates.sh` (READ_ONLY);
`scripts/windows/get-quality-gate-status.ps1`, `scripts/unix/get-quality-gate-status.sh` (READ_ONLY);
`scripts/windows/select-quality-gate.ps1`, `scripts/unix/select-quality-gate.sh` (WRITE).

## Authentication

SonarQube user token (local POC: `.github/local-secrets/sonarqube-token.txt`;
production: OAuth/credential broker — Section 12). Sent as
`Authorization: Bearer <token>`. Never logged or printed. Works
identically for Server and Cloud — only the base URL (and Cloud's
organization) differs.

## Read operations

List quality gates, get a project's quality gate status — both
`READ_ONLY`, executed directly, no approval required.

## Write operations

- `SELECT quality gate` (associate a project with a gate) — `WRITE`,
  requires `APPROVE UPDATE`.

## Approval rules

`select-quality-gate.ps1`/`.sh` imports `scripts/common/Common.psm1` /
sources `common.sh` and calls `Test-ApprovalToken` / `test_approval_token`
directly (binding: system=sonarqube, target=`<projectKey>`,
operation=`sonarqube.quality_gate.select`) immediately before executing.
No generic affirmation suffices — the exact phrase `APPROVE UPDATE` is
required.

## Security

TLS certificate validation always on; no `curl -k`/`-SkipCertificateCheck`.
No `Invoke-Expression`/`iex`/`eval`. Project keys and gate names are
passed as body parameters (not interpolated into the URL path) to avoid
injection via special characters.

## Verification

- SELECT -> `api/qualitygates/select` returns no read-back body (and
  `api/qualitygates/project_status` does not echo the gate name either).
  Verification here means "the POST returned 2xx" — reported as
  `CONFIRMED` on success. This is a narrower guarantee than other
  Skills' GET-after-write checks; documented honestly here rather than
  over-claiming a richer verification the API does not support.

## Audit

Every call appends to `logs/enterprise-devops-audit.jsonl` with
`system: sonarqube`, `skill: sonarqube-quality-gates`, the script path
used, and `executionMechanism` set to `mcp` or `rest-api` as appropriate.

## Rollback

- SELECT: rollback = select the project's previous gate again (read it
  first via `get-quality-gate-status` before changing, so you know what
  to roll back to); itself a `WRITE` requiring its own approval.

## Examples

```
User: Is project payments-api passing its quality gate?
Agent: READ_ONLY -> executes directly via MCP (or REST fallback) -> reports status.

User: Set project payments-api's quality gate to "Sonar way".
Agent: PROPOSE (project: payments-api, gate: Sonar way, risk: WRITE) -> APPROVE UPDATE
       -> EXECUTE -> VERIFY (2xx; see Verification note) -> AUDIT -> REPORT
```
