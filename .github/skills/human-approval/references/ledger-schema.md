# Approval engine storage schema

Two separate, gitignored locations, implemented by
`scripts/common/Common.psm1` and `scripts/common/common.sh`:

## 1. Staged proposals — `.proposals/<operationId>.json`

Written by `request-approval.*`, read and deleted by `confirm-approval.*`.
**Not** a usable approval — `Test-ApprovalToken` / `test_approval_token`
never looks here.

| Field | Notes |
|---|---|
| `operationId` | `op-<12-hex>` |
| `user` | requester identity |
| `system` | `bitbucket \| jira \| confluence \| jfrog \| github` |
| `target` | exact target identifier |
| `operationKey` | dotted key, e.g. `bitbucket.repository.delete` (matches `policies/operation-classification.json`) |
| `risk` | classification category |
| `approvalType` | exact phrase required, e.g. `APPROVE DELETE` |
| `currentState` / `proposedState` / `impact` | shown in the PROPOSED OPERATION block |
| `requestedAt` | ISO-8601 UTC |
| `expiresAfterSeconds` | default 900 |

## 2. Signed approval tokens — `logs/.approvals/<operationId>.json`

Written by `New-ApprovalToken` / `new_approval_token` (called from
`confirm-approval.*` once the phrase matches), read by
`Test-ApprovalToken` / `test_approval_token` (called directly by every
execution script, or via the `verify-approval.*` CLI wrapper).

| Field | Notes |
|---|---|
| `operationId`, `user`, `system`, `target`, `operation`, `risk`, `approvalType`, `issuedAt` | signed payload fields |
| `signature` | HMAC-SHA256 over the above fields, base64, keyed by `.github/local-secrets/approval-signing-key.txt` (POC-only; replace with a broker-issued key in production) |

A sibling marker file `logs/.approvals/<operationId>.consumed` is written
by `Set-ApprovalConsumed` / `set_approval_consumed` on first successful
execution; its presence makes the token single-use.

`Test-ApprovalToken` / `test_approval_token` rejects a presented token
when: the file is missing, the signature doesn't match (tamper
detection), the system/target/operation doesn't match exactly (Section
32 binding), the `approvalType` doesn't satisfy the caller's required
phrase, or the `.consumed` marker already exists.
