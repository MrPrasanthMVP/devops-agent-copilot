---
name: bitbucket-merge-settings
description: View and change Bitbucket Data Center repository merge strategy settings (allowed merge strategies, default strategy, commit message templates). Use for requests about which merge strategies (merge commit, squash, fast-forward) are allowed or default for a repository.
license: Proprietary - internal enterprise use
---

## Purpose

Manage repository-level merge strategy configuration.

## Scope

Merge *strategy* settings only. Required *checks* before merge (builds,
approval counts) -> `bitbucket-merge-checks`. The act of merging a given
PR -> `bitbucket-pull-requests`.

## When to use

"Only allow squash merges on repository X", "What's the default merge
strategy for repository Y?".

## When not to use

Required reviewers/build checks -> `bitbucket-merge-checks`. Merging a
specific PR -> `bitbucket-pull-requests`.

## MCP dependency

Official "MCP for Bitbucket DC" — discover repository-settings tools at
connect time.

## API fallback

- `GET /rest/api/1.0/projects/{projectKey}/repos/{repositorySlug}/settings/pull-requests` — read merge config
- `POST .../settings/pull-requests` — update merge config (allowed
  strategies, default strategy, delete-source-branch-on-merge)

Reference: `https://developer.atlassian.com/server/bitbucket/rest/`.

## Authentication

Bitbucket HTTP access token with repository admin permission.

## Read operations

Get current merge settings: `READ_ONLY`.

## Write operations

Change allowed/default merge strategy: `ADMINISTRATIVE`.

## Approval rules

`APPROVE ADMIN CHANGE`. Proposal shows current allowed strategies/default
vs. proposed.

## Security

No credential exposure risk; still gated because it changes repository
governance behavior for every future PR.

## Verification

Update -> `GET` settings -> compare.

## Audit

Logged as `resource: merge_settings`, `risk: ADMINISTRATIVE`.

## Rollback

Revert to previously-read settings object — reversible, requires its own
approval.

## Examples

```
User: Only allow squash merges on repository XYZ.
Agent: READ current (merge-commit, squash, ff allowed) -> PROPOSE (proposed:
       squash only, risk: ADMINISTRATIVE) -> APPROVE ADMIN CHANGE -> EXECUTE ->
       VERIFY -> AUDIT
```
