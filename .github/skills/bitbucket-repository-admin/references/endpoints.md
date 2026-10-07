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

Do not use any Bitbucket 10.x-only endpoint against this 9.4.5 target
without first confirming it is also documented for 9.x.
