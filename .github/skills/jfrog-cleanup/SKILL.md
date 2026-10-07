---
name: jfrog-cleanup
description: Find candidate artifacts for cleanup (old, large, or unused) in JFrog Artifactory Self-Managed, summarize impact, and delete only after explicit human approval. Use for any request to clean up, purge, or delete old/large/unused artifacts -- never performs bulk deletion directly from a natural-language request.
license: Proprietary - internal enterprise use
---

## Purpose

Implement the Section 20 cleanup pipeline exactly:
`READ -> find candidates -> show candidates/summary -> show total count ->
show total storage -> show retention criteria -> risk classification ->
APPROVE DELETE -> delete -> verify -> audit`. This Skill never deletes
anything as a direct consequence of a natural-language request — deletion
always requires a separate, explicit, operation-bound approval, and
large/bulk deletes are enumerated so the human can see exactly what is
being removed.

## Scope

Finding and deleting artifacts based on age, size, or other retention
criteria. Repository-level configuration -> `jfrog-repositories`.
Artifact metadata inspection (non-destructive) -> `jfrog-artifacts`.

## When to use

"Find artifacts older than 180 days in releases-local", "Delete those
artifacts", "Clean up artifacts larger than 500MB that haven't been
downloaded in 90 days".

## When not to use

Repository creation/configuration -> `jfrog-repositories`. Permission or
user/group management -> `jfrog-permissions`/`jfrog-users`/`jfrog-groups`.

## MCP dependency

Official **JFrog MCP Server** (`https://docs.jfrog.com/installation/docs/mcp`,
beta). Verified tool catalog at doc version 0.442
(`policies/system-policy.yaml`) exposes `artifactory_artifacts_get_summary`
and repository/build tools, but **no artifact-delete tool** was found in
that catalog version. Candidate discovery may use an MCP tool if one is
discovered at connect time (Section 23); deletion currently routes
through the REST fallback below until/unless a verified MCP delete tool
is confirmed present for your deployed server version.

## API fallback

JFrog Artifactory REST API:

- **Find candidates**: Artifactory Query Language (AQL) via
  `POST /artifactory/api/search/aql` — e.g. a `created` or
  `stat.downloaded` range query scoped to one repository. AQL is the
  officially documented mechanism for exactly this kind of query
  (`docs.jfrog.com`).
- **Delete**: `DELETE /artifactory/{repo-key}/{item-path}` — standard
  Artifactory item-delete endpoint.

Scripts: `scripts/windows/find-old-artifacts.ps1` /
`scripts/unix/find-old-artifacts.sh` (read), and
`scripts/windows/delete-artifacts.ps1` / `scripts/unix/delete-artifacts.sh`
(destructive — signatures match Section 26's worked example exactly).

## Authentication

JFrog Platform access token (local POC:
`.github/local-secrets/jfrog-token.txt`; production: secret
manager/credential broker). Sent as `Authorization: Bearer <token>`.

## Read operations

AQL search for candidates, artifact summary/size lookup: `READ_ONLY`.

## Write operations

`DELETE artifact(s)`: `DESTRUCTIVE` (Section 16: "DELETE Artifactory
artifact" = DESTRUCTIVE). Always requires `APPROVE DELETE`, one approval
per enumerated batch — see Approval rules.

## Approval rules

Before requesting approval, the agent MUST present, in this order:

1. The full candidate list (or a bounded, clearly-labeled sample plus
   total count if the list is very large).
2. Total artifact count.
3. Total storage size reclaimed.
4. The retention criteria used (e.g. "created > 180 days ago AND 0
   downloads in the last 90 days").
5. Risk classification (`DESTRUCTIVE`).

Only then does it call `request-approval` with phrase `APPROVE DELETE`,
proposing at **repository** scope (`Test-ApprovalToken`/
`test_approval_token` binds the resulting token to `System=jfrog`,
`Target=<Repository>`, `Operation=jfrog.artifact.delete`). **Never
perform bulk deletion directly from the original natural-language
request** — "delete those artifacts" always triggers this full pipeline,
never a shortcut. The approved `operationId` authorizes deleting only
within that one repository; `delete-artifacts.ps1`/`.sh` takes the exact
`CandidatePaths` list as an explicit parameter, and the calling
agent/Skill is the trust boundary ensuring that list is identical to
what was shown in the proposal — it must never pass a path the human did
not see and approve. Per-repository binding still prevents an approval
issued for one repository being replayed against a different one
(Section 32: an approval for repository A must not authorize repository B).

## Security

Repository keys and artifact paths are validated against
`^[A-Za-z0-9_][A-Za-z0-9_./-]*$` and checked for path traversal (`..`)
before being placed in a URL. No `curl -k`/TLS bypass. No
`Invoke-Expression`/`iex`/`eval`.

## Verification

After DELETE, `GET /artifactory/{repo-key}/{item-path}` (or AQL re-query)
is expected to return `404 Not Found` / zero results for every deleted
path. Any path that still resolves is reported as `verification: FAILED`
for that specific item — the script does not treat a partial batch
failure as an overall success.

## Audit

One audit record per deleted artifact path, `resource: artifact`,
`risk: DESTRUCTIVE`, `skill: jfrog-cleanup`, including repo key and path
as `target`.

## Rollback

**NOT GUARANTEED.** Artifactory does not provide a native "undelete"
for standard local repositories. If your Artifactory edition/repository
type has a trash-can/retention feature enabled, recovery may be possible
within its retention window — this framework does not assume that
feature is enabled and will not claim rollback unless you have
separately confirmed it.

## Examples

```
User: Find artifacts older than 180 days in releases-local.
Agent: READ_ONLY -> AQL query -> lists candidates (count + total size), no approval needed.

User: Delete those artifacts.
Agent: Re-shows candidate list + count + total size + retention criteria + risk
       -> APPROVE DELETE -> EXECUTE (one DELETE per approved path) ->
       VERIFY (404 for each) -> AUDIT (one record per path) -> REPORT
```
