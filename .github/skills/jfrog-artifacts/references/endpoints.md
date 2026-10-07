# Verified JFrog Artifactory REST endpoints (jfrog-artifacts scope)

| Operation | Method | Path | Source |
|---|---|---|---|
| Get artifact storage info | GET | `/artifactory/api/storage/{repoKey}/{itemPath}` | https://docs.jfrog.com/ (Artifactory REST API - Storage) |
| Deploy (upload) artifact | PUT | `/artifactory/{repoKey}/{itemPath}` | Standard Artifactory deploy endpoint |

Deletion is intentionally NOT implemented in this skill - use
`jfrog-cleanup` for both single-item and bulk artifact deletion so that
exactly one skill owns the destructive, candidate-digest-bound approval
path for artifacts.
