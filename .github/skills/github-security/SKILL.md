---
name: github-security
description: View and change GitHub repository security feature configuration -- code scanning, secret scanning, Dependabot alerts/security updates. Use for requests about enabling, disabling, or inspecting these security features.
license: Proprietary - internal enterprise use
---

## Purpose

Manage repository-level security feature configuration: code scanning,
secret scanning, Dependabot.

## Scope

Security *feature configuration* (on/off, alert management). This is
distinct from `jfrog-xray` (artifact vulnerability data) and from
`github-permissions`/`github-webhooks` (access/notification config).

## When to use

"Is secret scanning enabled on repo X?", "Enable Dependabot security
updates on repo X", "Show open code scanning alerts for repo X",
"Disable secret scanning on repo X".

## When not to use

Branch protection's "require status checks" referencing a security scan
-> `github-branch-protection`.

## MCP dependency

GitHub's official hosted MCP server (Cloud) or self-hosted
`github-mcp-server` (Server). Discover security-configuration and
alert-listing tools at connect time.

## API fallback

GitHub REST API:
- Security/analysis config: `GET/PATCH /repos/{owner}/{repo}`
  (`security_and_analysis` field —
  `https://docs.github.com/en/rest/repos/repos`).
- Code scanning: `GET /repos/{owner}/{repo}/code-scanning/alerts`
  (`https://docs.github.com/en/rest/code-scanning`).
- Secret scanning: `GET /repos/{owner}/{repo}/secret-scanning/alerts`
  (`https://docs.github.com/en/rest/secret-scanning`).
- Dependabot: `GET /repos/{owner}/{repo}/dependabot/alerts`,
  `PUT/DELETE /repos/{owner}/{repo}/vulnerability-alerts` (security
  updates toggle) (`https://docs.github.com/en/rest/dependabot`).

## Authentication

GitHub token/GitHub App with repository admin permission (config
changes) or read (alert listing).

## Read operations

Get security-and-analysis config, list alerts (code scanning/secret
scanning/Dependabot): `READ_ONLY`.

## Write operations

- `ENABLE` any of these features: `ADMINISTRATIVE` (a net-positive
  security change, but still a configuration change requiring
  traceability).
- `DISABLE` any of these features: `SECURITY_SENSITIVE` (Section 41
  explicitly lists disabling code scanning/secret scanning/Dependabot as
  security-sensitive) — the proposal must state the security coverage
  being removed and ask for explicit confirmation beyond a generic
  affirmation.
- Alert state changes (dismiss/resolve): `WRITE`.

## Approval rules

`APPROVE ADMIN CHANGE` for enable; `APPROVE SECURITY CHANGE` for disable;
`APPROVE UPDATE` for dismissing/resolving an individual alert (with the
specific alert and chosen reason shown).

## Security

Alert details (e.g. a secret-scanning alert's detected secret snippet)
are themselves sensitive — this Skill never echoes the raw detected
secret value into chat or logs, only the alert's metadata (type,
location, state).

## Verification

Config change -> GET -> compare `security_and_analysis` field. Alert
state change -> GET the alert -> confirm new state.

## Audit

Logged as `system: github`, `resource: security_config` or
`code_scanning_alert`/`secret_scanning_alert`/`dependabot_alert`.

## Rollback

Enable/disable: reversible via inverse toggle — but disabling leaves a
security-coverage gap for the time it was off, which this framework
flags, not hides. Alert dismissal: reversible (re-open), requires its
own approval.

## Examples

```
User: Disable secret scanning on repo XYZ.
Agent: READ current (enabled) -> PROPOSE (risk: SECURITY_SENSITIVE, impact:
       "repository will no longer be scanned for committed secrets") ->
       APPROVE SECURITY CHANGE -> EXECUTE -> VERIFY -> AUDIT
```
