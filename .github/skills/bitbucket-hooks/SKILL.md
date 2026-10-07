---
name: bitbucket-hooks
description: View and configure Bitbucket Data Center 9.4.5 repository hooks (pre-receive/post-receive plugin hooks, e.g. reject-force-push, commit-message-validator). Use for enabling/disabling/configuring a repository hook.
license: Proprietary - internal enterprise use
---

## Purpose

Enable, disable, and configure repository hooks (server-side plugin
hooks distinct from merge checks and webhooks).

## Scope

Hook enable/disable/settings only. External HTTP notifications ->
`bitbucket-webhooks`. Merge-gate checks (required builds/approvals) ->
`bitbucket-merge-checks`.

## When to use

"Enable the reject-force-push hook on repository X", "Disable hook Y",
"Show configured hooks for repository X".

## When not to use

Webhook URLs/payloads -> `bitbucket-webhooks`. Merge check configuration
-> `bitbucket-merge-checks`.

## MCP dependency

Official "MCP for Bitbucket DC" — discover hook-related tools at connect
time; not all hook management may be exposed via MCP depending on the
server version/whitelist, in which case use the REST fallback.

## API fallback

- `GET /rest/api/1.0/projects/{projectKey}/repos/{repositorySlug}/settings/hooks` — list
- `GET .../settings/hooks/{hookKey}` — read one hook's settings
- `PUT .../settings/hooks/{hookKey}/enabled` — enable
- `DELETE .../settings/hooks/{hookKey}/enabled` — disable
- `PUT .../settings/hooks/{hookKey}/settings` — configure

Reference: `https://developer.atlassian.com/server/bitbucket/rest/`.

## Authentication

Bitbucket HTTP access token with repository admin permission.

## Read operations

List/get hook configuration: `READ_ONLY`.

## Write operations

Enable/disable/configure a hook: `ADMINISTRATIVE`.

## Approval rules

Standard `human-approval` flow with `APPROVE ADMIN CHANGE`. The proposal
must name the exact `hookKey` and show the current enabled/disabled state
and settings diff.

## Security

Hook settings payloads are validated against the shape documented for
the specific `hookKey`; the agent never passes an arbitrary user-supplied
JSON blob straight through without surfacing it in the PROPOSED OPERATION
for review first.

## Verification

Enable/disable -> `GET` the hook -> confirm `enabled` matches. Configure
-> `GET` -> compare settings object.

## Audit

Logged as `resource: hook`, `risk: ADMINISTRATIVE`.

## Rollback

Toggle back to the prior enabled/disabled state, or reapply the prior
settings object — reversible, requires its own approval.

## Examples

```
User: Enable the reject-force-push hook on repository XYZ.
Agent: READ current state (disabled) -> PROPOSE (ADMINISTRATIVE) ->
       APPROVE ADMIN CHANGE -> EXECUTE -> VERIFY -> AUDIT
```
