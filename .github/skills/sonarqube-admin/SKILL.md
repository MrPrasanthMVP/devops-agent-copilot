---
name: sonarqube-admin
description: Instance-level administration for SonarQube Server/Community Build (self-managed) ONLY -- health, system info, and liveness checks. SonarQube Cloud is a managed SaaS instance and has no equivalent self-reported admin endpoints, so this Skill does not apply there. Use for instance-wide (not project-scoped) SonarQube health/diagnostics questions.
license: Proprietary - internal enterprise use
---

## Purpose

Inspect the health, configuration, and liveness of a self-managed
SonarQube Server/Community Build instance — with full audit coverage.

## Scope

Instance-wide diagnostics only. Project/issue/hotspot/quality-gate/webhook
operations are the other `sonarqube-*` Skills.

## When to use

- "Is the SonarQube server healthy?"
- "Show SonarQube system info"
- "Is the SonarQube server up?"

## When not to use

- Anything project-, issue-, hotspot-, quality-gate-, or webhook-scoped
  -> the matching `sonarqube-*` Skill.
- **SonarQube Cloud** — this Skill is Server/Community Build only (see
  Deployment below).

## Deployment (Server ONLY — no Cloud equivalent)

Unlike every other `sonarqube-*` Skill in this framework, this one does
**not** support SonarQube Cloud: `api/system/health`, `api/system/info`,
and `api/system/ping` are self-managed-instance diagnostics with no
equivalent on the managed SaaS platform (`policies/versions-and-sources.yaml#sonarqube`).
Pass `-BaseUrl` as your self-managed instance URL. There is no
`-Organization` parameter on any script in this Skill.

## MCP dependency

Primary: **official SonarQube MCP Server** (SonarSource, container image
`sonarsource/sonarqube-mcp`; see `.mcp.json` / `.vscode/mcp.json`;
verified tool catalog: `docs.sonarsource.com/sonarqube-mcp-server/reference/tools`,
"System (Server Only)" category). Verified tools for this Skill:

- `get_system_health` (no params) — covers HEALTH.
- `get_system_info` (no params) — covers INFO.
- `ping_system` (no params) — covers PING.

Also present in the verified catalog but **not yet scripted** in this
repo (Script: No — see `features.md`'s legend for what that means):
`get_system_logs` (param: `name`) and `get_system_status` (no params —
this repo already covers the equivalent via `scripts/sonarqube/get-version.ps1`/`.sh`,
which calls the same `api/system/status` REST endpoint directly for
version-discovery purposes, so a redundant Skill script was not added).

## API fallback

SonarQube Web API (`policies/versions-and-sources.yaml#sonarqube.official_docs.web_api`):

- `GET api/system/health` — health (no params)
- `GET api/system/info` — system info (no params)
- `GET api/system/ping` — liveness (no params; plain-text `pong` response)

Scripts: `scripts/windows/get-system-health.ps1`, `scripts/unix/get-system-health.sh` (READ_ONLY);
`scripts/windows/get-system-info.ps1`, `scripts/unix/get-system-info.sh` (READ_ONLY);
`scripts/windows/ping-system.ps1`, `scripts/unix/ping-system.sh` (READ_ONLY).

## Authentication

SonarQube user token (local POC: `.github/local-secrets/sonarqube-token.txt`;
production: OAuth/credential broker — Section 12). Sent as
`Authorization: Bearer <token>`. Never logged or printed.
`api/system/health` and `api/system/info` require 'Administer System'
permission; `api/system/ping` is a public endpoint (a token is still
passed for parity with every other script in this framework).

## Read operations

Health, system info, ping — all `READ_ONLY`, executed directly, no
approval required.

## Write operations

None. This Skill is entirely diagnostic/read-only.

## Approval rules

Not applicable — no write operations exist in this Skill.

## Security

TLS certificate validation always on; no `curl -k`/`-SkipCertificateCheck`.
No `Invoke-Expression`/`iex`/`eval`.

## Verification

Not applicable — every operation here is a read.

## Audit

Every call appends to `logs/enterprise-devops-audit.jsonl` with
`system: sonarqube`, `skill: sonarqube-admin`, the script path used, and
`executionMechanism` set to `mcp` or `rest-api` as appropriate.

## Rollback

Not applicable — no write operations exist in this Skill.

## Examples

```
User: Is the SonarQube server healthy?
Agent: READ_ONLY -> executes directly via MCP (or REST fallback) -> reports health status.

User: Show SonarQube system info.
Agent: READ_ONLY -> executes directly via MCP (or REST fallback) -> reports system info.
```
