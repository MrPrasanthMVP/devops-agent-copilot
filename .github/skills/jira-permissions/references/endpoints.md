# Verified Jira Cloud REST API v3 endpoints (jira-permissions scope)

Source: https://developer.atlassian.com/cloud/jira/platform/rest/v3/api-group-permission-schemes/

| Operation | Method | Path | Status |
|---|---|---|---|
| Get all permission schemes | GET | `/rest/api/3/permissionscheme` | Verified, not wired to a script (list variant) |
| Get permission scheme | GET | `/rest/api/3/permissionscheme/{schemeId}` | Implemented |
| Update permission scheme | PUT | `/rest/api/3/permissionscheme/{schemeId}` | Verified, not implemented (full replace; this skill uses the additive grant endpoint instead) |
| Create permission grant | POST | `/rest/api/3/permissionscheme/{schemeId}/permission` | Implemented |
| Delete permission grant | DELETE | `/rest/api/3/permissionscheme/{schemeId}/permission/{permissionId}` | Verified, not implemented (same pattern as create; add if needed) |
