---
name: github-runners
description: View and manage GitHub Actions self-hosted runners and runner groups (registration status, labels, group membership). Use for requests about self-hosted runner inventory or configuration.
license: Proprietary - internal enterprise use
---

## Purpose

Inspect and manage self-hosted GitHub Actions runners/runner groups.

## Scope

Runner/runner-group management. Workflow run inspection and secrets/
variables -> `github-actions`.

## When to use

"List self-hosted runners for org X", "Show runner group Y's
repositories", "Remove offline runner Z".

## When not to use

Workflow run results -> `github-actions`.

## MCP dependency

GitHub's official hosted MCP server (Cloud) or self-hosted
`github-mcp-server` (Server). Discover runner-management tools at
connect time.

## API fallback

GitHub REST API (`https://docs.github.com/en/rest/actions/self-hosted-runners`,
`https://docs.github.com/en/rest/actions/self-hosted-runner-groups`):
`GET /orgs/{org}/actions/runners`,
`GET /repos/{owner}/{repo}/actions/runners`,
`DELETE /orgs/{org}/actions/runners/{runner_id}` (remove/deregister),
`GET/PUT /orgs/{org}/actions/runner-groups/{group_id}`.

## Authentication

GitHub token/GitHub App with organization admin permission.

## Read operations

List runners/runner groups, get runner status: `READ_ONLY`.

## Write operations

- `REMOVE runner`: `ADMINISTRATIVE` — if the runner is currently
  executing a job, removal can fail that job; the proposal states the
  runner's current busy/idle status.
- `UPDATE runner group` (repository access list, labels policy):
  `ADMINISTRATIVE`, or `SECURITY_SENSITIVE` if it changes which
  repositories/visibility level can use self-hosted compute (self-hosted
  runners are a well-known lateral-movement risk if misconfigured —
  GitHub's own documentation warns against enabling them for public-repo
  workflows without restriction).

## Approval rules

Standard `human-approval` flow with the matching phrase; runner-group
visibility/access changes always get `APPROVE SECURITY CHANGE` framing.

## Security

Runner group changes that would allow public repositories or fork PR
workflows to target self-hosted runners are flagged as a specific risk
callout in the proposal, not just a generic admin change.

## Verification

Remove -> list runners -> confirm absence. Update group -> GET -> compare.

## Audit

Logged as `system: github`, `resource: runner` or `runner_group`.

## Rollback

Remove: re-registration requires the runner host to re-run the
registration flow — **NOT a simple API rollback**. Update group:
reversible via inverse update.

## Examples

```
User: Remove offline runner "build-agent-07" from org "my-org".
Agent: READ status (offline, idle) -> PROPOSE (risk: ADMINISTRATIVE) ->
       APPROVE ADMIN CHANGE -> EXECUTE -> VERIFY -> AUDIT
```
