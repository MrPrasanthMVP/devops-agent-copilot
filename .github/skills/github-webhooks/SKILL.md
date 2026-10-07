---
name: github-webhooks
description: View, create, update, and delete GitHub repository or organization webhooks. Use for any request to add, change, remove, or inspect a GitHub webhook.
license: Proprietary - internal enterprise use
---

## Purpose

Manage GitHub repository/organization webhook lifecycle.

## Scope

Webhook CRUD at repository or organization scope.

## When to use

"Add a webhook to repo X posting to URL Y on push", "List webhooks for
repo X", "Delete webhook Z".

## When not to use

GitHub Actions workflow configuration -> `github-actions`.

## MCP dependency

GitHub's official hosted MCP server (Cloud) or self-hosted
`github-mcp-server` (Server). Discover webhook-management tools at
connect time.

## API fallback

GitHub REST API (`https://docs.github.com/en/rest/webhooks/repos`,
`https://docs.github.com/en/rest/webhooks/orgs`):
`GET /repos/{owner}/{repo}/hooks`,
`POST /repos/{owner}/{repo}/hooks` (create),
`PATCH /repos/{owner}/{repo}/hooks/{hook_id}` (update),
`DELETE /repos/{owner}/{repo}/hooks/{hook_id}` (delete). Org-level
equivalents under `/orgs/{org}/hooks`.

## Authentication

GitHub token/GitHub App with repository or organization admin
permission as appropriate.

## Read operations

List/get webhook: `READ_ONLY` (the `secret` field, if configured, is
never returned by GitHub's API and never displayed by this Skill).

## Write operations

Create/update/delete a webhook: `SECURITY_SENSITIVE` — a webhook can
exfiltrate repository/organization event data to an arbitrary external
URL.

## Approval rules

`APPROVE WEBHOOK CHANGE`. The proposal shows the destination URL in
full, the subscribed events, and flags plain-HTTP destinations or
destinations outside any corporate-approved domain allowlist configured
in `policies/security-policy.yaml`.

## Security

Webhook secrets are never logged or echoed. URLs validated as
well-formed; SSRF-prone targets (e.g. internal metadata service IPs) are
flagged in the proposal for human judgment, not silently allowed or
silently blocked.

## Verification

Create/update -> GET -> compare URL/events/active state. Delete -> GET
list -> confirm absence.

## Audit

Logged as `system: github`, `resource: webhook`, `risk: SECURITY_SENSITIVE`,
destination URL included (never the secret).

## Rollback

Update: revert to prior URL/events. Delete: recreate if the prior
definition was recorded — the secret value itself is **NOT GUARANTEED**
recoverable (GitHub never returns it), so a recreated webhook needs a
freshly issued secret communicated out of band.

## Examples

```
User: Add a webhook on repo XYZ that POSTs to https://ci.example.com/hook on push.
Agent: PROPOSE (risk: SECURITY_SENSITIVE, destination shown in full) ->
       APPROVE WEBHOOK CHANGE -> EXECUTE -> VERIFY -> AUDIT
```
