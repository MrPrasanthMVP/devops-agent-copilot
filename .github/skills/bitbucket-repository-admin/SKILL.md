---
name: bitbucket-repository-admin
description: Create, read, update, and delete Bitbucket Data Center 9.4.5 repositories (including default branch changes and repository-level settings). Use for any request that creates, renames, archives, configures, or deletes a Bitbucket repository.
license: Proprietary - internal enterprise use
---

## Purpose

Manage the lifecycle of Bitbucket Data Center repositories: create, read,
update (including default branch), and delete, with full approval,
verification, and audit coverage.

## Scope

Repository-level operations only. Project-level operations are
`bitbucket-project-admin`; permissions are `bitbucket-permissions`; branch
restrictions are `bitbucket-branch-permissions`.

## When to use

- "Show repositories in project X" / "Get repository Y details"
- "Create a repository in project X"
- "Change repository Y's default branch to main"
- "Delete repository Y"

## When not to use

- Pull request operations -> `bitbucket-pull-requests`.
- Webhooks -> `bitbucket-webhooks`. Hooks (pre-receive/merge checks) ->
  `bitbucket-hooks` / `bitbucket-merge-checks`.

## MCP dependency

Primary: **official "MCP for Bitbucket DC"**
(`confluence.atlassian.com/bitbucketserver/mcp-for-bitbucket-dc-1822723926.html`),
connected at `<bitbucket-base-url>/rest/mcp/1.0/` (see `.mcp.json`). This
server documents support for "manage projects, repositories, branches,
and tags." At connect time, discover the exposed tools and use whichever
one corresponds to GET/CREATE/UPDATE/DELETE repository — tool names are
not assumed here (Section 23). If no matching tool is exposed for a given
operation (e.g. DELETE), fall back to the REST API below.

## API fallback

Bitbucket Server/Data Center REST API 1.0, target version **9.4.5**
(`https://developer.atlassian.com/server/bitbucket/rest/`):

- `GET /rest/api/1.0/projects/{projectKey}/repos` — list
- `GET /rest/api/1.0/projects/{projectKey}/repos/{repositorySlug}` — read
- `POST /rest/api/1.0/projects/{projectKey}/repos` — create
- `PUT /rest/api/1.0/projects/{projectKey}/repos/{repositorySlug}` — update (e.g. name)
- `PUT /rest/api/1.0/projects/{projectKey}/repos/{repositorySlug}/default-branch` — default branch
- `DELETE /rest/api/1.0/projects/{projectKey}/repos/{repositorySlug}` — delete

Scripts: `scripts/windows/create-repository.ps1`,
`scripts/unix/create-repository.sh` (WRITE/ADMINISTRATIVE),
`scripts/windows/delete-repository.ps1`,
`scripts/unix/delete-repository.sh` (DESTRUCTIVE).

## Authentication

Bitbucket HTTP access token (local POC: `.github/local-secrets/bitbucket-token.txt`;
production: OAuth/credential broker — Section 12). Sent as
`Authorization: Bearer <token>`. Never logged or printed.

## Read operations

List/get repository, get default branch, get repository settings — all
`READ_ONLY`, executed directly, no approval required.

## Write operations

- `CREATE repository` — `ADMINISTRATIVE` (creating governed infrastructure).
- `UPDATE repository name / default branch` — `WRITE`.
- `DELETE repository` — `DESTRUCTIVE`, requires `APPROVE DELETE`.

## Approval rules

Every write calls `.github/skills/human-approval/scripts/*/request-approval.*`
to propose, waits for the exact phrase, then `confirm-approval.*` mints a
signed token. `delete-repository.ps1`/`.sh` imports
`scripts/common/Common.psm1` / sources `common.sh` and calls
`Test-ApprovalToken` / `test_approval_token` directly (binding:
system=bitbucket, target=`<projectKey>/<repositorySlug>`,
operation=`bitbucket.repository.delete`) immediately before executing.
DELETE always requires `APPROVE DELETE` — no generic affirmation
suffices.

## Security

TLS certificate validation always on; no `curl -k`/`-SkipCertificateCheck`.
No `Invoke-Expression`/`iex`/`eval`. All repository slugs/project keys are
validated against `^[A-Za-z0-9_.-]+$` before being placed in a URL path.

## Verification

- CREATE -> `GET` the new repository -> confirm it exists with the
  requested name/slug.
- UPDATE default branch -> `GET` default branch -> compare.
- DELETE -> `GET` the repository -> expect `404 Not Found`. If the GET
  still returns the repository, or if the API call errors ambiguously,
  report `STATUS = UNKNOWN` — never claim success without the 404.

## Audit

Every call appends to `logs/enterprise-devops-audit.jsonl` with
`system: bitbucket`, `skill: bitbucket-repository-admin`, the script path
used, and `executionMechanism` set to `mcp` or `rest-api` as appropriate.

## Rollback

- CREATE: rollback = delete the newly created repository (itself a
  DESTRUCTIVE operation requiring its own approval).
- UPDATE (default branch / name): rollback = apply the inverse update;
  recoverable.
- DELETE: rollback = **NOT GUARANTEED**. Bitbucket Data Center does not
  expose an official "undelete repository" API; recovery, if any, depends
  on your backup/restore procedures, not this framework.

## Examples

```
User: Show repositories in project ABC.
Agent: READ_ONLY -> executes directly via MCP (or REST fallback) -> lists repos.

User: Change repository XYZ default branch to main.
Agent: READ current default branch -> PROPOSE (current: develop, proposed: main,
       risk: WRITE) -> APPROVE UPDATE -> EXECUTE -> VERIFY -> AUDIT -> REPORT

User: Delete repository TEST.
Agent: PROPOSED OPERATION (risk: DESTRUCTIVE, impact: permanent, irreversible)
       -> requires: APPROVE DELETE -> EXECUTE -> VERIFY (expect 404) -> AUDIT -> REPORT
```
