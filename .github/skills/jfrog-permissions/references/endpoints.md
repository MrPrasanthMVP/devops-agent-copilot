# Verified JFrog Artifactory REST endpoints (jfrog-permissions scope)

| Operation | Method | Path | Source |
|---|---|---|---|
| List permission targets | GET | `/artifactory/api/security/permissions` | https://docs.jfrog.com/administration/reference/getpermissiontargets |
| Get permission target (v2) | GET | `/artifactory/api/v2/security/permissions/{name}` | https://docs.jfrog.com/administration/reference/getpermissiontargetdetailsv2 |
| Create/replace permission target (v2) | POST | `/artifactory/api/v2/security/permissions/{name}` | https://docs.jfrog.com/administration/reference/createpermissiontargetv2 |

Legacy v1 `PUT /artifactory/api/security/permissions/{name}` is
deprecated - do not use. See
https://docs.jfrog.com/integrations/docs/deprecated-jfrog-apis for the
current migration status before modifying this skill.
