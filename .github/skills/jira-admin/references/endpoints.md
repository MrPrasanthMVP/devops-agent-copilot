# jira-admin - Verified REST Endpoints

All endpoints below are verified against the official Jira Cloud
platform REST API v3 documentation at developer.atlassian.com. No
endpoint in this file was sourced from Stack Overflow, blog posts, or
unofficial documentation.

## Get project

- **Method/Path**: `GET /rest/api/3/project/{projectIdOrKey}`
- **Operation key**: `jira.admin.get` -> `READ_ONLY`
- **Source**: https://developer.atlassian.com/cloud/jira/platform/rest/v3/api-group-projects/
- **Notes**: `projectIdOrKey` accepts either the numeric project id or
  the project key.

## Create project

- **Method/Path**: `POST /rest/api/3/project`
- **Operation key**: `jira.project.create` -> `ADMINISTRATIVE`
- **Source**: https://developer.atlassian.com/cloud/jira/platform/rest/v3/api-group-projects/
  (endpoint `#api-rest-api-3-project-post`)
- **Required request body fields** (confirmed against the official
  endpoint reference): `key`, `name`, `projectTypeKey`, `leadAccountId`.
  Optional fields include `projectTemplateKey`, `description`,
  `assigneeType`, `avatarId`, `url`.
- **Required permission**: "Administer Jira" global permission.

## Update project

- **Method/Path**: `PUT /rest/api/3/project/{projectIdOrKey}`
- **Operation key**: `jira.admin.update` -> `ADMINISTRATIVE`
- **Source**: https://developer.atlassian.com/cloud/jira/platform/rest/v3/api-group-projects/
  (endpoint `#api-rest-api-3-project-projectidorkey-put`)
- **Notes**: All body fields are optional; fields omitted from the
  request body are left unchanged server-side. Changing schemes or the
  project key additionally requires the "Administer Jira" global
  permission; otherwise "Administer Projects" project permission
  suffices. Available fields include `assigneeType`, `avatarId`,
  `categoryId`, `description`, `issueSecurityScheme`, `key`, `lead`,
  `leadAccountId`, `name`, `notificationScheme`.
