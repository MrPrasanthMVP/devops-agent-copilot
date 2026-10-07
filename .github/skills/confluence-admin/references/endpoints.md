# Verified Confluence Cloud REST API v2 endpoints (confluence-admin scope)

Source: https://developer.atlassian.com/cloud/confluence/rest/v2/api-group-space/

| Operation | Method | Path | Status |
|---|---|---|---|
| List spaces | GET | `/wiki/api/v2/spaces` | Implemented |
| Get space | GET | `/wiki/api/v2/spaces/{id}` | Verified, script not added (trivial extension of list-spaces.ps1/.sh) |
| Create space | POST | `/wiki/api/v2/spaces` | NOT IMPLEMENTED — gated to RBAC Early Access Program per official docs at generation time; GA alternative is legacy v1 `/wiki/rest/api/space`, not implemented here pending confirmation of which surface applies to your tenant |
