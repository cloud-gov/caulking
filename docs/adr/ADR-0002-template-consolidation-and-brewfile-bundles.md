# ADR-0002: Consolidation of Pre-Commit Templates and Selective Brewfile Bundles

**Status:** Accepted
**Date:** 2026-11-09
**Deciders:** William Zujkowski / Cloud.gov Platform Team

## Context

Previously, workstation pre-commit management was split across two repositories:

1. `cloud-gov/caulking` owned the global Git hooks (`core.hooksPath`), mandatory
   `gitleaks` execution, `prek`/`pre-commit` runner orchestration, and selective
   workstation toolchain bootstrap (`caulking.sh bootstrap`, `caulking.sh doctor`,
   `caulking.sh run`).
2. `cloud-gov/pre-commit-templates` owned the reusable hook catalog
   (`.pre-commit-hooks.yaml`), language `starter-configs/`, self-contained
   Python/Go hook implementations (`pyproject.toml`, `cloud_gov_pre_commit_checks/`,
   `go.mod`), hook scripts, validators, and a monolithic 16-package `Brewfile`.

Maintaining two repositories created version drift between hook definitions and
workstation bootstrap profiles, forced consumers to reference two separate repos
for onboarding, and left a monolithic `pre-commit-templates/Brewfile` that
installed conflicting runtimes (both `hashicorp/tap/terraform` and `opentofu`)
and unrelated tools while omitting caulking's own baseline (`gitleaks`, `prek`,
`bash`). At the same time, existing consuming repositories pin
`https://github.com/cloud-gov/pre-commit-templates` at tags such as `v0.5.3` and
`v0.6.0` and must not break when `pre-commit` fetches those historical revisions.

## Decision

### 1. Consolidate Hook Definitions and Starter Configs into `cloud-gov/caulking`

Move all reusable hook assets from `cloud-gov/pre-commit-templates` into
`cloud-gov/caulking` under a single Release Please SemVer version (`VERSION`,
`.release-please-manifest.json`, `release-please-config.json` per
[ADR-0001](ADR-0001-release-management.md)):

- `.pre-commit-hooks.yaml` (all 49 standard and opt-in `-selfcontained` Go and
  Python hooks at the repository root)
- `starter-configs/*.pre-commit-config.yaml` (pointing `repo:` at
  `https://github.com/cloud-gov/caulking`, with a note referencing the frozen
  `cloud-gov/pre-commit-templates` `v0.6.0` compatibility endpoint until the
  first consolidated caulking release `v3.4.0` is published by Release Please)
- Self-contained hook packages (`pyproject.toml`,
  `cloud_gov_pre_commit_checks/`, `go.mod`) at the repository root
- Hook scripts (`scripts/check-*.sh`, `scripts/end-of-file-fixer.sh`,
  `scripts/trailing-whitespace.sh`) and hook/config validators
  (`scripts/validate-hooks.py`, `scripts/test-validate-hooks.sh`)
- Architectural Decision Records (`docs/adr/ADR-0003` through `ADR-0010`),
  supply-chain monitoring (`docs/MONITORING.md`), and `TROUBLESHOOTING.md`

### 2. Replace Monolithic `Brewfile` with Composable `brewfiles/<profile>.Brewfile` Bundles

Replace the single all-languages `Brewfile` with 9 selective, composable
Homebrew Bundle files under `brewfiles/<profile>.Brewfile`:

- `brewfiles/baseline.Brewfile` (`bash`, `gitleaks`, `prek`)
- `brewfiles/shell.Brewfile` (`shellcheck`, `shfmt`)
- `brewfiles/container.Brewfile` (`hadolint`)
- `brewfiles/python.Brewfile` (`ruff`, `mypy`, `bandit`, `pip-audit`)
- `brewfiles/go.Brewfile` (`go`, `golangci-lint`)
- `brewfiles/javascript.Brewfile` (`node`)
- `brewfiles/opentofu.Brewfile` (`terraform-linters/tap`, `opentofu`, `terraform-linters/tap/tflint` cask)
- `brewfiles/terraform.Brewfile` (`hashicorp/tap`, `terraform-linters/tap`, `hashicorp/tap/terraform`, `terraform-linters/tap/tflint` cask)
- `brewfiles/security.Brewfile` (`semgrep`, `osv-scanner`, `syft`, `grype`)

Repositories declare their required profiles explicitly in `.caulking-profiles`
(no profiles are implicitly assumed; `run` and `hook-run` require `baseline` to
be selected). `caulking.sh bootstrap` verifies the presence of each selected
`brewfiles/<profile>.Brewfile` and installs missing Homebrew formulae/casks with
`HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_INSTALL_UPGRADE=1 HOMEBREW_NO_INSTALL_CLEANUP=1`
(never implicitly upgrading, downgrading, unlinking, or removing existing tools).
Teams can also invoke `brew bundle install --file=brewfiles/<profile>.Brewfile --no-upgrade`
directly.

### 3. Enforce Minimum SemVer Floors in `caulking doctor` While Allowing `brew upgrade`

Homebrew `Brewfile` syntax selects package names rather than enforcing `>=`
SemVer constraints. To balance supply-chain safety with developer ergonomics:

- `scripts/toolchain.sh` defines justified minimum supported SemVer floors for
  all 20 profile tools (`gitleaks >=8.21.0`, `prek >=0.4.0`, `bash >=4.0.0`,
  `shellcheck >=0.9.0`, `shfmt >=3.6.0`, `hadolint >=2.12.0`, `ruff >=0.4.0`,
  `mypy >=1.8.0`, `bandit >=1.7.5`, `pip-audit >=2.7.0`, `go >=1.22.0`,
  `golangci-lint >=1.59.0`, `node >=20.0.0`, `opentofu >=1.6.0`,
  `terraform >=1.5.0`, `tflint >=0.50.0`, `semgrep >=1.50.0`,
  `osv-scanner >=1.7.0`, `syft >=1.0.0`, `grype >=0.74.0`) and verifies installed
  versions in `caulking.sh doctor` (and before `run`/`hook-run`) with 5-second
  telemetry-disabled version probes.
- Developers may run `brew upgrade` freely to pick up upstream security fixes
  and improvements without waiting for a new `caulking` release for every tool
  patch.

### 4. Freeze `cloud-gov/pre-commit-templates` as a Compatibility Endpoint

Keep `cloud-gov/pre-commit-templates` online and frozen as a read-only
compatibility endpoint:

- Existing tags (`v0.5.3`, `v0.6.0`, etc.) and `.pre-commit-hooks.yaml` remain
  intact so repositories already pinned to `cloud-gov/pre-commit-templates`
  continue to resolve and run without disruption.
- Mark `pre-commit-templates/README.md`, `pre-commit-templates/Brewfile`, and
  bootstrap planning docs as consolidated into `cloud-gov/caulking`, directing all
  new adoption and updates to `https://github.com/cloud-gov/caulking`.

## Consequences

### Positive

- Single repository (`cloud-gov/caulking`) and single SemVer release stream for
  global workstation hooks, selective Brewfile bundles, `caulking.sh` CLI,
  reusable `.pre-commit-hooks.yaml`, and `starter-configs/`.
- Developers install only the language/scanner bundles their repositories need,
  and `opentofu` vs `terraform` remain separate bundles.
- `caulking.sh doctor` enforces minimum supported tool versions while allowing
  normal `brew upgrade` workflows.
- Zero breaking impact on existing repositories pinned to historical
  `cloud-gov/pre-commit-templates` tags.

### Negative

- Consumers migrating from `cloud-gov/pre-commit-templates` to
  `cloud-gov/caulking` must update the `repo:` URL and `rev:` in their
  `.pre-commit-config.yaml` after the first consolidated release is published.
- Historical ADRs migrated from `pre-commit-templates` are renumbered (`ADR-0003`
  through `ADR-0010`) with provenance notes to avoid colliding with `ADR-0001`
  and `ADR-0002`.

### Neutral

- Self-contained hooks (`-selfcontained`) continue to pin their own isolated tool
  dependencies (`PyYAML==6.0.3`, `gosec`, `govulncheck`) for Linux/CI environments
  where Homebrew is not used.

## References

- [ADR-0001: GitHub Actions Release Please and Stable SemVer Tags](ADR-0001-release-management.md)
- [ADR-0003: Hook Selection and Implementation Decisions](ADR-0003-hook-selection.md)
- [ADR-0004: Supply Chain Security Tool Selection](ADR-0004-supply-chain-security.md)
- [Toolchain Bootstrap Plan](../toolchain-bootstrap-plan.md)
- [Toolchain Bootstrap Guide](../toolchain-bootstrap.md)
