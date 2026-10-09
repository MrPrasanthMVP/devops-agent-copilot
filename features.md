# Features — what's actually available, and how

A capability matrix for every one of the 48 Skills in
`.github/skills/`: what operation it covers, its approval risk
category, whether an **official MCP tool** is confirmed/expected to
cover it, and whether a **runnable fallback script** (`.ps1`+`.sh`
pair) already exists in this repo today.

This is a snapshot of what's *implemented right now*, not a wishlist —
see `policies/operation-classification.yaml` for risk-category
definitions and `policies/versions-and-sources.yaml` for every
official-doc URL cited below.

## Legend

**Risk** — does this need human approval before it runs?
- `READ_ONLY` — just looking, runs immediately, no approval.
- `WRITE` / `ADMINISTRATIVE` / `SECURITY_SENSITIVE` / `DESTRUCTIVE` — changes something; all four require typing the exact approval phrase first (`policies/approval-policy.yaml`). `DESTRUCTIVE` is the irreversible-or-nearly-so tier (e.g. delete).

**MCP** — how the official connector for that system is expected to handle this operation:
- `Discover` — the vendor's official MCP server exists and should be able to do this, but we don't hardcode which exact tool it uses. The agent asks the server "what tools do you have?" when it connects and picks the matching one live. (This is deliberate — the vendor's tool catalog can change, so we never guess a name in advance.)
- `Verified` — we already confirmed the exact tool name exists in the vendor's published tool list (named in the Skill's `SKILL.md`), not just "should be there."
- `Not in catalog` — we checked the vendor's published tool list and confirmed this capability is **missing** from it. MCP cannot do this; it must go through the plain REST API instead.

**Script** — is there an actual, runnable backup file for this in the repo *right now*?
- `Yes` — a real `.ps1` (Windows) and `.sh` (Linux/macOS) file both exist under that Skill's `scripts/` folder. You (or the agent) can run this directly against the REST API even if MCP is unavailable or doesn't cover the operation.
- `No` — no such file exists yet. Today, this operation can only be done through MCP (if the MCP column says `Discover`/`Verified`). If MCP can't do it either, nobody can run this operation through the framework yet — a script would first need to be written and approved via the `APPROVE SCRIPT CREATION` → `APPROVE EXECUTION` process (see `SKILL.md` → "Approval rules" for any Skill, Section 33).
- `Not implemented` — neither MCP nor a script covers this; we couldn't verify an official way to do it at all, so we deliberately left it out rather than guessing.

---

## Bitbucket Data Center (all versions supported)

MCP: official **"MCP for Bitbucket DC"** (`policies/versions-and-sources.yaml#bitbucket`), tools discovered at connect time — no fixed names assumed anywhere below.

| Skill | Operation | Risk | MCP | Script |
|---|---|---|---|---|
| `bitbucket-admin` | Get instance version/properties | READ_ONLY | Discover | No |
| `bitbucket-admin` | Instance-wide write settings | — | — | **Not implemented** (no verified endpoint) |
| `bitbucket-project-admin` | List/get project | READ_ONLY | Discover | Yes |
| `bitbucket-project-admin` | Create project | ADMINISTRATIVE | Discover | Yes |
| `bitbucket-project-admin` | Update project | WRITE | Discover | Yes |
| `bitbucket-project-admin` | Delete project | DESTRUCTIVE | Discover | Yes |
| `bitbucket-repository-admin` | List/get repository, default branch, settings | READ_ONLY | Discover | Yes |
| `bitbucket-repository-admin` | Create repository | ADMINISTRATIVE | Discover | Yes |
| `bitbucket-repository-admin` | Update name / default branch | WRITE | Discover | Yes |
| `bitbucket-repository-admin` | Delete repository | DESTRUCTIVE | Discover | Yes |
| `bitbucket-permissions` | List grants | READ_ONLY | Discover | No |
| `bitbucket-permissions` | Grant/change/revoke permission | SECURITY_SENSITIVE | Discover | No |
| `bitbucket-branch-permissions` | List restrictions | READ_ONLY | Discover | No |
| `bitbucket-branch-permissions` | Create/remove branch restriction | ADMINISTRATIVE | Discover | No |
| `bitbucket-hooks` | List/get hook config | READ_ONLY | Discover | No |
| `bitbucket-hooks` | Enable/disable/configure hook | ADMINISTRATIVE | Discover | No |
| `bitbucket-webhooks` | List/get webhook | READ_ONLY | Discover | No |
| `bitbucket-webhooks` | Create/update/delete webhook | SECURITY_SENSITIVE | Discover | No |
| `bitbucket-merge-settings` | Get merge strategy config | READ_ONLY | Discover | No |
| `bitbucket-merge-settings` | Change allowed/default merge strategy | ADMINISTRATIVE | Discover | No |
| `bitbucket-merge-checks` | Get required-approvals/build config | READ_ONLY | Discover | No |
| `bitbucket-merge-checks` | Change required approvers/builds | ADMINISTRATIVE | Discover | No |
| `bitbucket-pull-requests` | List/get PR, list comments | READ_ONLY | Discover | No (read script not yet written) |
| `bitbucket-pull-requests` | Create / comment / approve PR | WRITE | Discover | No |
| `bitbucket-pull-requests` | Merge PR | WRITE (admin-override escalates to ADMINISTRATIVE too) | Discover | Yes |
| `bitbucket-file-management` | Browse directory / read file | READ_ONLY | Discover | No |
| `bitbucket-file-management` | Direct file commit | WRITE | Discover | No |

---

## Jira Cloud

MCP: official **Atlassian Rovo MCP Server** (`policies/versions-and-sources.yaml#jira`), OAuth 2.1, dynamic tool catalog resolved via its `discover`/`executeRead`/`executeWrite`/`executeDestructive` meta-tools.

| Skill | Operation | Risk | MCP | Script |
|---|---|---|---|---|
| `jira-admin` | List/get project, project types | READ_ONLY | Discover | Yes |
| `jira-admin` | Create project | ADMINISTRATIVE | Discover | Yes |
| `jira-admin` | Update project | WRITE | Discover | Yes |
| `jira-admin` | Delete project | DESTRUCTIVE | Discover | **Not implemented** |
| `jira-issues` | Search (JQL), get issue, list comments | READ_ONLY | Verified primaries (`getJiraIssue`, `searchJiraIssuesUsingJql`) | Yes |
| `jira-issues` | Create issue | WRITE | Verified (`createJiraIssue`) | No |
| `jira-issues` | Edit issue field | WRITE | Verified (`editJiraIssue`) | Yes |
| `jira-issues` | Transition issue | WRITE | Verified (`transitionJiraIssue`) | No |
| `jira-issues` | Comment on issue | WRITE | Verified (`addOrEditJiraIssueComment`) | No |
| `jira-issues` | Delete issue | DESTRUCTIVE | Discover | **Not implemented** |
| `jira-permissions` | List scheme/grants | READ_ONLY | Discover | Yes |
| `jira-permissions` | Add/remove permission grant | SECURITY_SENSITIVE | Discover | Yes |
| `jira-workflows` | List workflows/schemes | READ_ONLY | Discover | Yes |
| `jira-workflows` | Change workflow scheme association | ADMINISTRATIVE | Discover | Yes (scheme-association only; structural workflow edits are **not implemented** — no verified REST write endpoint) |

---

## Confluence Cloud

MCP: same **Atlassian Rovo MCP Server** connection as Jira (`policies/versions-and-sources.yaml#confluence`).

| Skill | Operation | Risk | MCP | Script |
|---|---|---|---|---|
| `confluence-admin` | List/get space | READ_ONLY | Verified (`listConfluenceSpaces`) | Yes |
| `confluence-admin` | Create space | ADMINISTRATIVE | Discover | No |
| `confluence-admin` | Archive/delete space | DESTRUCTIVE | Discover | No |
| `confluence-pages` | Search/find, get page | READ_ONLY | Verified (`getConfluenceContent`, `listConfluenceContent`, `searchConfluence`) | Yes |
| `confluence-pages` | Create page | WRITE | Verified (`createConfluenceContent`) | No |
| `confluence-pages` | Update page | WRITE | Verified (`updateConfluenceContent`) | Yes |
| `confluence-permissions` | List permissions/restrictions | READ_ONLY | Discover | Yes |
| `confluence-permissions` | Grant/change/revoke permission | SECURITY_SENSITIVE | Discover | Yes |

---

## JFrog Artifactory Self-Managed

MCP: official **JFrog MCP Server** (beta; `policies/versions-and-sources.yaml#jfrog`). Tool catalog verified at doc version 0.442 — several resource types (artifact delete, users, groups, permission targets) are **confirmed absent** from that catalog and route to REST fallback.

| Skill | Operation | Risk | MCP | Script |
|---|---|---|---|---|
| `jfrog-admin` | Version discovery, list tokens/OIDC | READ_ONLY | Verified (`access_tokens_list`) | Yes (version discovery, under `scripts/jfrog/`) |
| `jfrog-admin` | Create/revoke access token | SECURITY_SENSITIVE | Verified (`access_tokens_create`, `access_tokens_revoke`) | No |
| `jfrog-admin` | Create OIDC config | SECURITY_SENSITIVE | Verified (`access_oidc_create_configuration`) | No |
| `jfrog-repositories` | List/get repository config | READ_ONLY | Verified (`artifactory_repositories_get/list`) | Yes |
| `jfrog-repositories` | Create/update repository | ADMINISTRATIVE | Verified (`artifactory_repositories_create/update`) | Yes (create); update **not implemented** as script |
| `jfrog-repositories` | Delete repository | DESTRUCTIVE | Not in catalog → REST fallback | Yes |
| `jfrog-artifacts` | Find/inspect artifacts, properties, stats | READ_ONLY | Verified (`artifactory_artifacts_get_summary`) + Discover | Yes |
| `jfrog-cleanup` | Find candidates (AQL) | READ_ONLY | Discover | Yes |
| `jfrog-cleanup` | Delete artifact batch | DESTRUCTIVE | Not in catalog → REST fallback | Yes |
| `jfrog-permissions` | Get permission target | READ_ONLY | Not in catalog → REST fallback | Yes |
| `jfrog-permissions` | Create/update permission target | SECURITY_SENSITIVE | Not in catalog → REST fallback | Yes |
| `jfrog-users` | Get/list user | READ_ONLY | Not in catalog → REST fallback | Yes |
| `jfrog-users` | Create user | ADMINISTRATIVE | Not in catalog → REST fallback | Yes |
| `jfrog-users` | Delete user | DESTRUCTIVE | Not in catalog → REST fallback | Yes |
| `jfrog-groups` | List/get group, members | READ_ONLY | Not in catalog → REST fallback | Yes |
| `jfrog-groups` | Create/update/delete group, membership | ADMINISTRATIVE/SECURITY_SENSITIVE/DESTRUCTIVE | Not in catalog → REST fallback | Yes |
| `jfrog-projects` | List/get project | READ_ONLY | Verified (`access_projects_get/list_projects`) | No |
| `jfrog-projects` | Create/update project, role/user/group upsert, repo move | ADMINISTRATIVE/SECURITY_SENSITIVE | Verified (`access_projects_create/update/create_role/upsert_user/upsert_group/move_repository_to_project`) | No |
| `jfrog-projects` | Delete project | DESTRUCTIVE | Not in catalog → REST fallback | Yes |
| `jfrog-xray` | Vulnerability/license lookup | READ_ONLY | Verified (`catalog_vulnerabilities_get`, `catalog_packages_get`, `curation_packages_get_status`) | No |
| `jfrog-build-info` | List builds/runs, get build info | READ_ONLY | Verified (`artifactory_builds_list_builds/list_build_runs/get_info`) | No |

---

## SonarQube (Server + Cloud)

MCP: official **SonarQube MCP Server** (SonarSource; `policies/versions-and-sources.yaml#sonarqube`), supports BOTH SonarQube Server/Community Build (self-managed) and SonarQube Cloud via `SONARQUBE_URL`/`SONARQUBE_ORG`. Every script also accepts `-Organization`/`--organization` directly for Cloud.

| Skill | Operation | Risk | MCP | Script |
|---|---|---|---|---|
| `sonarqube-projects` | List/get project | READ_ONLY | Verified (`search_my_sonarqube_projects`) | Yes |
| `sonarqube-projects` | Create project | WRITE | Not in catalog → REST fallback | Yes |
| `sonarqube-projects` | Delete project | DESTRUCTIVE | Not in catalog → REST fallback | Yes |
| `sonarqube-quality-gates` | List quality gates | READ_ONLY | Verified (`list_quality_gates`) | Yes |
| `sonarqube-quality-gates` | Get project quality gate status | READ_ONLY | Verified (`get_project_quality_gate_status`) | Yes |
| `sonarqube-quality-gates` | Select quality gate for project | WRITE | Not in catalog → REST fallback | Yes |
| `sonarqube-issues` | Search issues | READ_ONLY | Verified (`search_sonar_issues_in_projects`) | Yes |
| `sonarqube-issues` | Assign issue | WRITE | Not in catalog → REST fallback | Yes |
| `sonarqube-issues` | Transition issue | WRITE | Verified but narrower vocabulary (`change_sonar_issue_status`: accept/falsepositive/reopen only) → full 6-value state machine always uses REST fallback | Yes |
| `sonarqube-hotspots` | Search hotspots | READ_ONLY | Verified (`search_security_hotspots`) | Yes |
| `sonarqube-hotspots` | Get hotspot | READ_ONLY | Verified (`show_security_hotspot`) | Yes |
| `sonarqube-hotspots` | Change hotspot status | WRITE | Verified (`change_security_hotspot_status`) | Yes |
| `sonarqube-admin` | Get system health (Server only) | READ_ONLY | Verified (`get_system_health`) | Yes |
| `sonarqube-admin` | Get system info (Server only) | READ_ONLY | Verified (`get_system_info`) | Yes |
| `sonarqube-admin` | Ping system (Server only) | READ_ONLY | Verified (`ping_system`) | Yes |
| `sonarqube-admin` | Get system logs (Server only) | READ_ONLY | Verified (`get_system_logs`) | No (not yet scripted) |
| `sonarqube-webhooks` | List webhooks | READ_ONLY | Verified (`list_webhooks`) | Yes |
| `sonarqube-webhooks` | Create webhook | WRITE | Verified (`create_webhook`) | Yes |
| `sonarqube-webhooks` | Delete webhook | DESTRUCTIVE | Not in catalog → REST fallback | Yes |

---

## GitHub Enterprise (Cloud or Server)

MCP: official hosted server for Cloud (`api.githubcopilot.com/mcp/`) or the self-hosted `github-mcp-server` build for Server — see `policies/versions-and-sources.yaml#github`. All tools resolved by discovery; none hardcoded.

| Skill | Operation | Risk | MCP | Script |
|---|---|---|---|---|
| `github-enterprise-admin` | Audit log query, list orgs | READ_ONLY | Discover | No |
| `github-enterprise-admin` | Enterprise-wide config change | ADMINISTRATIVE/SECURITY_SENSITIVE | Discover | **Not implemented** |
| `github-organizations` | Get org settings | READ_ONLY | Discover | No |
| `github-organizations` | Change org settings | ADMINISTRATIVE/SECURITY_SENSITIVE | Discover | No |
| `github-repositories` | List/get repository | READ_ONLY | Discover | No |
| `github-repositories` | Create / update / archive repository | WRITE/ADMINISTRATIVE/SECURITY_SENSITIVE | Discover | No |
| `github-repositories` | Delete repository | DESTRUCTIVE | Discover | No |
| `github-teams` | List/get team, members, repos | READ_ONLY | Discover | No |
| `github-teams` | Create/update/delete team, membership, repo access | ADMINISTRATIVE/SECURITY_SENSITIVE/DESTRUCTIVE | Discover | No |
| `github-permissions` | List collaborators | READ_ONLY | Discover | No |
| `github-permissions` | Add/update/remove collaborator permission | SECURITY_SENSITIVE | Discover | No |
| `github-branches` | List branches | READ_ONLY | Discover | No |
| `github-branches` | Create/delete branch | WRITE/DESTRUCTIVE | Discover | No |
| `github-branch-protection` | Get branch protection | READ_ONLY | Discover | Yes |
| `github-branch-protection` | Set/update branch protection | ADMINISTRATIVE | Discover | Yes |
| `github-rulesets` | List/get ruleset | READ_ONLY | Discover | No |
| `github-rulesets` | Create/update/delete ruleset | ADMINISTRATIVE/SECURITY_SENSITIVE/DESTRUCTIVE | Discover | No |
| `github-pull-requests` | List/get PR, reviews/comments | READ_ONLY | Discover | No |
| `github-pull-requests` | Create / review / merge PR | WRITE | Discover | No |
| `github-actions` | List workflow runs, get Actions permissions | READ_ONLY | Discover (toolset variant `/mcp/x/actions` on Cloud) | No |
| `github-actions` | Create/update/delete secret or variable | SECURITY_SENSITIVE/WRITE | Discover | No |
| `github-actions` | Change Actions permissions | SECURITY_SENSITIVE | Discover | No |
| `github-runners` | List runners/groups | READ_ONLY | Discover | No |
| `github-runners` | Remove runner / update runner group | ADMINISTRATIVE/SECURITY_SENSITIVE | Discover | No |
| `github-webhooks` | List/get webhook | READ_ONLY | Discover | No |
| `github-webhooks` | Create/update/delete webhook | SECURITY_SENSITIVE | Discover | No |
| `github-security` | Get security config, list alerts | READ_ONLY | Discover | No |
| `github-security` | Enable/disable scanning feature | ADMINISTRATIVE/SECURITY_SENSITIVE | Discover | No |
| `github-security` | Dismiss/resolve alert | WRITE | Discover | No |

---

## Framework core (`human-approval`)

Not a target-system integration — the approval engine itself, used by every skill above.

| Capability | Script |
|---|---|
| Propose an operation (PROPOSED OPERATION block + staged proposal) | `request-approval.ps1` / `.sh` |
| Confirm the human's phrase and mint a signed, single-use approval token | `confirm-approval.ps1` / `.sh` |
| Verify a token is valid/bound/unconsumed before executing (CLI wrapper) | `verify-approval.ps1` / `.sh` |
| Shared engine every execution script imports directly (HMAC signing, audit logging, secure HTTP, operation-classification lookup) | `scripts/common/Common.psm1` / `scripts/common/common.sh` |
| Mandatory version/deployment discovery (never hardcoded) | `scripts/bitbucket/get-version.*`, `scripts/jfrog/get-version.*`, `scripts/github/get-deployment-info.*` |

---

## Reading this matrix

- **"Script: No" does not mean unusable** — for most read operations and several writes, the agent can act directly through the MCP tool it discovers at connect time; a dedicated fallback script is only strictly required when MCP doesn't cover the operation (checked explicitly for JFrog's `Not in catalog` rows) or when you want a scriptable, approval-gated REST path independent of MCP availability.
- **"Not implemented"** means no verified official endpoint/tool was found for that specific operation at build time (Section 1/57) — it is deliberately excluded rather than guessed. See the relevant `SKILL.md`'s "API fallback" section for the exact reasoning, and `CONTRIBUTING.md` for how to add it once you've verified a real endpoint.
- Every `Yes` script has both a `.ps1` and a `.sh` implementation (PowerShell/Bash parity, Section 24) and goes through the same approval gate (`Test-ApprovalToken` / `test_approval_token`) before mutating anything.
