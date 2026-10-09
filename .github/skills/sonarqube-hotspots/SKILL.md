---
name: sonarqube-hotspots
description: Search SonarQube security hotspots, inspect one in detail, and change its review status (e.g. mark fixed/safe), on BOTH SonarQube Server/Community Build (self-managed) and SonarQube Cloud. Use for any request to triage a SonarQube security hotspot.
license: Proprietary - internal enterprise use
---

## Purpose

Triage SonarQube security hotspots: search, inspect, and change review
status (to_review/reviewed with fixed/safe resolution) — with full
approval, verification, and audit coverage, across **both supported
deployments**.

## Scope

Security hotspot review only. Hotspots are a distinct workflow from
Issues (`api/hotspots/*` vs `api/issues/*`) — code-quality/bug/vulnerability
issues are `sonarqube-issues`.

## When to use

- "What security hotspots exist in project X?"
- "Show me hotspot Y"
- "Mark hotspot Y as safe" / "Mark hotspot Y as fixed"

## When not to use

- Code-quality/bug issue search/assign/transition -> `sonarqube-issues`.

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

- `search_security_hotspots` (params: `projectKey`, `hotspotKeys`,
  `branch`, `pullRequest`, `files`, `status`, `resolution`,
  `sinceLeakPeriod`, `onlyMine`, `pageIndex`, `pageSize`) — covers SEARCH.
- `show_security_hotspot` (params: `hotspotKey`) — covers GET.
- `change_security_hotspot_status` (params: `hotspotKey`, `status`,
  `resolution`, `comment`) — covers CHANGE_STATUS. This repo's script
  always calls REST directly for CHANGE_STATUS anyway (not MCP), so that
  approval/audit/verification stays uniform with every other WRITE
  operation in this framework.

All three operations in this Skill have a verified MCP tool — none are
"Not in catalog" here.

## API fallback

SonarQube Web API (`policies/versions-and-sources.yaml#sonarqube.official_docs.web_api`):

- `GET api/hotspots/search` — search (params: `projectKey`, `status` [TO_REVIEW|REVIEWED], `organization` for Cloud)
- `GET api/hotspots/show` — get one (param: `hotspot` [the hotspot key], `organization` for Cloud)
- `POST api/hotspots/change_status` — change status (params: `hotspot`, `status` [TO_REVIEW|REVIEWED], `resolution` [FIXED|SAFE, required when status=REVIEWED], `comment` optional, `organization` for Cloud)

Scripts: `scripts/windows/search-hotspots.ps1`, `scripts/unix/search-hotspots.sh` (READ_ONLY);
`scripts/windows/show-hotspot.ps1`, `scripts/unix/show-hotspot.sh` (READ_ONLY);
`scripts/windows/change-hotspot-status.ps1`, `scripts/unix/change-hotspot-status.sh` (WRITE).

## Authentication

SonarQube user token (local POC: `.github/local-secrets/sonarqube-token.txt`;
production: OAuth/credential broker — Section 12). Sent as
`Authorization: Bearer <token>`. Never logged or printed. Works
identically for Server and Cloud — only the base URL (and Cloud's
organization) differs.

## Read operations

Search hotspots, get one hotspot — both `READ_ONLY`, executed directly,
no approval required.

## Write operations

- `CHANGE_STATUS hotspot` (to_review/reviewed, with fixed/safe
  resolution) — `WRITE`, requires `APPROVE UPDATE`.

## Approval rules

`change-hotspot-status.ps1`/`.sh` imports `scripts/common/Common.psm1` /
sources `common.sh` and calls `Test-ApprovalToken` / `test_approval_token`
directly (binding: system=sonarqube, target=`<hotspotKey>`,
operation=`sonarqube.hotspot.change_status`) immediately before
executing. No generic affirmation suffices — the exact phrase
`APPROVE UPDATE` is required.

## Security

TLS certificate validation always on; no `curl -k`/`-SkipCertificateCheck`.
No `Invoke-Expression`/`iex`/`eval`. `-Status` and `-Resolution` are
restricted to the documented enum values; `-Resolution` is mandatory
(script-enforced) when `-Status REVIEWED` is requested.

## Verification

- CHANGE_STATUS -> `GET api/hotspots/show` after the change -> confirm
  `status` matches, and `resolution` matches when one was supplied. If
  either doesn't match, or the call errors ambiguously, report
  `STATUS = UNKNOWN` — never claim success without the match.

## Audit

Every call appends to `logs/enterprise-devops-audit.jsonl` with
`system: sonarqube`, `skill: sonarqube-hotspots`, the script path used,
and `executionMechanism` set to `mcp` or `rest-api` as appropriate.

## Rollback

- CHANGE_STATUS: rollback = set the status back to `TO_REVIEW` (read the
  prior status first via `show-hotspot` before changing); itself a
  `WRITE` requiring its own approval.

## Examples

```
User: What security hotspots exist in project payments-api?
Agent: READ_ONLY -> executes directly via MCP (or REST fallback) -> lists hotspots.

User: Mark hotspot AbCd1234 as safe.
Agent: PROPOSE (hotspot: AbCd1234, status: REVIEWED, resolution: SAFE, risk: WRITE)
       -> APPROVE UPDATE -> EXECUTE -> VERIFY (show confirms status+resolution) -> AUDIT -> REPORT
```
