---
name: github-branch-protection
description: View and change GitHub Enterprise (Cloud or Server) branch protection rules -- required reviews, required status checks, admin enforcement, force-push/deletion restrictions. Use for any request to protect, lock down, or change push/merge rules on a branch.
license: Proprietary - internal enterprise use
---

## Purpose

Manage classic branch protection configuration on GitHub Enterprise
repositories.

## Scope

Classic branch-protection API. Repository rulesets (the newer, more
flexible mechanism) -> `github-rulesets`. General repo settings ->
`github-repositories`.

## When to use

"Show branch protection for main", "Require two reviewers for main",
"Require status check X before merge on main", "Prevent force-push to
release/*".

## When not to use

If the organization uses Rulesets instead of classic branch protection,
route to `github-rulesets`. Ask/check which mechanism is in use if
ambiguous — do not assume.

## MCP dependency

**GitHub's official hosted MCP server**
(`https://docs.github.com/en/copilot/how-tos/provide-context/use-mcp-in-your-ide/set-up-the-github-mcp-server`,
`https://github.com/github/github-mcp-server`), connected at
`https://api.githubcopilot.com/mcp/` for GitHub Enterprise **Cloud**, or
the self-hosted `github-mcp-server` build pointed at the Enterprise
**Server** hostname (Section 5/21 — never assume Cloud/Server
interchangeably). Discover the exact branch-protection tool at connect
time rather than assuming a name (Section 23).

## API fallback

GitHub REST API — branch protection
(`https://docs.github.com/en/rest/branches/branch-protection`):

- `GET /repos/{owner}/{repo}/branches/{branch}/protection` — read
- `PUT /repos/{owner}/{repo}/branches/{branch}/protection` — set (full
  replace of the protection object — the proposal must show the FULL
  resulting object, not just the changed field, since this endpoint
  replaces rather than patches)
- `DELETE /repos/{owner}/{repo}/branches/{branch}/protection` — remove all protection

Scripts: `scripts/windows/get-branch-protection.ps1` / `scripts/unix/get-branch-protection.sh` (read),
`scripts/windows/update-branch-protection.ps1` / `scripts/unix/update-branch-protection.sh`
(write, via `scripts/common/Common.psm1` / `common.sh`).

## Authentication

GitHub token (local POC: `.github/local-secrets/github-token.txt`;
production: GitHub App installation token — Section 12/49) with
repository admin permission.

## Read operations

Get current branch protection: `READ_ONLY`.

## Write operations

Set/remove branch protection: `ADMINISTRATIVE`
(`APPROVE BRANCH PROTECTION`, per Section 8's dedicated phrase and
Section 51's worked example).

## Approval rules

The PROPOSED OPERATION must show the **current full protection object**
(from `get-branch-protection`) and the **proposed values** side by side —
because the underlying API call is a full replace, the executing script
(`update-branch-protection.ps1`/`.sh`) always sends a complete
protection payload (currently: `required_approving_review_count`,
`enforce_admins`, with `required_status_checks`/`restrictions` cleared)
rather than a partial patch, so the agent must surface that this is a
full-replace operation and confirm no other existing protection setting
is being silently dropped.

## Security

Branch name validated for shape; no shell/URL injection via branch
names. TLS validation always on.

## Verification

Set -> `GET` branch protection -> compare the full object field-by-field
against what was proposed. Remove -> `GET` -> expect `404`.

## Audit

Logged as `system: github`, `resource: branch_protection`,
`risk: ADMINISTRATIVE`.

## Rollback

Revert to the previously-read full protection object (captured before
the change) — reversible, requires its own approval. Remove-protection:
reversible by re-applying the prior object, but there is a real window
where the branch is unprotected — flagged in the proposal.

## Examples

```
User: Show branch protection for main.
Agent: READ_ONLY -> GET -> returns current config directly, no approval needed.

User: Require two reviewers for main.
Agent: READ current full protection object -> PROPOSE (current vs. full proposed
       object with required_pull_request_reviews.required_approving_review_count=2,
       risk: ADMINISTRATIVE) -> APPROVE BRANCH PROTECTION -> EXECUTE -> VERIFY -> AUDIT
```
