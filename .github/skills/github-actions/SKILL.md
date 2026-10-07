---
name: github-actions
description: View GitHub Actions workflows/runs, and manage Actions secrets/variables/permissions settings. Use for requests about CI workflow runs, or about Actions-level secrets/variables/permissions configuration.
license: Proprietary - internal enterprise use
---

## Purpose

Inspect GitHub Actions workflow activity and manage Actions-level
configuration (secrets, variables, permission settings).

## Scope

Workflow run inspection and Actions configuration. Runner management ->
`github-runners`. Environment-scoped secrets specifically -> covered
here but always flagged as environment-scoped when relevant.

## When to use

"Show recent workflow runs for repo X", "Why did workflow run #123
fail?", "Add a repository secret named Y", "Disable Actions for repo X".

## When not to use

Self-hosted runner registration/management -> `github-runners`.

## MCP dependency

GitHub's official hosted MCP server documents an Actions-focused
toolset variant at `https://api.githubcopilot.com/mcp/x/actions`
(Cloud). For Server, the self-hosted `github-mcp-server` build's Actions
toolset applies. Discover exact tools at connect time.

## API fallback

GitHub REST API (`https://docs.github.com/en/rest/actions`):
`GET /repos/{owner}/{repo}/actions/runs`,
`GET /repos/{owner}/{repo}/actions/runs/{run_id}`,
`GET/PUT /repos/{owner}/{repo}/actions/permissions`,
`PUT /repos/{owner}/{repo}/actions/secrets/{secret_name}` (create/update
— value must be encrypted client-side with the repo's public key per
GitHub's documented libsodium sealed-box scheme before sending),
`DELETE /repos/{owner}/{repo}/actions/secrets/{secret_name}`,
`POST/PATCH/DELETE /repos/{owner}/{repo}/actions/variables`.

## Authentication

GitHub token/GitHub App with repository admin permission (secrets/
variables/permissions) or read (workflow run inspection).

## Read operations

List/get workflow runs, get Actions permissions: `READ_ONLY`.

## Write operations

- `CREATE/UPDATE/DELETE secret`: `SECURITY_SENSITIVE` — the secret VALUE
  is never displayed, logged, or echoed back by this Skill at any point,
  including in the PROPOSED OPERATION (only the secret NAME and the fact
  that a value is being set/changed/removed is shown).
- `CREATE/UPDATE/DELETE variable`: `WRITE` (variables are not secret, but
  still a WRITE).
- `CHANGE Actions permissions` (enable/disable, allowed actions list):
  `SECURITY_SENSITIVE`.

## Approval rules

`APPROVE SECURITY CHANGE` for secrets/permissions; `APPROVE UPDATE` for
variables. The agent never accepts a secret VALUE pasted in chat as
something to echo back for confirmation — it confirms only the secret
name and action taken.

## Security

Secret values are encrypted client-side before transmission per GitHub's
documented scheme and are never written to
`logs/enterprise-devops-audit.jsonl` (name/action only, per the global
redaction rule).

## Verification

Secret create/update -> list secrets -> confirm the name is present with
an updated `updated_at` (never the value, which the API never returns).
Delete -> list -> confirm absence. Variables -> GET -> compare value
directly (not secret).

## Audit

Logged as `system: github`, `resource: actions_secret` or
`actions_variable` or `actions_permissions`, value redacted for secrets.

## Rollback

Variables: reversible. Secrets: **NOT GUARANTEED** to roll back to the
exact prior value (the prior value was never retained by this
framework, by design, since secret values are never stored outside the
target system).

## Examples

```
User: Add a repository secret named DEPLOY_TOKEN to repo XYZ.
Agent: PROPOSE (name: DEPLOY_TOKEN, value: [not shown], risk: SECURITY_SENSITIVE)
       -> APPROVE SECURITY CHANGE -> EXECUTE (encrypt+PUT) -> VERIFY (name present)
       -> AUDIT (name only)
```
