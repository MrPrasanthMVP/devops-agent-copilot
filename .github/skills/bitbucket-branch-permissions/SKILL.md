---
name: bitbucket-branch-permissions
description: View and change Bitbucket Data Center branch permissions/restrictions (who can push, force-push, or delete on protected branches like main/release/*). Use for any request to lock down, restrict, or change push rules on a branch or branch pattern.
license: Proprietary - internal enterprise use
---

## Purpose

Manage branch-level restrictions (Bitbucket's equivalent of GitHub branch
protection) for Bitbucket Data Center repositories.

## Scope

Branch restriction rules only (fast-forward-only, no-deletes, pull-
request-only, read/write access restriction by branch pattern).

## When to use

"Lock down main so only PRs can merge", "Who can push to release/*?",
"Prevent force-push on develop".

## When not to use

General repo permissions -> `bitbucket-permissions`. Merge check config
(required builds/approvals) -> `bitbucket-merge-checks`.

## MCP dependency

Official "MCP for Bitbucket DC" — this server's documented capability
list includes branch management; discover the exact
restriction-management tool at connect time rather than assuming a name.

## API fallback

Branch permissions in Bitbucket Server/Data Center are managed via the
**branch-permissions** REST module:

- `GET /rest/branch-permissions/2.0/projects/{projectKey}/repos/{repositorySlug}/restrictions` — list
- `POST /rest/branch-permissions/2.0/projects/{projectKey}/repos/{repositorySlug}/restrictions` — create a restriction
- `DELETE /rest/branch-permissions/2.0/projects/{projectKey}/repos/{repositorySlug}/restrictions/{id}` — remove

Reference: `https://developer.atlassian.com/server/bitbucket/rest/` (branch-permissions REST plugin module).

## Authentication

Bitbucket HTTP access token with repository admin permission.

## Read operations

List current restrictions: `READ_ONLY`.

## Write operations

Create/remove a branch restriction: `ADMINISTRATIVE`
(`APPROVE BRANCH PROTECTION`).

## Approval rules

Proposal must show the exact branch/pattern, restriction type
(`fast-forward-only`, `no-deletes`, `pull-request-only`,
`read`/`write` access list), and current vs. proposed state. Always
`APPROVE BRANCH PROTECTION`, even for a restriction that appears
"additive" (tightening access is still a governance change).

## Security

Branch pattern strings are validated for shape (no path traversal, no
shell metacharacters) before being sent as a JSON body field.

## Verification

Create -> `GET` restrictions -> confirm the new rule is present with the
expected `id`. Remove -> `GET` -> confirm the `id` is absent.

## Audit

Logged as `resource: branch_permission`, `risk: ADMINISTRATIVE`.

## Rollback

Remove a restriction (if it was a create) or recreate the prior
restriction (if it was a remove) — both are themselves approved
`ADMINISTRATIVE` operations; not automatic.

## Examples

```
User: Make sure nobody can push directly to main in repository XYZ -- only via PR.
Agent: READ current restrictions -> PROPOSE (type: pull-request-only, branch: main,
       risk: ADMINISTRATIVE) -> APPROVE BRANCH PROTECTION -> EXECUTE -> VERIFY -> AUDIT
```
