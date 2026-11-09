# Homebrew toolchain bootstrap and selective Brewfile bundles

Status: local consolidated implementation, macOS-first. Includes selective
`brewfiles/<profile>.Brewfile` bundles, minimum SemVer floor verification in
`caulking doctor`, profile-aware global hook integration, reusable
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

Select only the profiles your repository needs. A repository's `.caulking-profiles`
is a data-only text file with one profile per line and optional `#` comments:

```text
baseline
shell
container
```

| Profile | Brewfile bundle | Homebrew packages & minimum versions enforced by `caulking doctor` |
| --- | --- | --- |
| `baseline` | `brewfiles/baseline.Brewfile` | `gitleaks >=8.21.0`, `prek >=0.4.0`, `bash >=4.0.0` |
| `shell` | `brewfiles/shell.Brewfile` | `shellcheck >=0.9.0`, `shfmt >=3.6.0` |
| `container` | `brewfiles/container.Brewfile` | `hadolint >=2.12.0` |
| `python` | `brewfiles/python.Brewfile` | `ruff >=0.4.0`, `mypy >=1.8.0`, `bandit >=1.7.5`, `pip-audit >=2.7.0` |
| `go` | `brewfiles/go.Brewfile` | `go >=1.22.0`, `golangci-lint >=1.59.0` |
| `javascript` | `brewfiles/javascript.Brewfile` | `node >=20.0.0` |
| `opentofu` | `brewfiles/opentofu.Brewfile` | `opentofu` (`tofu >=1.6.0`), `terraform-linters/tap/tflint >=0.50.0` |
| `terraform` | `brewfiles/terraform.Brewfile` | `hashicorp/tap/terraform >=1.5.0`, `terraform-linters/tap/tflint >=0.50.0` |
| `security` | `brewfiles/security.Brewfile` | `semgrep >=1.50.0`, `osv-scanner >=1.7.0`, `syft >=1.0.0`, `grype >=0.74.0` |

No profiles are implied. Repeated `--profile` flags add to the file's selections,
and shared tools (such as `tflint` across `opentofu` and `terraform`) are
automatically deduplicated. Unknown profiles and malformed files fail before
installation. `.caulking-profiles` is limited to 64 KiB and 128 lines, rejects
NUL bytes, and is never sourced or executed as shell code.

From the caulking checkout:

```bash
./caulking.sh bootstrap --repo /path/to/repo --dry-run
./caulking.sh bootstrap --repo /path/to/repo
./caulking.sh doctor --repo /path/to/repo
./caulking.sh run --repo /path/to/repo
```

Or use explicit selections without creating a profiles file:

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

## Coverage boundaries

- **Reusable hooks and starter configs:** `.pre-commit-hooks.yaml` at the root
  of `cloud-gov/caulking` defines all 49 reusable hooks. Copy-to-start
  configurations in `starter-configs/` include `.caulking-profiles` pairings.
- **Self-contained syntax hooks:** `check-yaml-selfcontained` and
  `check-json-selfcontained` use runner-managed Python environments (`PyYAML==6.0.3`
  for YAML; stdlib for JSON) invoked with `python -I -m cloud_gov_pre_commit_checks`,
  preventing `PYTHONPATH` and working-directory shadowing. Legacy `check-yaml`
  and `check-json` remain available for backward compatibility.
- **Self-contained Go hooks:** `gofmt-selfcontained`, `go-vet-selfcontained`,
  `gosec-selfcontained`, and `govulncheck-selfcontained` use `language: golang`
  (backed by root `go.mod`) so CI and container environments without a
  pre-installed Go toolchain can bootstrap Go 1.25.8 automatically.
- **Global `gitleaks` isolation:** Explicit `./caulking.sh setup --no-install`
  enables profile-aware global hooks. Global secret scanning always runs before
  the repo hook suite using caulking's pinned `gitleaks` binary and config,
  never the repo-scoped `PATH`. Never set `SKIP=gitleaks` globally to
  deduplicate a repo hook, as that bypasses caulking's global secret scan.

## Verification performed

- `make check-consolidated`: runs `make test`, `make test-toolchain`,
  `make verify-hooks`, `make test-python`, and `make verify-release`.
- `/bin/bash tests/toolchain.sh` and `./tests/toolchain.sh`: 99 isolated checks
  exercising all 9 profiles (`baseline`, `shell`, `container`, `python`, `go`,
  `javascript`, `opentofu`, `terraform`, `security`), minimum-version floor
  rejection, upgraded-version acceptance, `opentofu` (`tofu`) binary resolution,
  `go version` probing, `tflint` Caskroom/opt resolution, and `brewfiles/*.Brewfile`
  presence.
- `python3 scripts/validate-hooks.py` and `bash scripts/test-validate-hooks.sh`:
  validates all 49 hooks in `.pre-commit-hooks.yaml` and all 7 `starter-configs/*.yaml`
  files against `PROFILE_BINARIES`.
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
