# enterprise-devops-copilot

An Enterprise DevOps Copilot Control Framework: a GitHub Copilot custom
agent, a library of Skills, and a policy/approval/audit layer that lets
developers and administrators drive Bitbucket Data Center, Jira Cloud,
Confluence Cloud, JFrog Artifactory (Self-Managed), and GitHub
Enterprise safely from VS Code or Copilot CLI - starting as a local POC
and designed to grow into a centrally governed enterprise platform.

This repository was generated against the master specification in
`requirement.md`. Where an MCP tool, REST endpoint, or Copilot/VS Code
configuration syntax could not be verified against official
documentation, it is explicitly marked
`NOT IMPLEMENTED — OFFICIAL DOCUMENTATION/API VERIFICATION REQUIRED`
inside the relevant `SKILL.md` rather than guessed.

**New here?** See [`how_to_use.md`](how_to_use.md) for a short,
practical walkthrough (setup, VS Code, Copilot CLI, the approval loop)
before reading the full reference below.

## Overview

Every mutating operation goes through the same pipeline, enforced by the
`human-approval` Skill and the Enterprise DevOps Agent:

```
READ -> ANALYZE -> PROPOSE -> SHOW CURRENT STATE -> SHOW PROPOSED STATE ->
CLASSIFY RISK -> REQUEST HUMAN APPROVAL -> EXECUTE -> VERIFY -> AUDIT -> REPORT
```

Read-only operations skip straight to execution. Everything else -
WRITE, DESTRUCTIVE, ADMINISTRATIVE, SECURITY_SENSITIVE - requires an
explicit, operation-bound, single-use human approval. The user's
original request is never itself approval, and generic affirmatives
("yes", "ok", "proceed") never satisfy it.

## Architecture

```
                         ENTERPRISE USER
                               |
                 +-------------+-------------+
                 |                           |
              VS Code                   Copilot CLI
                 |                           |
                 +-------------+-------------+
                               |
                     Enterprise DevOps Agent
                   (.github/agents/enterprise-devops.agent.md)
                               |
        +----------+-----------+-----------+-----------+
        |          |           |           |           |
        v          v           v           v           v
   Bitbucket     Jira      Confluence    JFrog      GitHub
      DC         Cloud        Cloud     Artifactory  Enterprise
        |          |           |           |           |
        v          +-----------+           |           v
   Bitbucket          Rovo MCP          JFrog MCP   GitHub MCP
      MCP                                  |
                                           |
                                      Artifactory
                                           |
                               +-----------+-----------+
                               |
                         Approval Engine (human-approval Skill)
                               |
                         Policy Engine (policies/*.yaml)
                               |
                         Verification (per-Skill GET-after-write)
                               |
                         Audit Logging (logs/enterprise-devops-audit.jsonl)
                               |
                            SIEM (production)
```

Decision process for every operation (`requirement.md` Section 6):

```
USER REQUEST -> IDENTIFY TARGET SYSTEM -> CHECK OFFICIAL MCP
  FOUND -> USE MCP
  NOT FOUND -> CHECK OFFICIAL REST API
    VERIFIED -> FALLBACK SKILL (scripts/windows + scripts/unix)
    NOT VERIFIED -> NOT IMPLEMENTED
```

## How it works — full workflow

The diagrams above show the shape; this section walks through the
actual files and function calls involved, end to end, for a real
request. Two paths exist: the **read path** (short) and the **write
path** (the one with the approval gate). Both start the same way.

### Step 0 — routing

1. You type a request in Copilot Chat (VS Code) or `copilot` (CLI),
   with the **Enterprise DevOps Agent** selected
   (`.github/agents/enterprise-devops.agent.md`).
2. The agent identifies which system you mean (Bitbucket / Jira /
   Confluence / JFrog / GitHub) and which Skill under
   `.github/skills/` covers it, and opens that Skill's `SKILL.md`.
3. It checks the matching MCP server (`.mcp.json` / `.vscode/mcp.json`)
   and discovers the tools that server actually exposes right now — it
   never assumes a tool name in advance (Section 23).

### Read path (no approval needed)

```
Request -> identify Skill -> discover MCP tool (or use the Skill's
read script) -> call it -> return the answer
```

Example: *"list repositories in project ABC"* → the agent calls the
discovered Bitbucket MCP tool (or, if that specific capability isn't
exposed, the Skill's REST-fallback read script, e.g.
`bitbucket-repository-admin/scripts/windows/get-repository.ps1`) and
shows you the result directly. Nothing is written anywhere except one
`READ_ONLY` line in `logs/enterprise-devops-audit.jsonl`.

### Write path (every mutation goes through this)

```
1. READ current state
2. Classify risk          -> policies/operation-classification.yaml/.json
3. PROPOSE                -> request-approval.ps1/.sh stages .proposals/<id>.json
                              and prints the PROPOSED OPERATION block
4. Human types the exact required phrase (e.g. "APPROVE DELETE")
5. CONFIRM                -> confirm-approval.ps1/.sh checks the phrase,
                              then New-ApprovalToken/new_approval_token mints
                              a signed token at logs/.approvals/<id>.json
6. EXECUTE                -> the Skill's own execution script re-checks
                              that exact token itself via
                              Test-ApprovalToken/test_approval_token
                              (system+target+operation+approvalType must
                              match exactly), then calls the MCP tool or
                              the REST API
7. CONSUME                -> Set-ApprovalConsumed/set_approval_consumed marks
                              the token used -- it cannot be replayed
8. VERIFY                 -> the script re-reads the result (GET-after-write)
                              and compares it to what was proposed
9. AUDIT                  -> Write-AuditLog/write_audit_log appends one line
                              to logs/enterprise-devops-audit.jsonl
10. REPORT                -> the agent tells you SUCCESS, FAILURE, or
                              STATUS = UNKNOWN -- never a guess
```

Worked example, start to finish:

```
You:    Delete repository TEST in project PROJ

Agent:  (step 1-2) Reads the repository, classifies
        "bitbucket.repository.delete" as DESTRUCTIVE.

        (step 3) Runs request-approval, which prints:

        PROPOSED OPERATION
        System: bitbucket
        Target: PROJ/TEST
        Operation: bitbucket.repository.delete
        Risk: DESTRUCTIVE
        Impact: Permanent repository deletion. Not reversible via API.
        Explicit approval required. Type: APPROVE DELETE
        (operationId: op-a1b2c3d4e5f6, expires in 900s)

You:    APPROVE DELETE

Agent:  (step 5) confirm-approval matches the phrase exactly and mints
        a signed token for op-a1b2c3d4e5f6.

        (step 6-7) Runs delete-repository.ps1, which re-validates that
        exact token against bitbucket/PROJ-TEST/bitbucket.repository.delete,
        calls DELETE on the Bitbucket REST API, then marks the token consumed.

        (step 8) GETs the repository again -- expects 404.

        (step 9-10) Appends an audit record and reports:
        "Deleted PROJ/TEST. Verification: CONFIRMED (404 on re-check)."
```

What happens if you skip the approval, or get it wrong:

- You say "yes" instead of "APPROVE DELETE" → `confirm-approval` rejects
  it (generic affirmatives never satisfy a protected operation) and no
  token is minted. Nothing executes.
- You approve, but then the agent (or you, scripting directly) tries to
  reuse that `operationId` against a *different* repository →
  `Test-ApprovalToken` rejects it: the token is bound to the exact
  target it was issued for.
- You try to run the delete script directly with no `operationId` at
  all → it has nothing to check, fails immediately with exit code 6
  (`ApprovalDenied`), and never calls the Bitbucket API. This exact
  guarantee — "no approval → must not execute" — is what
  `tests/approval/`, `tests/bitbucket/`, `tests/jira/`,
  `tests/confluence/`, `tests/jfrog/`, and `tests/github/` test for
  every system, independent of any one Skill's own test suite.

### Multiple mutations in one request

If your request implies several writes (e.g. "create a repo, add a
team, and set branch protection"), the agent enumerates them as
separately numbered proposals, each with its own `operationId`, and you
can approve a subset:

```
1. CREATE repository
2. MODIFY team
3. MODIFY branch protection

You: APPROVE 1
     APPROVE 3

Agent: executes 1 and 3; operation 2 stays PENDING until approved separately.
```

### Script creation (when no fallback script exists yet)

If MCP doesn't cover an operation and no fallback script exists either
(see `features.md` for exactly which operations are in that state
today), the agent doesn't write and run one in the same breath. It
first shows a **NEW SCRIPT PROPOSAL** (name, purpose, HTTP method,
parameters, security risks, rollback, verification) and requires
`APPROVE SCRIPT CREATION`. Only after the script exists, unexecuted,
does running it require its own separate `APPROVE EXECUTION` — the two
approvals are never the same `operationId`.

## Supported systems and versions

**Single source of truth: [`policies/versions-and-sources.yaml`](policies/versions-and-sources.yaml).**
Every version number and official-documentation/MCP-endpoint URL in this
framework is defined there exactly once. The table below is a
human-readable summary kept in sync with it (CI's
`validate-versions.ps1`/`.sh` checks for drift) — if you need to bump a
version or change a URL, edit that one file first.

| System | Deployment | Version target |
|---|---|---|
| Bitbucket | Data Center | **9.4.5** exactly (never 10.x-only APIs) |
| Jira | Cloud | current Cloud API (v3) |
| Confluence | Cloud | current Cloud API (v2, legacy v1 only where explicitly noted) |
| JFrog Artifactory | Self-Managed / On-Prem | runtime-discovered (never hardcoded); verified at generation time: 7.161.32 (2026-10-07) |
| GitHub | Enterprise Cloud **or** Server | resolved from `github.deployment` config - Cloud and Server are never assumed interchangeable |

## MCP architecture

Primary integration path for every system, discovered and routed per
`.mcp.json` (Copilot CLI) and `.vscode/mcp.json` (VS Code):

- **Bitbucket DC**: official "MCP for Bitbucket DC" plugin (bundled with
  Bitbucket 10.5+, Marketplace-installable on 9.x-10.x). Admins control
  the exposed tool whitelist via `BITBUCKET_HOME/shared/mcp-tools.json`.
- **Jira + Confluence**: official Atlassian **Rovo MCP Server**
  (`https://mcp.atlassian.com/v2/mcp`, OAuth 2.1).
- **JFrog**: official **JFrog MCP Server** for self-managed platforms
  (toolsets at generation time: Access, Artifactory, Security,
  Curation, Distribution, Evidence, AppTrust, Workers). The deprecated
  community project `jfrog/mcp-jfrog` is explicitly NOT used.
- **GitHub**: the officially documented GitHub MCP mechanism for
  Copilot CLI/VS Code.

Tool names are **never hardcoded** - every Skill instructs the agent to
discover the tools actually exposed by the connected MCP server at
runtime and select among them, falling back to the verified REST API
(then to a Skill-provided fallback script) only when no MCP tool covers
the operation.

## Skills architecture

Each Skill lives under `.github/skills/<name>/` with:

```
SKILL.md              - Purpose/Scope/MCP dependency/API fallback/
                         Authentication/Read+Write operations/Approval
                         rules/Security/Verification/Audit/Rollback
scripts/windows/*.ps1  - PowerShell 7+ implementations
scripts/unix/*.sh      - Bash implementations (equivalent semantics)
references/            - verified endpoint tables, supporting docs
tests/                 - Pester (*.Tests.ps1) and/or Bats (*.bats)
```

42 Skills are defined (see `.github/skills/`): `human-approval` plus 11
Bitbucket, 4 Jira, 3 Confluence, 10 JFrog, and 13 GitHub Skills, per
`requirement.md` Section 15.

## Approval architecture

Implemented by `.github/skills/human-approval/` and
`scripts/common/Common.psm1` / `scripts/common/common.sh`:

- Every operation is classified via
  `policies/operation-classification.yaml` (+ its machine-readable
  mirror `operation-classification.json`) into `READ_ONLY`, `WRITE`,
  `DESTRUCTIVE`, `ADMINISTRATIVE`, or `SECURITY_SENSITIVE`.
- Protected operations require one of the exact phrases in
  `policies/approval-policy.yaml#approval_types` (`APPROVE CREATE`,
  `APPROVE UPDATE`, `APPROVE DELETE`, `APPROVE MERGE`,
  `APPROVE PERMISSION CHANGE`, `APPROVE ADMIN CHANGE`,
  `APPROVE BRANCH PROTECTION`, `APPROVE WEBHOOK CHANGE`,
  `APPROVE SECURITY CHANGE`, `APPROVE SCRIPT CREATION`,
  `APPROVE EXECUTION`).
- An approval is an HMAC-SHA256-signed record bound to
  `operationId`+`user`+`system`+`target`+`operation`+`risk`+`approvalType`,
  single-use, stored under `logs/.approvals/`. An approval for
  `DELETE artifact A` cannot authorize `DELETE artifact B`.
- Multiple requested mutations are enumerated and independently
  approvable (`APPROVE 1`, `APPROVE 3`, ...).
- Creating a fallback script and executing it require **separate**
  approvals (`APPROVE SCRIPT CREATION` then `APPROVE EXECUTION`).

## Security

See `SECURITY.md` and `policies/security-policy.yaml` for the full
threat model: credential handling, MCP security, prompt-injection
defense (all retrieved content - Jira comments, Confluence pages,
commit messages, PR/issue text, Artifactory metadata - is treated as
untrusted data, never as instructions), command/shell/PowerShell
injection prevention, TLS enforcement, and audit-log handling.

## Authentication

Three independent, all-mandatory controls for every protected write
(`policies/approval-policy.yaml#controls`):

1. **Authentication** - who is the user (local POC token today; OAuth/
   OIDC/GitHub App/credential broker in production).
2. **Authorization** - does the user hold the platform-side permission.
3. **Human approval** - did the user explicitly approve *this specific*
   change.

### Local POC credentials

```
.github/local-secrets/
    bitbucket-token.txt.example   <- copy to bitbucket-token.txt, fill in
    jfrog-token.txt.example       <- copy to jfrog-token.txt, fill in
    github-token.txt.example      <- copy to github-token.txt, fill in
```

These real files are gitignored and must never be committed, printed,
or logged. Jira and Confluence have no local-secrets file by design -
their Skills accept an email + API token (or OAuth via Rovo MCP) as
explicit parameters instead, since the primary path is the Rovo MCP
OAuth flow.

### Production authentication

Replace local files with: OAuth, OIDC, a GitHub App, Atlassian OAuth,
JFrog access tokens issued via a credential broker, an enterprise
secret manager, or managed/workload identity. No Skill is tightly
coupled to a local token file - scripts accept credentials as
parameters, so swapping the issuance mechanism does not require
rewriting Skills. See "Production Hardening" below.

## Installation

1. Clone this repository.
2. Copy each `*.txt.example` file under `.github/local-secrets/` to its
   real filename and populate it with a POC credential (never commit
   the real file).
3. Open the repository in VS Code, or start Copilot CLI in it.

## Configuration

- `.mcp.json` - Copilot CLI MCP server configuration (`mcpServers` key).
  Placeholder header values must be replaced locally - see
  "Troubleshooting" for why this file intentionally ships without a
  working secret-reference mechanism.
- `.vscode/mcp.json` - VS Code MCP server configuration (`servers` +
  `inputs` keys - **not** the same schema as `.mcp.json`). Secrets are
  collected via VS Code's `inputs` prompt mechanism
  (`${input:<id>}`), never hardcoded.
- `policies/system-policy.yaml` - per-system deployment facts and
  mandatory runtime version/capability discovery configuration,
  including the `github.deployment: cloud | server` /
  `hostname` / `organization` / `enterprise` shape from
  `requirement.md` Section 5.

### VS Code

1. Open this repository in VS Code.
2. Ensure GitHub Copilot is installed/enabled.
3. Select the **Enterprise DevOps Agent**
   (`.github/agents/enterprise-devops.agent.md`) in the Copilot Chat
   agent picker.
4. Configure MCP via **Configure Custom Agents...** / the MCP server UI,
   pointing at the entries in `.vscode/mcp.json` (you'll be prompted for
   each `inputs` secret the first time a server connects).
5. Check MCP status in the Chat view's MCP indicator.
6. Ask a read-only question first (e.g. "list repositories in project
   ABC") to confirm connectivity before attempting a write.
7. Attempt an approval-protected write (e.g. "create repository X") and
   confirm the agent produces a `PROPOSED OPERATION` block rather than
   executing immediately.
8. View MCP logs via VS Code's MCP output channel; view audit logs at
   `logs/enterprise-devops-audit.jsonl`.

### Copilot CLI

1. Start Copilot CLI in this repository.
2. Select the custom agent: `/agent` -> Enterprise DevOps Agent, or
   `copilot --agent enterprise-devops --prompt "..."`.
3. Skills under `.github/skills/` are discovered automatically; invoke
   one explicitly with `/human-approval` etc. if needed.
4. Configure MCP via the entries in `.mcp.json` (project-level) -
   populate real header values only in your **user-level**
   `~/.copilot/mcp-config.json`, never in the committed project file
   (see "Troubleshooting").
5. Check MCP connectivity, then run a read-only test, then an
   approval-protected write test, exactly as in the VS Code flow above.
6. Troubleshoot by inspecting Copilot CLI's own MCP/tool-call logs and
   this repository's `logs/enterprise-devops-audit.jsonl`.

## Platform-specific notes

### Bitbucket

Target Bitbucket Data Center **9.4.5** exactly;
`/rest/api/1.0/` is the REST fallback base. See
`.github/skills/bitbucket-*/SKILL.md`.

### Jira

Jira Cloud via Rovo MCP, REST fallback `/rest/api/3/`. See
`.github/skills/jira-*/SKILL.md`.

### Confluence

Confluence Cloud via Rovo MCP, REST fallback `/wiki/api/v2/` (legacy
`/wiki/rest/api/` only where explicitly noted). See
`.github/skills/confluence-*/SKILL.md`.

### JFrog

Self-managed Artifactory; version discovered at runtime via
`GET /artifactory/api/system/version` - never assumed. See
`.github/skills/jfrog-*/SKILL.md`.

### GitHub Enterprise

Cloud (`api.github.com`) or Server (`https://<hostname>/api/v3`),
resolved from configuration - never assumed. See
`.github/skills/github-*/SKILL.md`.

## Testing

```
# PowerShell (Windows, or PowerShell 7+ on Linux/macOS)
Invoke-Pester -Path .

# Bash (Linux/macOS)
find .github/skills -name "*.bats" -exec bats {} \;
```

Unit tests use mocked HTTP responses / local fixtures - no live
credentials required (`requirement.md` Section 44). The single most
important test class, present for every write-capable Skill: calling
the write script **without** a valid approval record MUST exit non-zero
and MUST NOT mutate anything.

Structural/security/skill validation:

```
./scripts/validation/validate-repository.ps1   # or .sh
./scripts/validation/validate-skills.ps1        # or .sh
./scripts/validation/validate-security.ps1      # or .sh
```

CI (`.github/workflows/ci.yml`) runs all of the above on a
`windows-latest` + `ubuntu-latest` matrix and never touches production
systems.

## Dry-run

Most mutating scripts support `-WhatIf` (PowerShell) / `--dry-run`
(Bash), which prints Target, Operation, current vs. proposed state (where
applicable), Risk, and the expected MCP/API call - and makes **no**
mutation.

## Audit

Every operation (read or write) produces one JSON line in
`logs/enterprise-devops-audit.jsonl` (schema in
`policies/audit-policy.yaml`). Credentials are never included; known
sensitive field names are redacted defensively even though they should
never appear. Production deployments must forward this stream to
centralized logging / a SIEM - see "Production Hardening".

## Troubleshooting

- **MCP server won't connect**: check `.mcp.json` / `.vscode/mcp.json`
  host/URL placeholders have been replaced, and that your token is
  valid and not expired.
- **"Approval check failed" on a write you just approved**: approval
  records are bound to the exact `system`/`target`/`operation`/`risk`
  tuple and are single-use - re-approving the *same* proposal again
  works; approving a *different* target does not transfer.
- **Copilot CLI `.mcp.json` has no real secret in it**: this is
  intentional. As of this writing, GitHub's documented Copilot CLI MCP
  configuration schema has no variable-interpolation mechanism for
  secrets in HTTP headers (unlike VS Code's `${input:...}`) - populate
  real tokens only in your user-level `~/.copilot/mcp-config.json`
  (outside this repo, never committed), not in the project-level
  `.mcp.json` committed here. Re-check
  https://docs.github.com/en/copilot/how-tos/copilot-cli/customize-copilot/add-mcp-servers
  periodically in case this changes.
- **A Skill says `NOT IMPLEMENTED`**: that operation could not be
  verified against official documentation at generation time. Verify
  it yourself against the sources in `requirement.md` Section 1 and
  contribute the fix (see `CONTRIBUTING.md`) rather than working around
  the gate.

## Production hardening

- Replace local token files with OAuth/OIDC/GitHub Apps/Atlassian
  OAuth/JFrog broker-issued tokens/a secret manager/managed or workload
  identity (`policies/system-policy.yaml`, `SECURITY.md`).
- Centralize audit logs to your logging platform, then to a SIEM
  (`policies/audit-policy.yaml#production`) - vendor-neutral by design.
- Enforce MCP server/tool allowlisting at the platform level, not just
  by convention.
- Apply least privilege to every token/identity used by this framework.
- Separate admin identities from day-to-day developer identities.
- Maintain environment separation (dev/staging/prod configuration must
  not share credentials).
- Define break-glass procedures for when the approval flow itself is
  unavailable (e.g. human-approval skill outage) - these procedures
  must still produce an audit trail after the fact.
- Apply normal change-management and code review to Skill/script
  changes (see `CONTRIBUTING.md`).
- Sign and version operational scripts (every script already carries a
  `$ScriptVersion`/`SCRIPT_VERSION`; add code-signing in production per
  your platform's standards).

## Enterprise rollout

Officially-supported mechanisms to consider when distributing this
framework beyond a single repository: GitHub organization-level
configuration, enterprise-level configuration, a private configuration
repository (e.g. `.github-private`), repository-level Skills, VS Code
settings sync/profiles, Copilot CLI configuration, and MCP server
allowlisting at the org/enterprise level. This repository does not
claim centralized-distribution support beyond what current official
GitHub documentation confirms - verify against
https://docs.github.com/en/copilot/ before relying on any specific
distribution mechanism in production.

## Limitations

- Several niche operations across Bitbucket/Jira/Confluence/JFrog/
  GitHub are marked `NOT IMPLEMENTED — OFFICIAL DOCUMENTATION/API
  VERIFICATION REQUIRED` inside the relevant `SKILL.md` where official
  documentation could not be verified at generation time (e.g. certain
  Bitbucket branch-permissions plugin-API variants, certain GitHub
  Enterprise Cloud-vs-Server admin endpoints, certain JFrog
  users/groups/permissions paths mid-migration to the Access service).
  Verify and implement these yourself following `CONTRIBUTING.md`.
- Rollback is **not guaranteed** for destructive operations unless an
  official platform recovery mechanism is separately verified and
  documented in the relevant Skill - this framework does not invent
  undo capability a platform doesn't provide.
- The local POC audit log and approval-signing key have no built-in
  tamper-evidence (see `SECURITY.md` "Known limitations").
- GitHub Actions secret updates require client-side libsodium/NaCl
  sealed-box encryption of the secret value before `PUT`; verify your
  tooling's crypto library before relying on that specific Skill.

## Official documentation

Full, individually-labeled list (every URL cited anywhere in this
framework, organized by vendor): **[`policies/versions-and-sources.yaml`](policies/versions-and-sources.yaml)**.
Quick links:

- GitHub: https://docs.github.com/ , https://docs.github.com/en/copilot/ ,
  https://docs.github.com/en/enterprise-cloud/ ,
  https://docs.github.com/en/enterprise-server/
- Atlassian: https://developer.atlassian.com/ ,
  https://confluence.atlassian.com/ ,
  https://confluence.atlassian.com/bitbucketserver/
- JFrog: https://docs.jfrog.com/ , https://jfrog.com/
- VS Code: https://code.visualstudio.com/docs/

---

Built to the specification in `requirement.md`. Never guess; verify
official documentation; mark `NOT IMPLEMENTED` rather than fabricate.
