# How to use this framework

A short, practical walkthrough. For full reference (architecture,
security model, every Skill, production hardening) see `README.md`,
`SECURITY.md`, and `CONTRIBUTING.md`. For versions/URLs, see
`policies/versions-and-sources.yaml` (the single source of truth —
never hand-edit a version or URL anywhere else).

## 1. First-time setup (local POC)

1. Clone this repository.
2. Copy each local-secret template and fill in a real credential —
   **never commit the copy**:
   ```
   .github/local-secrets/bitbucket-token.txt.example  -> bitbucket-token.txt
   .github/local-secrets/jfrog-token.txt.example       -> jfrog-token.txt
   .github/local-secrets/github-token.txt.example      -> github-token.txt
   .github/local-secrets/sonarqube-token.txt.example   -> sonarqube-token.txt
   .github/local-secrets/jira-email.txt.example        -> jira-email.txt   (only if using the Jira/Confluence REST fallback)
   .github/local-secrets/jira-token.txt.example        -> jira-token.txt   (only if using the Jira/Confluence REST fallback)
   ```
3. Replace the placeholder hostnames in `.mcp.json` and
   `.vscode/mcp.json` (`bitbucket.example.internal`,
   `artifactory.example.internal`) with your real Bitbucket/JFrog base
   URLs. The Atlassian Rovo and GitHub hosted MCP endpoints are already
   correct — leave them as-is. For SonarQube, fill in the `sonarqube`
   entry's `env` block: `SONARQUBE_TOKEN` always, plus either
   `SONARQUBE_URL` (Server/Community Build, self-managed) or
   `SONARQUBE_ORG` (Cloud) — see `policies/versions-and-sources.yaml#sonarqube`.
4. Run the validators once to confirm the repo is intact:
   ```
   ./scripts/validation/validate-repository.ps1   # or .sh
   ./scripts/validation/validate-skills.ps1        # or .sh
   ./scripts/validation/validate-security.ps1      # or .sh
   ./scripts/validation/validate-versions.ps1      # or .sh
   ```
   All four should print `PASS`.

## 2. Open it in VS Code

1. Open the repository folder in VS Code with GitHub Copilot installed.
2. In Copilot Chat, pick the **Enterprise DevOps Agent** from the agent
   picker (`.github/agents/enterprise-devops.agent.md`).
3. The first time you touch an MCP server that needs a secret
   (Bitbucket, JFrog, SonarQube), VS Code will prompt you for the token
   via the `inputs` mechanism in `.vscode/mcp.json` — paste the same
   value you put in the matching `.github/local-secrets/*.txt` file.
4. Try a read-only question first, e.g. *"list repositories in project
   ABC"* — this should answer directly, no approval prompt.

## 3. Use it from Copilot CLI

1. Start `copilot` inside the repository.
2. Select the custom agent (`/agent` → Enterprise DevOps Agent, or
   `copilot --agent enterprise-devops --prompt "..."`).
3. Skills under `.github/skills/` are auto-discovered. MCP servers come
   from `.mcp.json` — add real bearer tokens for Bitbucket/JFrog via
   `copilot mcp add --header "Authorization: Bearer <token>"` at the CLI
   (never paste a token into the committed `.mcp.json`). SonarQube's
   entry is a local/stdio server (not HTTP), so its credential instead
   goes in that entry's `env` block (`SONARQUBE_TOKEN` plus
   `SONARQUBE_URL` or `SONARQUBE_ORG`) — edit your local, uncommitted
   copy of `.mcp.json`, never the one tracked in git.

## 4. The core loop: every write follows the same pattern

```
You:    Delete repository TEST
Agent:  Reads current state, then shows:

        PROPOSED OPERATION
        System: bitbucket
        Target: PROJ/TEST
        Operation: bitbucket.repository.delete
        Risk: DESTRUCTIVE
        Impact: Permanent repository deletion. Not reversible via API.
        Explicit approval required. Type: APPROVE DELETE

You:    APPROVE DELETE
Agent:  Executes, re-reads the result to verify, writes an audit
        record, and reports success/failure — never a guess.
```

Things that will **not** work, by design:
- Typing `yes`, `ok`, `sure`, or `proceed` instead of the exact phrase.
- Asking twice in a row — each proposal has its own `operationId` and
  expires after 15 minutes if unconfirmed.
- Approving one target and expecting it to cover a different one (e.g.
  approving deletion of `TEST` does not authorize deleting `TEST-2`).

See `.github/skills/human-approval/references/approval-types.md` for
the full table of required phrases (`APPROVE CREATE`, `APPROVE DELETE`,
`APPROVE MERGE`, `APPROVE PERMISSION CHANGE`, etc.) and which risk
category each applies to.

## 5. Finding the right Skill

Skills are organized by system and resource under `.github/skills/`.
If you're not sure which one covers your request, ask the agent — it
will tell you which Skill it's routing through, or say the capability
isn't implemented rather than guessing. A few entry points:

| You want to... | Skill |
|---|---|
| Manage Bitbucket repos/projects | `bitbucket-repository-admin`, `bitbucket-project-admin` |
| Merge or review a Bitbucket/GitHub PR | `bitbucket-pull-requests`, `github-pull-requests` |
| Change branch protection | `github-branch-protection`, `bitbucket-branch-permissions` |
| Clean up old/large JFrog artifacts | `jfrog-cleanup` |
| Edit a Jira issue or Confluence page | `jira-issues`, `confluence-pages` |
| Check/assign a SonarQube issue or hotspot | `sonarqube-issues`, `sonarqube-hotspots` |
| Create/delete a SonarQube project or quality gate | `sonarqube-projects`, `sonarqube-quality-gates` |
| Change who can access something | any `*-permissions` skill (always `SECURITY_SENSITIVE`) |

## 6. Checking what happened

- **Audit trail**: `logs/enterprise-devops-audit.jsonl` — one JSON line
  per operation, read or write, with credentials always redacted.
- **Dry run**: most write scripts support `-WhatIf` (PowerShell) /
  `--dry-run` (Bash) to see the planned call without executing it.
- **Something says `NOT IMPLEMENTED`**: that means official documentation
  couldn't verify the capability at build time — see `CONTRIBUTING.md`
  to add it properly rather than working around it.

## 7. Going to production

This repo starts as a local POC (token files on disk). Before rolling
it out beyond your own machine, read README.md's "Production
Hardening" section — the short version: replace local token files with
OAuth/OIDC/GitHub Apps/a secret manager, forward the audit log to your
SIEM, and apply least-privilege to every credential this framework
uses.
