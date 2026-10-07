---
name: human-approval
description: Mandatory human-approval engine for the Enterprise DevOps Copilot framework. Every WRITE, DESTRUCTIVE, ADMINISTRATIVE, or SECURITY_SENSITIVE operation against Bitbucket, Jira, Confluence, JFrog, or GitHub Enterprise must be proposed and approved through this Skill before any other Skill executes it. Use this whenever you are about to mutate state in any target system, create or run a fallback script, or need to classify operation risk.
license: Proprietary - internal enterprise use
---

## Purpose

This Skill is the single enforcement point for Section 7-10 and 32-34 of
the governing framework: it issues operation-bound approval proposals,
validates the human's response against the exact required approval
phrase, mints a signed approval token, and provides the binding-check
primitive every other Skill's execution script calls before performing a
mutation. No other Skill implements its own approval logic — they all
call into the shared engine this Skill wraps:
`scripts/common/Common.psm1` (PowerShell) and `scripts/common/common.sh`
(Bash).

## Scope

- Proposing an operation (showing current state, proposed state, risk,
  impact, and the required approval phrase) and staging it under
  `.proposals/<operationId>.json` (gitignored, NOT itself a usable
  approval).
- Turning a human's literal response into either a canonical,
  HMAC-signed, single-use approval token at `logs/.approvals/<operationId>.json`
  (on exact phrase match), or a recorded denial (otherwise).
- The binding-check primitive (`Test-ApprovalToken` /
  `test_approval_token`, wrapped by `verify-approval.ps1` /
  `verify-approval.sh`) that confirms a token is signature-valid,
  unexpired in effect (unconsumed), and bound to the exact
  system/target/operation/approval-type being executed.
- Enumerating and independently tracking multiple mutations from a single
  user request, including partial approval.
- Distinguishing `APPROVE SCRIPT CREATION` from `APPROVE EXECUTION` as two
  separate, independently tracked gates.

## When to use

- Immediately after READ + ANALYZE, for any operation classified as
  `WRITE`, `DESTRUCTIVE`, `ADMINISTRATIVE`, or `SECURITY_SENSITIVE` in
  `policies/operation-classification.yaml` /
  `policies/operation-classification.json`.
- Before writing a new fallback script that doesn't exist yet
  (`APPROVE SCRIPT CREATION`), and again before running it
  (`APPROVE EXECUTION`).
- Before any other Skill's execution script performs its mutating call —
  that script imports `Common.psm1` / sources `common.sh` and calls
  `Test-ApprovalToken` / `test_approval_token` directly (see any
  `delete-*`, `update-*`, `create-*`, `merge-*` script under
  `.github/skills/*/scripts/` for the established pattern).

## When not to use

- `READ_ONLY` operations never need this Skill — execute them directly.
- Do not use this Skill to "double check" something the user merely
  described hypothetically ("what would happen if I deleted X?") — that is
  a READ/ANALYZE conversation, not a proposal; only invoke this Skill when
  you are actually about to execute.

## MCP dependency

None. Approval enforcement is a framework-internal control, not a
target-system capability, so it is implemented entirely with local
scripts — never delegated to an MCP server or a target system API.

## API fallback

Not applicable (no external API).

## Authentication

Uses the identity already established for the session (the authenticated
Copilot/VS Code/CLI user). This Skill does not itself perform
authentication — see Section 10: Authentication, Authorization, and
Human Approval are three separate controls, and this Skill implements
only the third.

## Read operations

- `verify-approval.ps1` / `verify-approval.sh` — read-only validation of
  an existing signed approval token (thin CLI wrapper over
  `Test-ApprovalToken` / `test_approval_token`); does not mutate
  anything. Execution scripts more commonly call `Test-ApprovalToken` /
  `test_approval_token` directly (no subprocess) rather than shelling
  out to this wrapper, but the wrapper exists for manual/CLI checks.

## Write operations

- `request-approval.ps1` / `request-approval.sh` — stages a new PENDING
  proposal under `.proposals/` and prints the PROPOSED OPERATION block.
  This is a local bookkeeping write only; it never touches
  Bitbucket/Jira/Confluence/JFrog/GitHub, and the staged proposal is
  **not** a valid approval token on its own.
- `confirm-approval.ps1` / `confirm-approval.sh` — validates the human's
  literal response against the staged proposal's expected phrase. On an
  exact match, mints the canonical signed token via `New-ApprovalToken` /
  `new_approval_token` and deletes the staged proposal. On anything
  else, records a denial and leaves no usable token behind.

## Approval rules

- The approval phrase must exactly match the operation-specific phrase in
  `policies/approval-policy.yaml` (e.g. `APPROVE DELETE`, not `yes`/`ok`/
  `sure`/`do it`/`go ahead`/`proceed`).
- A signed token is valid only for the exact `operationId` it was issued
  for, and only when the caller's presented system/target/operation tuple
  matches the signed payload exactly — Section 32: an approval for
  `DELETE artifact A` fails validation if presented against `DELETE
  artifact B`.
- A proposal expires 900 seconds (15 minutes) after issuance by default
  (`expiresAfterSeconds`); `confirm-approval` refuses to mint a token
  from an expired proposal and the calling Skill must re-propose.
- A minted token is **single-use**: the first successful execution calls
  `Set-ApprovalConsumed` / `set_approval_consumed`, after which
  `Test-ApprovalToken` / `test_approval_token` rejects any further use of
  that `operationId`.
- `APPROVE SCRIPT CREATION` and `APPROVE EXECUTION` are always separate
  operationIds — never conflate them.
- Multiple mutations from one request get one `request-approval` call per
  mutation, enumerated and independently approvable.

## Security

- `logs/.approvals/` (signed tokens) and `.proposals/` (staged, unsigned
  proposals) are both gitignored and contain no credentials — only
  operation metadata (system, target, operation, risk, approval type,
  timestamps, approver identity, and an HMAC-SHA256 signature).
- The signature is computed over the record's own fields using a
  POC-local signing key (`.github/local-secrets/approval-signing-key.txt`,
  auto-provisioned on first use, gitignored); production deployments
  must replace this with a key issued by a secret manager/credential
  broker (Section 12).
- Scripts never accept a bare `--approved true`/`-Approved` boolean flag
  as sufficient authorization; they require a full, signature-valid,
  matching, unconsumed token.
- No `Invoke-Expression`/`iex`/dynamic evaluation of untrusted input is
  used anywhere in this Skill or in `scripts/common/`.
- No network calls are made by this Skill.

## Verification

`Test-ApprovalToken` / `test_approval_token` (and the `verify-approval`
CLI wrapper over it) is the verification primitive other Skills use.
Its result is a boolean `Valid` plus a `Reason` string; calling scripts
treat `Valid = $false` as "stop and do not execute" (see any execution
script's `ApprovalDenied` exit path).

## Audit

Every `request-approval` and `confirm-approval` call appends a record to
`logs/enterprise-devops-audit.jsonl` via `Write-AuditLog` /
`write_audit_log`, independent of the audit record the *calling* Skill
writes for the underlying business operation.

## Examples

### Destructive example

```
User: Delete repository TEST
Agent: (READ current state) -> (PROPOSE)

PROPOSED OPERATION
System: bitbucket
Target: PROJ/TEST
Operation: bitbucket.repository.delete
Risk: DESTRUCTIVE
Impact: Permanent repository deletion. Not reversible via API.
Explicit approval required. Type: APPROVE DELETE

User: APPROVE DELETE
Agent: (confirm-approval mints a signed token) -> EXECUTE (delete-repository.ps1/.sh,
       which calls Test-ApprovalToken/test_approval_token itself) -> VERIFY -> AUDIT -> REPORT
```

### Multiple mutations with partial approval

```
1. CREATE repository
2. MODIFY team
3. MODIFY permissions
4. MODIFY branch protection
5. CREATE webhook
6. MERGE pull request

User: APPROVE 1
      APPROVE 4
Agent: executes only operations 1 and 4; operations 2,3,5,6 remain PENDING.
```

### Script creation vs execution

```
Agent: NEW SCRIPT PROPOSAL (Name, Purpose, System, API, HTTP method,
       Parameters, Security risks, Expected impact, Rollback,
       Verification) -> requires APPROVE SCRIPT CREATION
User:  APPROVE SCRIPT CREATION
Agent: writes the script (unexecuted) -> requires a NEW, separate
       APPROVE EXECUTION before running it
```
