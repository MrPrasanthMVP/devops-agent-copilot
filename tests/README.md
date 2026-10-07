# Tests directory layout

This top-level `tests/` tree holds **cross-skill / cross-system**
integration-style tests (requirement.md Section 42/43), organized by
system: `approval/`, `bitbucket/`, `jira/`, `confluence/`, `jfrog/`,
`github/`.

This is distinct from **per-skill unit tests**, which live next to each
Skill at `.github/skills/<skill-name>/tests/` and are the primary,
exhaustive test coverage for that Skill's scripts (mocked API/MCP
responses, no live credentials - Section 44).

Use this top-level `tests/` tree for:
- The single most important invariant from Section 43 - **"No approval
  -> MUST NOT EXECUTE"** - verified once per system against a
  representative sample of that system's destructive/administrative
  scripts, as a cross-cutting regression guard independent of any one
  Skill.
- Future true integration tests against a real sandbox instance
  (separately configured, never run automatically in default CI -
  see CONTRIBUTING.md "Testing").

Run everything with Pester:
```powershell
Invoke-Pester tests/
```
or Bats for the shell-side tests:
```bash
find tests -name "*.bats" -print0 | xargs -0 -n1 bats
```

Unit tests must use mocked API/MCP responses - never live production
credentials. Integration tests against a real sandbox instance are
configured separately from default CI (see CONTRIBUTING.md).
