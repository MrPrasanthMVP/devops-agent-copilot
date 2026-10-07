# Verified JFrog Artifactory REST endpoints (jfrog-repositories scope)

| Operation | Method | Path | Source |
|---|---|---|---|
| List repositories | GET | `/artifactory/api/repositories` | https://docs.jfrog.com/artifactory/reference/getrepositoryconfiguration |
| Get repository | GET | `/artifactory/api/repositories/{repoKey}` | https://docs.jfrog.com/artifactory/reference/getrepositoryconfiguration |
| Create repository | PUT | `/artifactory/api/repositories/{repoKey}` | https://docs.jfrog.com/artifactory/reference/createrepository |
| Update repository | POST | `/artifactory/api/repositories/{repoKey}` | https://jfrog.com/help/r/jfrog-rest-apis/update-repository-configuration |
| Delete repository | DELETE | `/artifactory/api/repositories/{repoKey}` | https://docs.jfrog.com/artifactory/reference/deleterepository |

Delete removes BOTH the configuration AND all repository content - this
must always be stated explicitly in the proposal shown to the human.
