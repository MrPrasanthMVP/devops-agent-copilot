---
name: sonarqube-webhooks
description: List, create, and delete SonarQube webhooks (global or project-scoped), on BOTH SonarQube Server/Community Build (self-managed) and SonarQube Cloud. Use for any request to see, add, or remove an outbound HTTP notification hook for SonarQube analysis events.
license: Proprietary - internal enterprise use
---

## Purpose

Manage SonarQube webhooks (outbound HTTP notifications fired after each
analysis): list, create, and delete — with full approval, verification,
and audit coverage, across **both supported deployments**.

## Scope

Webhook configuration only. Project lifecycle is `sonarqube-projects`;
issue/hotspot/quality-gate operations are the other `sonarqube-*` Skills.

## When to use

- "What webhooks are configured for project X?" / "What global webhooks exist?"
- "Add a webhook to notify CI when project X finishes analysis"
- "Remove webhook Y"

## When not to use

- Project create/delete -> `sonarqube-projects`.
- Issue/hotspot/quality-gate operations -> the matching `sonarqube-*` Skill.

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

- `list_webhooks` (param: `projectKey`) — covers LIST.
- `create_webhook` (params: `name`, `url`, `projectKey`, `secret`) —
  covers CREATE.

**Confirmed absent from the verified MCP catalog — routes to REST
fallback:** webhook DELETE. There is no `delete_webhook` (or
equivalent) MCP tool; `webhook.delete` is REST-fallback-only via
`POST api/webhooks/delete`.

## API fallback

SonarQube Web API (`policies/versions-and-sources.yaml#sonarqube.official_docs.web_api`):

- `GET api/webhooks/list` — list (params: `project` optional, `organization` for Cloud)
- `POST api/webhooks/create` — create (params: `name`, `url`, `project` optional, `secret` optional, `organization` for Cloud)
- `POST api/webhooks/delete` — delete (param: `webhook` [the webhook key], `organization` for Cloud)

Scripts: `scripts/windows/list-webhooks.ps1`, `scripts/unix/list-webhooks.sh` (READ_ONLY);
`scripts/windows/create-webhook.ps1`, `scripts/unix/create-webhook.sh` (WRITE);
`scripts/windows/delete-webhook.ps1`, `scripts/unix/delete-webhook.sh` (DESTRUCTIVE).

## Authentication

SonarQube user token (local POC: `.github/local-secrets/sonarqube-token.txt`;
production: OAuth/credential broker — Section 12). Sent as
`Authorization: Bearer <token>`. Never logged or printed. Works
identically for Server and Cloud — only the base URL (and Cloud's
organization) differs.

## Read operations

List webhooks (global or project-scoped) — `READ_ONLY`, executed
directly, no approval required.

## Write operations

- `CREATE webhook` — `WRITE`, requires `APPROVE CREATE`.
- `DELETE webhook` — `DESTRUCTIVE`, requires `APPROVE DELETE`.

## Approval rules

`create-webhook.ps1`/`.sh` and `delete-webhook.ps1`/`.sh` import
`scripts/common/Common.psm1` / source `common.sh` and call
`Test-ApprovalToken` / `test_approval_token` directly (binding:
system=sonarqube, target=`<projectKey-or-global>/<name>` for CREATE or
`<webhookKey>` for DELETE, operation=`sonarqube.webhook.create` or
`sonarqube.webhook.delete`) immediately before executing. DELETE always
requires `APPROVE DELETE` — no generic affirmation suffices.

## Security

TLS certificate validation always on; no `curl -k`/`-SkipCertificateCheck`.
No `Invoke-Expression`/`iex`/`eval`. The webhook `-Secret`/`--secret`
value (used by SonarQube to sign outbound payloads) is sent to the API
but is **never** logged, printed, or included in the audit record —
`Protect-SensitiveData` redacts any key matching the sensitive-key
pattern before it reaches `logs/enterprise-devops-audit.jsonl`.

## Verification

- CREATE -> `api/webhooks/create` returns the new webhook's `key` ->
  `GET api/webhooks/list` -> confirm a webhook with that key is present.
- DELETE -> `GET api/webhooks/list` -> confirm the webhook key is
  **absent**. If the key still appears, or the call errors ambiguously,
  report `STATUS = UNKNOWN` — never claim success without confirmed
  absence.

## Audit

Every call appends to `logs/enterprise-devops-audit.jsonl` with
`system: sonarqube`, `skill: sonarqube-webhooks`, the script path used,
and `executionMechanism` set to `mcp` or `rest-api` as appropriate.

## Rollback

- CREATE: rollback = delete the newly created webhook (itself a
  DESTRUCTIVE operation requiring its own approval).
- DELETE: rollback = **NOT GUARANTEED**. SonarQube does not expose an
  official "undelete webhook" API; recreating it (with `create-webhook`)
  restores equivalent behavior only if the name/URL/secret are known.

## Examples

```
User: What webhooks are configured for project payments-api?
Agent: READ_ONLY -> executes directly via MCP (or REST fallback) -> lists webhooks.

User: Add a webhook to project payments-api notifying https://ci.example.internal/sonar-hook.
Agent: PROPOSE (project: payments-api, name: ..., url: ..., risk: WRITE) -> APPROVE CREATE
       -> EXECUTE -> VERIFY (list confirms new key present) -> AUDIT -> REPORT

User: Delete webhook AbCd1234.
Agent: PROPOSED OPERATION (risk: DESTRUCTIVE, impact: permanent, irreversible)
       -> requires: APPROVE DELETE -> EXECUTE -> VERIFY (list confirms key absent) -> AUDIT -> REPORT
```
