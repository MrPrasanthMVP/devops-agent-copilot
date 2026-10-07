---
name: bitbucket-file-management
description: Browse files/directories and commit file changes directly to a Bitbucket Data Center 9.4.5 repository branch (without a local clone). Use for requests to view a file's content, list a directory, or commit a file change directly via the API/MCP.
license: Proprietary - internal enterprise use
---

## Purpose

Read file/directory contents and perform direct (non-PR) file commits
against a Bitbucket Data Center repository branch.

## Scope

File browsing and direct-commit file edits. Pull request creation/review
-> `bitbucket-pull-requests`.

## When to use

"Show me the contents of README.md on branch main in repository X",
"List files under src/ in repository X", "Commit a change to file Y
directly on branch main" (note: direct commits to protected branches are
still subject to `bitbucket-branch-permissions`).

## When not to use

Changes intended for review -> propose a pull request via
`bitbucket-pull-requests` instead of a direct commit.

## MCP dependency

Official "MCP for Bitbucket DC" explicitly documents "browse commits and
read file contents" and "commit file changes directly" as supported
capabilities. Discover the exact tool names at connect time (Section 23)
rather than assuming them.

## API fallback

- `GET /rest/api/1.0/projects/{projectKey}/repos/{repositorySlug}/browse/{path}` — browse/read
- `PUT /rest/api/1.0/projects/{projectKey}/repos/{repositorySlug}/browse/{path}` — commit a file change
  (multipart form: content, message, branch, sourceCommitId)

Reference: `https://developer.atlassian.com/server/bitbucket/rest/`.

## Authentication

Bitbucket HTTP access token with repository write permission for commits;
read permission suffices for browsing.

## Read operations

Browse directory, read file content: `READ_ONLY`.

## Write operations

Direct file commit: `WRITE`. If the target branch is protected
(`bitbucket-branch-permissions`), the operation additionally requires
that the token/user is permitted to write directly per that branch's
restriction — the agent checks this before proposing, not after.

## Approval rules

`APPROVE UPDATE` (or `APPROVE CREATE` for a new file). The proposal shows
a diff-style current-vs-proposed content summary (not necessarily the
full file for large files — a truncated diff with a note is acceptable,
but never silently omitted).

## Security

File paths are validated against path-traversal (`..`) before use.
Binary/large file content is handled via the multipart API, never
inlined into a shell/PowerShell command string (avoids injection and
command-length issues).

## Verification

Commit -> `GET` the file at the resulting commit -> compare content
hash/size to what was proposed.

## Audit

Logged as `resource: file`, `risk: WRITE`, with the file path and commit
id (never full file content, to keep audit records bounded and avoid
leaking secrets that might be embedded in a file).

## Rollback

A direct commit can be reverted by a follow-up commit restoring the prior
content (itself a new approved `WRITE` operation) — Bitbucket does not
"undo" a commit from history via the REST API.

## Examples

```
User: Show the contents of README.md on main in repository XYZ.
Agent: READ_ONLY -> GET browse API -> returns content directly, no approval needed.

User: Update the version number in package.json on main in repository XYZ.
Agent: READ current content -> PROPOSE (diff shown, risk: WRITE) -> APPROVE UPDATE
       -> EXECUTE (commit) -> VERIFY (re-read, compare) -> AUDIT
```
