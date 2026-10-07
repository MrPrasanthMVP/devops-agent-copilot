---
name: jira-workflows
description: View Jira Cloud workflow definitions (statuses, transitions, conditions) and change workflow configuration or scheme associations. Use for requests about workflow structure itself, not simply moving one issue through its existing workflow.
license: Proprietary - internal enterprise use
---

## Purpose

Inspect and change Jira Cloud workflow definitions and workflow-scheme
associations.

## Scope

Workflow structure (statuses, transitions, conditions/validators/post-
functions) and scheme-to-project associations. Moving a single issue
through an existing transition -> `jira-issues` (`TRANSITION issue`).

## When to use

"What statuses exist in workflow X?", "Add a transition from Review to
Done", "Associate workflow scheme X with project Y".

## When not to use

"Move issue ABC-123 to Done" -> `jira-issues`.

## MCP dependency

Official Atlassian Rovo MCP Server — workflow-management tools (if
exposed for your site's edition/tier) resolved via `discover` at call
time.

## API fallback

Jira Cloud REST API v3: `GET /rest/api/3/workflow/search`,
`GET /rest/api/3/workflowscheme`, `PUT /rest/api/3/workflowscheme/{id}`.
Workflow *editing* (statuses/transitions) in Jira Cloud is primarily a
UI-driven operation in current Jira Cloud editions; where no verified
REST write endpoint exists for a specific requested change, this Skill
reports:

```
NOT IMPLEMENTED — OFFICIAL DOCUMENTATION/API VERIFICATION REQUIRED
```

rather than guessing a payload shape.

## Authentication

Rovo MCP: OAuth 2.1. REST fallback: shared Atlassian site credential.

## Read operations

List workflows, get workflow scheme, get project's associated scheme:
`READ_ONLY`.

## Write operations

Changing a workflow scheme association, or any verified workflow
structural change: `ADMINISTRATIVE`.

## Approval rules

`APPROVE ADMIN CHANGE`. Workflow changes affect every issue in every
project using that workflow/scheme — the proposal must enumerate the
affected project(s).

## Security

No credential exposure; gated due to broad blast radius across projects.

## Verification

Update -> `GET` the scheme/workflow -> compare.

## Audit

Logged as `system: jira`, `resource: workflow`, `risk: ADMINISTRATIVE`.

## Rollback

Revert the scheme association to the prior workflow — reversible,
requires its own approval. Structural workflow edits (statuses/
transitions) may not be cleanly reversible depending on in-flight issues
already on removed statuses — flag this explicitly in the proposal.

## Examples

```
User: What statuses exist in the "Software Development" workflow?
Agent: READ_ONLY -> GET workflow -> lists statuses directly, no approval needed.
```
