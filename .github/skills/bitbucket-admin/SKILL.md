---
name: bitbucket-admin
description: Bitbucket Data Center instance-level administration -- global settings, license/application properties inspection, system-wide configuration discovery. Use for instance-wide (not project- or repo-scoped) Bitbucket administration questions.
license: Proprietary - internal enterprise use
---

## Purpose

Instance-level Bitbucket Data Center administration: version/capability
discovery, global/system settings inspection, and (where officially
supported) system configuration changes.

## Scope

Instance-wide settings only. Project-scoped admin -> `bitbucket-project-admin`.
Repository-scoped admin -> `bitbucket-repository-admin`.

## When to use

"What Bitbucket version is this?", "Show global Bitbucket settings",
"Is mesh/smart mirroring enabled?", instance-level configuration review.

## When not to use

Any project- or repository-scoped request -- route to the more specific
Skill.

## MCP dependency

Official "MCP for Bitbucket DC" (see `policies/system-policy.yaml`).
Discover tools at connect time; this Skill does not assume a tool exists
for instance administration beyond what the server actually exposes
(administration endpoints are typically more restricted than
project/repo endpoints in Bitbucket's REST whitelisting model).

## API fallback

`GET /rest/api/1.0/application-properties` (version/build info, used for
Section 38 version discovery) is verified and safe to call read-only.
Instance-level *write* administration (e.g. global permission scheme
changes, mail server config) is highly product-specific and is marked:

```
NOT IMPLEMENTED — OFFICIAL DOCUMENTATION/API VERIFICATION REQUIRED
```

until a specific verified endpoint is identified for the exact requested
change, per Section 1/57.

## Authentication

Bitbucket HTTP access token with instance-admin scope for any write path
(none implemented yet -- see above); read-only version discovery works
with any authenticated token.

## Read operations

Version/application-properties discovery: `READ_ONLY`, no approval
needed.

## Write operations

None implemented in this POC (see API fallback). Any future addition
must cite a verified endpoint and is classified `ADMINISTRATIVE` or
`SECURITY_SENSITIVE` depending on the setting.

## Approval rules

Any future write path must go through `.github/skills/human-approval/`
exactly like every other Skill — no exceptions for "instance-level."

## Security

Read-only in this POC; no destructive instance-level capability is
implemented, minimizing blast radius by design.

## Verification

Version discovery is self-verifying (the response IS the fact being
reported).

## Audit

Every version-discovery call is still logged (`operation: GET`,
`risk: READ_ONLY`) for traceability of what the agent believed the
instance capabilities were at a point in time.

## Examples

```
User: What Bitbucket version is running?
Agent: GET /rest/api/1.0/application-properties -> reports the detected
       version (all Bitbucket Data Center versions are supported), compares
       against the documented reference baseline purely for informational
       drift-tracking, and warns if different.
```
