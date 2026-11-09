# ADR-0003: Hook Selection and Implementation Decisions

**Status:** Accepted  
**Date:** 2026-05-18  
**Deciders:** Cloud.gov Platform Team  
**Context:** Implementation of cloud-gov pre-commit hooks per ADR-0028  
**Provenance:** Originally recorded as ADR-0001 in cloud-gov/pre-commit-templates prior to repository consolidation into cloud-gov/caulking ([ADR-0002](ADR-0002-template-consolidation-and-brewfile-bundles.md)).

## Context

Cloud.gov repositories need standardized pre-commit hooks to enforce code quality and security practices. Currently, teams implement hooks ad-hoc, leading to inconsistency and duplicated effort.

ADR-0028 established the need for centralized pre-commit templates. This ADR documents the specific decisions made during implementation.

## Decision

### 1. Hook Categories

We organize hooks into these categories:

| Category | Purpose | Target Users |
|----------|---------|--------------|
| Hygiene | Basic file quality | All repos |
| Shell | Shell script quality | Repos with scripts |
| Python | Python code quality | Python projects |
| Go | Go code quality | Go projects |
| Terraform | IaC quality | Terraform projects |
| Container | Dockerfile quality | Containerized apps |

**Rationale:** These categories cover cloud.gov's primary tech stack. Each category is opt-in, so teams only enable what they need.

### 2. Tool Selection

#### Python: Ruff over Black + isort + Flake8

- **Decision:** Use `ruff` for both linting and formatting
- **Rationale:**
  - 10-100x faster than alternatives
  - Single tool replaces three (black, isort, flake8)
  - Active maintenance, broad rule coverage
  - Configured via pyproject.toml (single config file)

#### Go: golangci-lint over individual linters

- **Decision:** Use `golangci-lint` as the primary Go linter
- **Rationale:**
  - Aggregates 100+ linters into one tool
  - Faster than running linters individually (caches results)
  - Industry standard for Go projects
  - Configurable via .golangci.yml

### 3. Language Value: `unsupported` over `system`

- **Decision:** Use `language: unsupported` in hook definitions
- **Rationale:**
  - `language: system` is deprecated in pre-commit 4.4.0+
  - `unsupported` clearly signals hooks require external tools
  - Aligns with pre-commit's direction for future compatibility

### 4. Secrets Detection: Handled by Caulking Global Hooks

- **Decision:** Do not include secrets detection (gitleaks) in `.pre-commit-hooks.yaml`
- **Rationale:**
  - [Caulking](https://github.com/cloud-gov/caulking) enforces gitleaks globally on all developer workstations
  - Caulking sets `core.hooksPath` to intercept all commits before any repo-specific hooks run
  - Caulking also installs `prek` which triggers `.pre-commit-config.yaml` hooks after gitleaks passes
  - Including gitleaks in `.pre-commit-hooks.yaml` would cause duplicate scans and potential conflicts
  - For CI environments (where caulking's global hook wrapper is not active), teams add gitleaks directly to their CI pipeline or use the upstream gitleaks hook (see [ADR-0009](ADR-0009-gitleaks-via-upstream-hook.md))

### 5. SAST Tools: Examples Only

- **Decision:** Bandit, Semgrep, tfsec are documented as optional examples, not mandatory core hooks
- **Rationale:**
  - SAST tools require significant configuration per-project
  - False positive rates vary by codebase
  - Better to run in CI with tuned configs than as mandatory pre-commit hooks
  - Teams can add them if their workflow benefits

### 6. macOS/Linux Compatibility

- **Decision:** All shell scripts must work on both macOS and Linux without GNU coreutils
- **Rationale:**
  - Most developers use macOS locally
  - CI runs on Linux
  - Cannot assume coreutils is installed on macOS

## Consequences

### Positive

- Teams get standardized hooks with one line in their config
- New repos can adopt best practices immediately
- Central updates propagate to all consuming repos
- Reduced maintenance burden for individual teams

### Negative

- Requires tools installed locally (via selective `brewfiles/<profile>.Brewfile` bundles or `caulking bootstrap`)
- Hook versions tied to this repo's releases
- May not cover every edge case (teams can add custom hooks)

### Neutral

- Integrates with existing caulking workflow
- Does not replace CI security scanning

## References

- ADR-0028: Pre-commit Standardization (internal cloud.gov ADR)
- [ADR-0002: Consolidation of Pre-Commit Templates and Selective Brewfile Bundles](ADR-0002-template-consolidation-and-brewfile-bundles.md)
- [Pre-commit documentation](https://pre-commit.com/)
- [Ruff documentation](https://docs.astral.sh/ruff/)
- [golangci-lint documentation](https://golangci-lint.run/)
- [Caulking repository](https://github.com/cloud-gov/caulking)
