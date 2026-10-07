---
name: bitbucket-webhooks
description: View, create, update, and delete Bitbucket Data Center 9.4.5 repository webhooks (outbound HTTP notifications on repo/PR events). Use for any request to add, change, remove, or inspect a Bitbucket webhook.
license: Proprietary - internal enterprise use
---

## Purpose

Manage outbound webhooks on Bitbucket Data Center repositories.

## Scope

Webhook CRUD only. Server-side plugin hooks -> `bitbucket-hooks`.

## When to use

"Add a webhook to repository X that posts to URL Y on push", "List
webhooks for repository X", "Delete webhook Z".

## When not to use

Server-side pre/post-receive plugin hooks -> `bitbucket-hooks`.

## MCP dependency

Official "MCP for Bitbucket DC" — discover webhook tools at connect
time.

## API fallback

- `GET /rest/api/1.0/projects/{projectKey}/repos/{repositorySlug}/webhooks` — list
- `POST .../webhooks` — create
- `PUT .../webhooks/{webhookId}` — update
- `DELETE .../webhooks/{webhookId}` — delete

Reference: `https://developer.atlassian.com/server/bitbucket/rest/`.

## Authentication

Bitbucket HTTP access token with repository admin permission.

## Read operations

List/get webhook: `READ_ONLY` (the webhook's configured secret, if any,
is treated as a credential and never displayed).

## Write operations

Create/update/delete a webhook: `SECURITY_SENSITIVE` — a webhook can
exfiltrate repository event data to an arbitrary external URL, so even
"just adding a notification" is security-sensitive.

## Approval rules

`APPROVE WEBHOOK CHANGE` is required for create/update/delete. The
proposal must show the destination URL in full so the human can assess
exfiltration risk, and must flag if the URL is outside any documented
corporate-approved domain allowlist (if one is configured in
`policies/security-policy.yaml`).

## Security

Webhook secrets/tokens are never logged, never echoed back in full (only
confirmation that a secret is configured). URLs are validated as
well-formed HTTPS URLs; plain HTTP destinations are flagged as a risk in
the proposal.

## Verification

Create/update -> `GET` the webhook -> compare URL/events/active state.
Delete -> `GET` list -> confirm the `webhookId` is absent.

## Audit

Logged as `resource: webhook`, `risk: SECURITY_SENSITIVE`, destination
URL included (never the secret).

## Rollback

Update: revert to prior URL/events config. Delete: recreate if the prior
definition was recorded — treated as `NOT GUARANTEED` if the original
secret value was not independently retained (Bitbucket does not return
secrets on GET).

## Examples

```
User: Add a webhook on repository XYZ that POSTs to https://ci.example.com/hook on push.
Agent: PROPOSE (risk: SECURITY_SENSITIVE, destination shown in full) ->
       APPROVE WEBHOOK CHANGE -> EXECUTE -> VERIFY -> AUDIT
```
