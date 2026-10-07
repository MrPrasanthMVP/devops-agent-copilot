# Contributing to enterprise-devops-copilot

This repository is a control framework that lets GitHub Copilot act on
production enterprise systems. Changes here are change-managed
accordingly - the bar is higher than a typical internal tool.

## Before you start

1. Read `requirement.md` (the master specification this framework was
   built against) and `README.md`.
2. To bump a pinned version number or change an official-documentation/
   MCP-endpoint URL, edit **only** `policies/versions-and-sources.yaml`
   — it is the single source of truth. Then run
   `scripts/validation/validate-versions.ps1` (or `.sh`) to find the
   small set of files that must carry a literal copy (`.mcp.json`,
   `.vscode/mcp.json`, `README.md`'s summary table) and update those to
   match. Do not hand-edit a version/URL anywhere else — scripts under
   `scripts/bitbucket/` and `scripts/jfrog/` already read the pinned/
   reference values from that file at runtime.
2. Read `.github/skills/human-approval/SKILL.md` and
   `policies/approval-policy.yaml` - every Skill you add or change must
   respect the approval boundary.
3. Read `SECURITY.md` and `policies/security-policy.yaml`.

## Non-negotiable rules (inherited from `requirement.md`)

- **Official documentation only.** Every MCP tool name, REST endpoint,
  request body, or Copilot/VS Code configuration syntax you add must be
  verifiable against the official sources listed in `requirement.md`
  Section 1 (docs.github.com, developer.atlassian.com,
  confluence.atlassian.com/bitbucketserver, docs.jfrog.com,
  code.visualstudio.com/docs). If you cannot verify something, write
  `NOT IMPLEMENTED — OFFICIAL DOCUMENTATION/API VERIFICATION REQUIRED`
  instead of guessing.
- **Never invent MCP tools or APIs.**
- **Human approval is mandatory** for every non-read-only operation. Do
  not add a write path that bypasses `.github/skills/human-approval/`.
- **Script/script-creation/execution approvals are separate.** Approving
  the creation of a new fallback script never implies approval to run
  it.
- **Verify every write.** Report `STATUS = UNKNOWN` rather than a false
  `SUCCESS` when verification is inconclusive.
- **PowerShell/Bash parity.** Every operational script needs both a
  `.ps1` and a `.sh` implementation with equivalent behavior
  (`scripts/validation/validate-skills.ps1`/`.sh` checks this in CI).
- **No secrets in source.** Never commit real credentials; never print
  or log them. See `.github/local-secrets/*.txt.example`.

## Adding or modifying a Skill

1. Create `.github/skills/<name>/SKILL.md` following the structure used
   by existing skills (Purpose, Scope, When to use, When not to use, MCP
   dependency, API fallback, Authentication, Read operations, Write
   operations, Approval rules, Security, Verification, Audit, Examples,
   Rollback).
2. Add scripts under `scripts/windows/*.ps1` and `scripts/unix/*.sh`,
   importing `scripts/common/Common.psm1` / sourcing
   `scripts/common/common.sh` - do not reimplement approval checking,
   audit logging, or secure HTTP calls locally.
3. If the operation isn't already classified, add it to **both**
   `policies/operation-classification.yaml` and
   `policies/operation-classification.json` identically, choosing the
   risk category that matches existing examples (reads = `READ_ONLY`;
   permission/ACL/secret changes = `SECURITY_SENSITIVE`; governance/
   config changes = `ADMINISTRATIVE`; deletes = `DESTRUCTIVE`; other
   mutations = `WRITE`).
4. Add at least one test (`tests/*.Tests.ps1` and/or `tests/*.bats`)
   that: (a) checks the operation classification lookup, and (b)
   asserts the write script refuses to execute without a valid approval
   record.
5. Run the validation scripts locally before opening a PR:
   ```
   ./scripts/validation/validate-repository.ps1
   ./scripts/validation/validate-skills.ps1
   ./scripts/validation/validate-security.ps1
   ```
   (or the `.sh` equivalents on Linux/macOS).

## Testing

- Unit tests must not require live credentials against production
  systems - use mocked HTTP responses (Pester) or recorded fixtures
  (Bats). See `requirement.md` Section 44.
- Integration tests against a real sandbox instance are configured
  separately and are out of scope for the default CI workflow
  (`.github/workflows/ci.yml`), which never talks to production.

## Pull requests

- Keep the "why" in the PR description, not in code comments.
- Call out explicitly: which Skill(s) changed, which approval type(s)
  they require, and what you verified (official doc links).
- Do not bundle an approval-boundary change with an unrelated feature.
- CI (`validate-repository`, `validate-skills`, `validate-security`,
  unit tests on Windows + Linux) must pass before merge.

## Code review expectations

Reviewers should specifically check:
- Does every write path go through approval verification before
  mutating?
- Does every write path verify its result afterward?
- Is TLS verification intact (no `-k`, `--insecure`,
  `-SkipCertificateCheck`)?
- Are operation-classification YAML/JSON still in sync?
- Are there any credentials, tokens, or real hostnames accidentally
  committed?
