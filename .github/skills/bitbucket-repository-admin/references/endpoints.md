# Verified Bitbucket Server/DC REST endpoints (repository-admin scope)

Source: https://developer.atlassian.com/server/bitbucket/rest/ (API base
`/rest/api/1.0/`, stable across Bitbucket Server/DC 9.x).

| Operation | Method | Path | Body |
|---|---|---|---|
| List repositories | GET | `/rest/api/1.0/projects/{projectKey}/repos` | - |
| Get repository | GET | `/rest/api/1.0/projects/{projectKey}/repos/{repositorySlug}` | - |
| Create repository | POST | `/rest/api/1.0/projects/{projectKey}/repos` | `{"name": "<slug>", "scmId": "git"}` |
| Delete repository | DELETE | `/rest/api/1.0/projects/{projectKey}/repos/{repositorySlug}` | - |
| Get default branch | GET | `/rest/api/1.0/projects/{projectKey}/repos/{repositorySlug}/branches/default` | - |
| Set default branch | PUT | `/rest/api/1.0/projects/{projectKey}/repos/{repositorySlug}/branches/default` | `{"id": "refs/heads/<branch>"}` |

All Bitbucket Data Center versions are supported. Do not use any
version-specific endpoint (9.x-only or 10.x-only) without first
confirming it against the detected version's own documentation
(`GET /rest/api/1.0/application-properties`).
