# Homebrew toolchain bootstrap and selective Brewfile bundles

Status: local consolidated implementation, macOS-first. Includes
`.pre-commit-config.yaml`-driven toolchain resolution, selective
`brewfiles/<profile>.Brewfile` bundles, minimum SemVer floor verification in
`caulking doctor`, toolchain-aware global hook integration, reusable
`.pre-commit-hooks.yaml` definitions, `starter-configs/`, and a formula template.

`cloud-gov/caulking` is the single consolidated home for global secret-scanning
hooks, selective workstation toolchain profiles, reusable pre-commit hook
definitions (`.pre-commit-hooks.yaml`), and `starter-configs/`. The former
`cloud-gov/pre-commit-templates` repository is frozen as a compatibility
endpoint so existing pinned tags (`v0.5.3`, `v0.6.0`, etc.) continue resolving.
The full [research and rollout plan](toolchain-bootstrap-plan.md) and
[ADR-0002](adr/ADR-0002-template-consolidation-and-brewfile-bundles.md) record
the consolidation decision.

## Try from a checkout

Caulking includes repository stack detection, gap auditing, and multi-stack
`.pre-commit-config.yaml` generation so any new or existing repository can be
onboarded in four commands:

```bash
./caulking.sh detect --repo /path/to/repo
./caulking.sh init --repo /path/to/repo --write
./caulking.sh bootstrap --repo /path/to/repo
./caulking.sh doctor --repo /path/to/repo
```

- **`./caulking.sh detect --repo /path/to/repo`:**
  - Scans tracked files in the repository (ignoring `node_modules/`, `.venv/`,
    `venv/`, `vendor/`, `fixtures/`, `testdata/`, and `examples/`) to detect all
    active stacks (`shell`, `container`, `python`, `go`, `javascript`, `ruby`,
    `opentofu` / `terraform`, `docs`).
  - Recommends the exact 5-pillar hooks (`FMT`, `LINT`, `CHECK`, `SAST`, `SCA`)
    and Homebrew profiles for the repository.
  - If `.pre-commit-config.yaml` already exists, audits it for legacy
    `cloud-gov/pre-commit-templates` URLs, legacy ambient `check-yaml`/`check-json`
    hooks, and missing hooks for detected file types.
- **`./caulking.sh init --repo /path/to/repo [--interactive|-i] [--stack NAME]... [--no-stack NAME]... [--write] [--force]`:**
  - Generates a tailored, multi-stack `.pre-commit-config.yaml` combining all
    detected languages in the repository.
  - **`--interactive` (`-i`):** Launches an interactive 9-row checkbox TUI on
    stderr pre-checked (`[x]`) with the auto-detected stacks (`shell`,
    `container`, `python`, `go`, `javascript`, `ruby`, `opentofu`, `terraform`,
    `docs`). Developers can use `↑`/`↓` (or `j`/`k`) + `Space`, number keys
    `1`–`9`, `a` (all), or `n` (none) to toggle stacks before pressing `Enter`
    to confirm (or `q` to cancel).
  - **`--stack NAME` / `--no-stack NAME`:** Explicitly add or remove a stack
    non-interactively.
  - Prints to stdout by default (dry-run preview); `--write` writes
    `<repo>/.pre-commit-config.yaml` atomically (refusing to overwrite an
    existing config unless `--force` is passed, and always refusing symlinks).

`.pre-commit-config.yaml` is the single repository configuration file—no
separate `.caulking-profiles` file is needed. When invoked with `--repo PATH`
(or defaulting to `.`), `caulking.sh bootstrap`, `caulking.sh doctor`,
`caulking.sh run`, and global hooks (`hook-run`) read hook IDs directly from
`REPO/.pre-commit-config.yaml` and map each enabled hook to the required
Homebrew formulae alongside the `baseline` tools (`gitleaks`, `prek`, `bash`).

The config parser is bounded (`<=64 KiB`, `<=1024 lines`), rejects NUL bytes,
never uses `eval` or executes repository code, and resolves hook IDs against a
static allowlist in `scripts/toolchain.sh`. Unknown or self-contained hook IDs
(which provision their own isolated environments via `prek`/`pre-commit`) do not
trigger arbitrary Homebrew installs, while malformed hook IDs fail closed (`exit 2`).

Optional `--profile <name>` flags and `brewfiles/<profile>.Brewfile` remain
available as convenience bundles for installing or checking a language stack
outside a repository:

| Profile | Brewfile bundle | Homebrew packages & minimum versions enforced by `caulking doctor` |
| --- | --- | --- |
| `baseline` | `brewfiles/baseline.Brewfile` | `gitleaks >=8.21.0`, `prek >=0.4.0`, `bash >=4.0.0` |
| `shell` | `brewfiles/shell.Brewfile` | `shellcheck >=0.9.0`, `shfmt >=3.6.0` |
| `container` | `brewfiles/container.Brewfile` | `hadolint >=2.12.0` |
| `python` | `brewfiles/python.Brewfile` | `ruff >=0.4.0`, `mypy >=1.8.0`, `pyright >=1.1.350`, `bandit >=1.7.5`, `pip-audit >=2.7.0` |
| `go` | `brewfiles/go.Brewfile` | `go >=1.22.0`, `golangci-lint >=1.59.0`, `gosec >=2.18.0`, `govulncheck >=1.0.0` |
| `javascript` | `brewfiles/javascript.Brewfile` | `node >=20.0.0` |
| `ruby` | `brewfiles/ruby.Brewfile` | `ruby >=3.2.0`, `rubocop >=1.60.0` |
| `opentofu` | `brewfiles/opentofu.Brewfile` | `opentofu` (`tofu >=1.6.0`), `terraform-linters/tap/tflint >=0.50.0` |
| `terraform` | `brewfiles/terraform.Brewfile` | `hashicorp/tap/terraform >=1.5.0`, `terraform-linters/tap/tflint >=0.50.0` |
| `docs` | `brewfiles/docs.Brewfile` | `yamllint >=1.35.0`, `yamlfmt >=0.13.0`, `actionlint >=1.7.0`, `zizmor >=1.0.0`, `markdownlint-cli` (`markdownlint >=0.39.0`) |
| `security` | `brewfiles/security.Brewfile` | `semgrep >=1.50.0`, `osv-scanner >=1.7.0`, `syft >=1.0.0`, `grype >=0.74.0`, `checkov >=3.2.0` |

Repeated `--profile` flags can be combined with or used independently of
`--repo`, and shared tools (such as `tflint` across `opentofu` and `terraform`)
are automatically deduplicated.

From the caulking checkout (reading `REPO/.pre-commit-config.yaml` directly):

```bash
./caulking.sh bootstrap --repo /path/to/repo --dry-run
./caulking.sh bootstrap --repo /path/to/repo
./caulking.sh doctor --repo /path/to/repo
./caulking.sh run --repo /path/to/repo
```

Or use explicit `--profile` convenience bundles outside a repository:

```bash
./caulking.sh doctor --profile baseline --profile shell --profile container
```

Or install a bundle directly with Homebrew Bundle:

```bash
brew bundle install --file=brewfiles/baseline.Brewfile --no-upgrade
brew bundle install --file=brewfiles/shell.Brewfile --no-upgrade
```

## Brewfile bundles and minimum-version model

Homebrew `Brewfile` syntax selects package names; it does not support arbitrary
`>=` SemVer constraints. Caulking pairs selective `brewfiles/<profile>.Brewfile`
files with explicit minimum version checks in `caulking doctor`:

- **Bootstrap (`caulking bootstrap`):** Installs missing selected packages on
  macOS with `HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_INSTALL_UPGRADE=1` and
  `HOMEBREW_NO_INSTALL_CLEANUP=1`. It does not upgrade, downgrade, unlink,
  remove, or reinstall broken existing packages.
- **Frequent `brew upgrade` support:** Developers can run `brew upgrade`
  regularly. `caulking doctor` enforces justified minimum supported version
  floors without imposing artificial upper bounds, so routine upstream tool
  updates do not require a new `caulking` release.
- **Dual Bash posture:** `scripts/toolchain.sh` is compatible with `/bin/bash`
  (macOS system Bash 3.2) so `caulking bootstrap` and `caulking doctor` can run
  even before Homebrew `bash >=4.0.0` is on the interactive `PATH`, while the
  `baseline` profile provisions and verifies Homebrew `bash >=4.0.0` for
  `install.sh` and global hooks.
- **`golangci-lint` v1/v2 compatibility:** `caulking doctor` accepts
  `golangci-lint >=1.59.0` (both late v1 and v2). Repositories upgrading to
  `golangci-lint` v2 must include `version: "2"` in `.golangci.yml` (see
  `starter-configs/go-repo.pre-commit-config.yaml`).

Doctor inspects Homebrew `opt`/`Cellar` (and `Caskroom` for `tflint`) locations
and runs absolute executable version probes (`tofu --version` for `opentofu`,
`go version` for `go`, `gitleaks version` for `gitleaks`, and `--version` for
other tools). Version and prefix probes have five-second direct-child deadlines.

Exit codes: `0` means selected tools are healthy; `1` means a missing, outdated,
or broken dependency or installation/probe failure; `2` means invalid input.
`run` propagates the runner's exit code, including genuine lint failures.

## 5-Pillar Per-Language Minimum Baseline Matrix

Across all **11 profiles**, **31 profile tools**, **65 reusable hooks**, and **9 starter configs**, caulking covers five verification pillars (`FMT`, `LINT`, `CHECK`, `SAST`, `SCA`):

| Ecosystem | Profiles | `FMT` | `LINT` | `CHECK` | `SAST` | `SCA` |
| --- | --- | --- | --- | --- | --- | --- |
| **Baseline (All)** | `baseline` | `trailing-whitespace`, `end-of-file-fixer` | `check-merge-conflict`, `check-added-large-files` | `check-yaml-selfcontained`, `check-json-selfcontained`, `check-gsa-email` | Global `gitleaks` (`pre-commit` + `pre-push`) | — |
| **Shell** | `baseline`, `shell` | `shfmt` / `shfmt-check` | `shellcheck` | `bash-syntax` (`bash -n`) | `shellcheck` + `semgrep` | — |
| **Python** | `baseline`, `python` | `ruff-format` / `ruff-format-check` | `ruff-check` | `mypy` / `pyright` | `bandit` | `pip-audit` |
| **Go** | `baseline`, `go` | `go-fmt` / `gofmt-selfcontained` | `golangci-lint` | `go-vet` / `go-vet-selfcontained` | `gosec` / `gosec-selfcontained` | `govulncheck` / `govulncheck-selfcontained` |
| **JS / TS** | `baseline`, `javascript`, `security` | `prettier` / `biome-check` | `eslint` / `biome-check` | `tsc` | `semgrep` | `npm-audit` / `pnpm-audit` / `yarn-audit` / `retire-js` / `osv-scanner-lockfile` |
| **Ruby / InSpec** | `baseline`, `ruby`, `security` | `rubocop` | `rubocop` / `rubocop-check` | `ruby-check` (`ruby -c`) | `semgrep` | `osv-scanner-lockfile` / `bundle-audit` |
| **OpenTofu / Terraform** | `baseline`, `opentofu` \| `terraform`, `security` | `tofu-fmt` \| `terraform-fmt` | `tflint` | `tofu-validate` \| `terraform-validate` | `semgrep` / `checkov` | `osv-scanner` |
| **Containers** | `baseline`, `container`, `security` | — | `hadolint` | `hadolint` | `semgrep` | `grype` + `syft` |
| **Docs / YAML / CI** | `baseline`, `docs` | `yamlfmt` / `markdownlint` | `yamllint` / `markdownlint-check` | `actionlint` / `check-yaml-selfcontained` | `zizmor` | — |

## Coverage boundaries

- **Reusable hooks and starter configs:** `.pre-commit-hooks.yaml` at the root
  of `cloud-gov/caulking` defines all 65 reusable hooks. All 9 copy-to-start
  configurations in `starter-configs/` work as a single `.pre-commit-config.yaml`
  file—`caulking.sh bootstrap --repo .`, `caulking.sh doctor --repo .`, and
  `caulking.sh run --repo .` derive the required Homebrew formulae directly from
  enabled hook IDs.
- **Self-contained syntax hooks:** `check-yaml-selfcontained` and
  `check-json-selfcontained` use runner-managed Python environments (`PyYAML==6.0.3`
  for YAML; stdlib for JSON) invoked with `python -I -m cloud_gov_pre_commit_checks`,
  preventing `PYTHONPATH` and working-directory shadowing. Legacy `check-yaml`
  and `check-json` remain available for backward compatibility.
- **Self-contained Go hooks:** `gofmt-selfcontained`, `go-vet-selfcontained`,
  `gosec-selfcontained`, and `govulncheck-selfcontained` use `language: golang`
  (backed by root `go.mod`) so CI and container environments without a
  pre-installed Go toolchain can bootstrap Go 1.25.8 automatically.
- **Global `gitleaks` isolation and `CAULKING_NO_TOOLCHAIN_PATH=1` opt-out:**
  Explicit `./caulking.sh setup --no-install` enables toolchain-aware global
  hooks, which automatically run `hook-run` whenever a repository contains
  `.pre-commit-config.yaml` (unless `CAULKING_NO_TOOLCHAIN_PATH=1` is set as an
  opt-out escape hatch to use the direct ambient runner path). Global secret
  scanning always runs before the repo hook suite using caulking's pinned
  `gitleaks` binary and config, never the repo-scoped `PATH`. Never set
  `SKIP=gitleaks` globally to deduplicate a repo hook, as that bypasses
  caulking's global secret scan.

## Verification performed

- `make check-consolidated`: runs `make test`, `make test-toolchain`,
  `make verify-hooks`, `make test-python`, and `make verify-release`.
- `/bin/bash tests/toolchain.sh` and `./tests/toolchain.sh`: isolated checks
  exercising `.pre-commit-config.yaml` hook-to-formula derivation, all 11
  profiles (`baseline`, `shell`, `container`, `python`, `go`, `javascript`,
  `ruby`, `opentofu`, `terraform`, `docs`, `security`), all 31 profile tools,
  minimum-version floor rejection, upgraded-version acceptance, `opentofu`
  (`tofu`) and `markdownlint-cli` (`markdownlint`) binary resolution,
  `go version` probing, `tflint` Caskroom/opt resolution, and `brewfiles/*.Brewfile`
  presence.
- `python3 scripts/validate-hooks.py` and `bash scripts/test-validate-hooks.sh`:
  validates all 65 hooks in `.pre-commit-hooks.yaml` and all 9 `starter-configs/*.yaml`
  files against `HOOK_FORMULAE` and `FORMULA_PROFILE`.
- `python3 -m unittest discover -s tests -p "test_python_checks.py" -v` and
  `python3 tests/try_repo_python_checks.py`: verifies isolated YAML/JSON hooks.
- `shellcheck -x`, `shfmt -d`, `yamllint -d relaxed`, and `actionlint`.
- Multi-model consensus review `job-vote-76e4c3fc-37c8-47e7-90cd-167a52da0150`
  (record `vote-1794244071006-yqyunpa`): **approved** (6 approve, 0 reject,
  1 unverifiable abstention; 100% approval across 5 distinct models and 4 model
  families).
- Iterative implementation panel reviews (`vote-1794246736577-pho1bzx` ->
  `vote-1794247774409-5c0xfdy` -> `vote-1794249285609-i8lvu6w`): identified
  starter-config profile alignment and Python profile `bandit`/`pip-audit`
  provisioning on `scoped_path`; after adding `bandit` (`>=1.7.5`) and `pip-audit`
  (`>=2.7.0`) to `brewfiles/python.Brewfile` and `scripts/toolchain.sh`, both
  Security Engineer and Scope Steward approved the bound implementation
  (`vote-1794249285609-i8lvu6w`, 2 approve, 0 reject, 1 parser error -> `no_quorum`).

## Sources

- [Homebrew Bundle and Brewfile](https://docs.brew.sh/Brew-Bundle-and-Brewfile)
- [Pre-commit supported languages](https://pre-commit.com/#supported-languages)
- [ADR-0001: Release Management](adr/ADR-0001-release-management.md)
- [ADR-0002: Template Consolidation and Brewfile Bundles](adr/ADR-0002-template-consolidation-and-brewfile-bundles.md)
