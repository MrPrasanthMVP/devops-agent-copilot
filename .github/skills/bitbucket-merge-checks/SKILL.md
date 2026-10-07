---
name: bitbucket-merge-checks
description: View and change Bitbucket Data Center 9.4.5 merge check requirements (minimum approvals, required builds, unresolved-tasks check) that gate whether a pull request can be merged. Use for requests about required reviewers/approvals or required build status before merge.
license: Proprietary - internal enterprise use
---

## Purpose

Manage merge-gating checks: minimum approvers, required successful
builds, unresolved-comment/task blocking.

## Scope

Merge-gate check configuration only. Merge strategy itself ->
`bitbucket-merge-settings`.

## When to use

"Require at least 2 approvals before merge on repository X", "Require a
green build before merge".

## When not to use

Which merge strategy is allowed -> `bitbucket-merge-settings`.

## MCP dependency

Official "MCP for Bitbucket DC" — discover merge-check tools at connect
time.

## API fallback

Merge checks are configured via the **merge-config**
REST module, e.g.:

- `GET /rest/api/1.0/projects/{projectKey}/repos/{repositorySlug}/settings/pull-requests` —
  includes `requiredApprovers`, `requiredAllApprovers`,
  `requiredAllTasksComplete`, `requiredSuccessfulBuilds` fields.
- `POST .../settings/pull-requests` — update the same fields.

Reference: `https://developer.atlassian.com/server/bitbucket/rest/`.

## Authentication

Bitbucket HTTP access token with repository admin permission.

## Read operations

Get current merge-check configuration: `READ_ONLY`.

## Write operations

Change required approvers / required builds / task-completion gate:
`ADMINISTRATIVE`.

## Approval rules

`APPROVE ADMIN CHANGE`. Proposal shows current numeric/boolean values vs.
proposed, per field.

## Security

No credential exposure; gated because it changes the quality/security
bar for all future merges (e.g. lowering required approvals from 2 to 0
is a meaningful governance regression that must be visible in the
proposal, not buried).

## Verification

Update -> `GET` settings -> compare every changed field.

## Audit

Logged as `resource: merge_checks`, `risk: ADMINISTRATIVE`.

## Rollback

Revert to previously-read values — reversible, requires its own approval.

## Examples

```
User: Require 2 approvals and a passing build before merge on repository XYZ.
Agent: READ current (requiredApprovers: 0, requiredSuccessfulBuilds: 0) ->
       PROPOSE (proposed: requiredApprovers=2, requiredSuccessfulBuilds=1,
       risk: ADMINISTRATIVE) -> APPROVE ADMIN CHANGE -> EXECUTE -> VERIFY -> AUDIT
```
