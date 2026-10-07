---
name: jfrog-admin
description: JFrog Platform / Artifactory instance-level administration -- version discovery, system configuration, access tokens, and OIDC configuration at the platform level. Use for instance-wide (not repository- or project-scoped) JFrog administration questions.
license: Proprietary - internal enterprise use
---

## Purpose

Instance-level JFrog Platform administration: version/capability
discovery and platform-wide access configuration (tokens, OIDC).

## Scope

Instance-wide settings. Repository config -> `jfrog-repositories`.
Project-scoped settings -> `jfrog-projects`. User/group/permission admin
-> their dedicated Skills.

## When to use

"What Artifactory version is running?", "List access tokens",
"Create an OIDC configuration for platform access".

## When not to use

Repository-, project-, user-, or group-scoped requests -> the dedicated
Skill for that resource.

## MCP dependency

Official JFrog MCP Server. Verified v0.442 tool catalog includes
`access_tokens_create`, `access_tokens_list`, `access_tokens_revoke`, and
`access_oidc_create_configuration` — documented, real MCP tools for this
capability.

## API fallback

- Version discovery (mandatory per Section 4/38, never hard-coded):
  `GET /artifactory/api/system/version`.
- Access tokens: JFrog Access REST API token endpoints
  (`https://docs.jfrog.com` — Access Tokens).

## Authentication

JFrog access token with Artifactory/Access admin permission for any
write path.

## Read operations

Version discovery, list access tokens, list OIDC configs: `READ_ONLY`.

## Write operations

- `CREATE access token`: `SECURITY_SENSITIVE` — issuing a new credential
  is itself a security-sensitive act; the proposal states the token's
  scope and expiry, and the resulting token value is reported to the
  user exactly once and never written to the audit log or any file by
  this framework.
- `REVOKE access token`: `SECURITY_SENSITIVE` — requires
  `APPROVE SECURITY CHANGE` (revoking a token a running system depends on
  can cause an outage; the proposal must say so).
- `CREATE OIDC configuration`: `SECURITY_SENSITIVE`.

## Approval rules

All writes in this Skill require `APPROVE SECURITY CHANGE` given their
authentication-infrastructure impact, even where
`policies/operation-classification.yaml`'s generic examples might
otherwise suggest `ADMINISTRATIVE` — authentication/identity
configuration is treated as the stricter category per this framework's
"default to the stricter category" rule.

## Security

Issued token values are never logged, never written to
`logs/enterprise-devops-audit.jsonl` (only the token's *metadata* — id,
scope, expiry — is audited), and never echoed back a second time.

## Verification

Version discovery self-verifies. Token create -> list tokens -> confirm
the new token id is present (not the secret value). Revoke -> list ->
confirm absence.

## Audit

Logged as `system: jfrog`, `resource: access_token` or
`resource: oidc_configuration`, `risk: SECURITY_SENSITIVE`, metadata only.

## Rollback

Token create: revoke it (own approval). Revoke: **NOT GUARANTEED** — a
revoked token cannot be "un-revoked"; a new token must be issued,
requiring every dependent system to be reconfigured.

## Examples

```
User: What Artifactory version is this instance running?
Agent: READ_ONLY -> GET /artifactory/api/system/version -> reports verified
       version, compares against policies/system-policy.yaml's recorded
       reference value, flags if materially different.
```
