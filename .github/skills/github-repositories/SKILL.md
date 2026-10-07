---
name: github-repositories
description: Create, read, update, and delete GitHub Enterprise (Cloud or Server) repositories, including settings like default branch, visibility, and topics. Use for any request to create, configure, rename, transfer, archive, or delete a GitHub repository.
license: Proprietary - internal enterprise use
---

## Purpose

Manage GitHub Enterprise repository lifecycle.

## Scope

Repository-level operations. Organization-level settings ->
`github-organizations`. Branch protection -> `github-branch-protection`.
Rulesets -> `github-rulesets`. Collaborator/team permissions ->
`github-permissions`.

## When to use

"Create a repository in org X", "Show settings for repo Y", "Rename repo
Y", "Archive repo Y", "Delete repo Y", "Change the default branch of
repo Y".

## When not to use

Branch-protection/ruleset changes -> their dedicated Skills.

## MCP dependency

GitHub's official hosted MCP server (`api.githubcopilot.com/mcp/`,
Cloud) or self-hosted `github-mcp-server` (Server) — see
`policies/system-policy.yaml` for the Cloud/Server decision. Discover
repository-management tools at connect time (Section 23).

## API fallback

GitHub REST API (`https://docs.github.com/en/rest/repos/repos`):

- `GET /repos/{owner}/{repo}` — read
- `GET /orgs/{org}/repos` — list
- `POST /orgs/{org}/repos` — create
- `PATCH /repos/{owner}/{repo}` — update (name, default_branch,
  visibility, archived, topics, etc.)
- `DELETE /repos/{owner}/{repo}` — delete

## Authentication

GitHub token (local POC: `.github/local-secrets/github-token.txt`;
production: GitHub App installation token) with the required
organization/repository admin scope.

## Read operations

List/get repository: `READ_ONLY`.

## Write operations

- `CREATE repository`: `WRITE` (Section 16 worked example lists generic
  "CREATE repository" as WRITE; note this differs from Bitbucket's/
  JFrog's CREATE-repository classification of ADMINISTRATIVE — GitHub
  repo creation is comparatively lower blast-radius since it starts
  empty and unconfigured, consistent with the spec's own generic
  example table).
- `UPDATE repository settings` (rename, default branch, visibility):
  `WRITE`, except visibility change (private<->public/internal) which is
  `SECURITY_SENSITIVE` (changes who can see the code).
- `ARCHIVE repository`: `ADMINISTRATIVE` (read-only afterward, but
  reversible).
- `DELETE repository`: `DESTRUCTIVE` — `APPROVE DELETE` required.

## Approval rules

Standard `human-approval` flow with the matching phrase. Visibility
changes always get `APPROVE PERMISSION CHANGE` framing in the proposal
("this will make the repository visible to: ...") regardless of
direction.

## Security

Repository/org names validated for shape before use in any URL.

## Verification

CREATE/UPDATE -> GET -> compare. ARCHIVE -> GET -> confirm
`archived: true`. DELETE -> GET -> expect `404`.

## Audit

Logged as `system: github`, `resource: repository`.

## Rollback

CREATE: delete it (own DESTRUCTIVE approval). UPDATE: revert the changed
field. ARCHIVE: unarchive (reversible). DELETE: **NOT GUARANTEED** —
GitHub does not expose a standard self-service "undelete repository" API
for most plans; recovery, if any, depends on GitHub Support / your
Enterprise's data-recovery procedures, not this framework.

## Examples

```
User: Change repository XYZ default branch to main.
Agent: READ current default branch -> PROPOSE (risk: WRITE) -> APPROVE UPDATE
       -> EXECUTE -> VERIFY -> AUDIT

User: Delete repository TEST.
Agent: PROPOSE (DESTRUCTIVE) -> APPROVE DELETE -> EXECUTE -> VERIFY (404) -> AUDIT
```
