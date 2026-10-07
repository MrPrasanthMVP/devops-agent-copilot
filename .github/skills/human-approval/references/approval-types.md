# Approval type reference

Mirrors `policies/approval-policy.yaml#approval_types`. Each row is the
exact, case-sensitive phrase a human must type - nothing else satisfies it.

| Phrase | Applies to category | Explicit confirmation | Notes |
|---|---|---|---|
| `APPROVE CREATE` | WRITE, ADMINISTRATIVE | No | New resource creation |
| `APPROVE UPDATE` | WRITE | No | In-place mutation |
| `APPROVE DELETE` | DESTRUCTIVE | Yes | Irreversible/hard-to-reverse removal |
| `APPROVE MERGE` | WRITE | No | Pull/merge request merge |
| `APPROVE PERMISSION CHANGE` | SECURITY_SENSITIVE | No | ACL/permission grant or revoke |
| `APPROVE ADMIN CHANGE` | ADMINISTRATIVE | No | Platform-level config change |
| `APPROVE BRANCH PROTECTION` | ADMINISTRATIVE | No | Branch protection / ruleset change |
| `APPROVE WEBHOOK CHANGE` | ADMINISTRATIVE, DESTRUCTIVE | No (Yes if delete) | Webhook create/update/delete |
| `APPROVE SECURITY CHANGE` | SECURITY_SENSITIVE | No | Security settings/scanning config |
| `APPROVE SCRIPT CREATION` | ADMINISTRATIVE | No | Authorizes writing a new fallback script only |
| `APPROVE EXECUTION` | WRITE, DESTRUCTIVE, ADMINISTRATIVE, SECURITY_SENSITIVE | Depends on underlying op | Authorizes running an already-created script |

Partial-approval syntax for enumerated multi-operation requests:
`APPROVE <item-number>`, one per line or comma-separated, e.g.
`APPROVE 1, APPROVE 3`.
