---
name: sonarqube-issues
description: Search SonarQube issues, assign/unassign an issue, and perform workflow transitions (confirm/resolve/reopen/etc), on BOTH SonarQube Server/Community Build (self-managed) and SonarQube Cloud. Use for any request to triage, assign, or resolve a SonarQube code-quality/security issue.
license: Proprietary - internal enterprise use
---

## Purpose

Triage SonarQube issues: search, assign/unassign, and perform workflow
transitions (confirm, resolve, reopen, mark false-positive/won't-fix) —
with full approval, verification, and audit coverage, across **both
supported deployments**.

## Scope

Issue triage only. Security hotspots are a separate workflow (not yet a
Skill in this repo — hotspots use `api/hotspots/*`, distinct from
`api/issues/*`). Project lifecycle is `sonarqube-projects`; quality gate
status/selection is `sonarqube-quality-gates`.

## When to use

- "What issues exist in project X?"
- "Assign issue Y to jdoe"
- "Mark issue Y as a false positive" / "Resolve issue Y" / "Reopen issue Y"

## When not to use

- Project create/delete -> `sonarqube-projects`.
- Quality gate status/selection -> `sonarqube-quality-gates`.

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

- `search_sonar_issues_in_projects` (params: `issueStatuses`, `tags`,
  `inNewCodePeriod`, `issueKey`, `impactSoftwareQualities`, `pageIndex`,
  `projectKeys`, `pageSize`, `branch`, `pullRequest`, `severities`) —
  covers SEARCH.
- `change_sonar_issue_status` (params: `key`, `status`, `comment`) —
  **partially** covers TRANSITION. Its `status` vocabulary
  (accept/falsepositive/reopen) is NARROWER than the REST
  `api/issues/do_transition` state machine this Skill's
  `transition-issue.ps1`/`.sh` uses (confirm/unconfirm/reopen/resolve/
  falsepositive/wontfix) — this Skill always calls REST directly so every
  transition value stays available, rather than silently losing
  confirm/unconfirm/resolve/wontfix when MCP is connected.

**Confirmed absent from the verified MCP catalog — routes to REST
fallback:** issue ASSIGN. There is no `assign_issue` (or equivalent) MCP
tool; `issue.assign` is REST-fallback-only via `POST api/issues/assign`.

## API fallback

SonarQube Web API (`policies/versions-and-sources.yaml#sonarqube.official_docs.web_api`):

- `GET api/issues/search` — search (params: `componentKeys`, `issues`, `assignees`, `issueStatuses`, `organization` for Cloud)
- `POST api/issues/assign` — assign/unassign (params: `issue`, `assignee` [omit to unassign], `organization` for Cloud)
- `POST api/issues/do_transition` — workflow transition (params: `issue`, `transition`, `organization` for Cloud)

Scripts: `scripts/windows/search-issues.ps1`, `scripts/unix/search-issues.sh` (READ_ONLY);
`scripts/windows/assign-issue.ps1`, `scripts/unix/assign-issue.sh` (WRITE);
`scripts/windows/transition-issue.ps1`, `scripts/unix/transition-issue.sh` (WRITE).

## Authentication

SonarQube user token (local POC: `.github/local-secrets/sonarqube-token.txt`;
production: OAuth/credential broker — Section 12). Sent as
`Authorization: Bearer <token>`. Never logged or printed. Works
identically for Server and Cloud — only the base URL (and Cloud's
organization) differs.

## Read operations

Search issues — `READ_ONLY`, executed directly, no approval required.

## Write operations

- `ASSIGN issue` — `WRITE`, requires `APPROVE UPDATE`.
- `TRANSITION issue` (confirm/unconfirm/reopen/resolve/falsepositive/wontfix)
  — `WRITE`, requires `APPROVE UPDATE`.

## Approval rules

`assign-issue.ps1`/`.sh` and `transition-issue.ps1`/`.sh` import
`scripts/common/Common.psm1` / source `common.sh` and call
`Test-ApprovalToken` / `test_approval_token` directly (binding:
system=sonarqube, target=`<issueKey>`, operation=`sonarqube.issue.assign`
or `sonarqube.issue.transition`) immediately before executing. No
generic affirmation suffices — the exact phrase `APPROVE UPDATE` is
required for both.

## Security

TLS certificate validation always on; no `curl -k`/`-SkipCertificateCheck`.
No `Invoke-Expression`/`iex`/`eval`. Issue keys, assignees, and transition
values are passed as body parameters (not interpolated into the URL
path); `-Transition`/`--transition` is restricted to the documented
enum of valid values.

## Verification

- ASSIGN -> search the issue by key -> confirm `assignee` matches the
  requested value (or is absent, for unassign). If the search still
  shows the old assignee, or the call errors ambiguously, report
  `STATUS = UNKNOWN` — never claim success without the match.
- TRANSITION -> search the issue by key -> confirm the top-level
  `status` matches the expected post-transition value (see the
  transition→status map in the script). The `resolution` sub-field
  (e.g. FALSE-POSITIVE vs WONTFIX, both of which map to status
  `RESOLVED`) is **not** separately re-verified — documented honestly
  rather than over-claiming a finer-grained check the simple status
  comparison doesn't actually perform.

## Audit

Every call appends to `logs/enterprise-devops-audit.jsonl` with
`system: sonarqube`, `skill: sonarqube-issues`, the script path used, and
`executionMechanism` set to `mcp` or `rest-api` as appropriate.

## Rollback

- ASSIGN: rollback = assign back to the previous assignee (read it first
  via `search-issues` before changing); itself a `WRITE` requiring its
  own approval.
- TRANSITION: rollback = apply the inverse transition where one exists
  (e.g. `reopen` undoes `resolve`); some transitions (e.g. `falsepositive`,
  `wontfix`) are not symmetric — `reopen` is the closest available
  inverse for all of them.

## Examples

```
User: What issues exist in project payments-api?
Agent: READ_ONLY -> executes directly via MCP (or REST fallback) -> lists issues.

User: Assign issue AbCd1234 to jdoe.
Agent: PROPOSE (issue: AbCd1234, assignee: jdoe, risk: WRITE) -> APPROVE UPDATE
       -> EXECUTE -> VERIFY (search confirms assignee) -> AUDIT -> REPORT

User: Mark issue AbCd1234 as a false positive.
Agent: PROPOSE (issue: AbCd1234, transition: falsepositive, risk: WRITE) -> APPROVE UPDATE
       -> EXECUTE -> VERIFY (search confirms status RESOLVED) -> AUDIT -> REPORT
```
