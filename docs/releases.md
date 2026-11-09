# Releases and compatibility

## Stable installation

The latest published, non-prerelease GitHub Release is stable:
https://github.com/cloud-gov/caulking/releases/latest

Use its immutable `vX.Y.Z` tag for installation and reusable hook revisions.
`main` is development, not a stable installation reference. Never move published
version tags. As of 2026-11-08, no tags/releases were published: VERSION 3.3.0 and
older changelog links are historical labels, not proof of released artifacts.

## Release Please on GitHub Actions

One root release covers caulking and, after consolidation, reusable checks and
bundles. VERSION contains plain SemVer; the release manifest tracks the same
version. Release Please's simple strategy updates both and CHANGELOG.md.

On main pushes, the SHA-pinned Release Please action opens/updates a release PR.
After maintainers merge that PR, the next run creates its tag and GitHub Release.
There is no automatic merge. A manual workflow dispatch can recover a missed run.
Release jobs serialize to avoid simultaneous updates.

Initial configuration uses 3.3.0 as the historical baseline and bootstrap commit
`68c6d45f9b2cefe334672e6715323a2b776806c4`, the observed main HEAD before this work.
It does not fabricate v3.3.0. Review the first proposed version and release notes;
the first published version depends on the commits merged after that boundary.
Remove bootstrap-sha after the first successful release establishes history.

Repository Actions settings must allow Actions to create/approve pull requests;
the workflow needs contents and pull-requests write permissions. It does not
approve PRs itself. PRs created with GITHUB_TOKEN generally do not trigger other
PR workflows. If required checks are configured, use a narrowly scoped GitHub App
token for Release Please, or have a maintainer trigger checks through an approved
process. Do not disable required checks to merge release PRs.

## Conventional Commits and SemVer

PR titles are checked on every PR title/edit/code update. Use squash merging with
the validated PR title as the commit subject; repository merge settings and
required status checks must be configured by maintainers (not changed locally).
Direct main pushes bypass PR title checks and must use the same convention.

- `fix:`: patch release.
- `feat:`: minor release.
- `feat!:` or `BREAKING CHANGE:` footer: major release.
- docs/test/ci/chore changes alone generally do not produce a release.

Breaking hook IDs, CLI behavior, or supported configurations require a major
release. New compatible hooks/bundles require a minor release. Implementation
corrections normally require a patch. Do not hand-edit generated release entries.
Retain historical changelog text as history until reviewed; broken old tag links
must not be mistaken for published releases.

Validate locally with `python3 scripts/check-release-config.py`. This validates
local invariants, not remote permissions or actual release creation. Publication
has not been performed during development.

## Tool versions are separate from caulking releases

Brewfiles (`brewfiles/<profile>.Brewfile`) declare package names, not arbitrary `>=`
version constraints. Homebrew installs rolling current versions. Compatibility
checks in `caulking doctor` enforce minimum supported versions across all **11 profiles**
and **31 profile tools** (backing all **65 reusable hooks** and **9 starter configs**
under the 5-Pillar Per-Language Minimum Baseline Matrix: `FMT`, `LINT`, `CHECK`,
`SAST`, `SCA`), without pinning each upstream patch:

| Profile | Tool | Minimum enforced by `caulking doctor` | Rationale |
| --- | --- | --- | --- |
| `baseline` | `gitleaks` | `>= 8.21.0` | `[extend] useDefault = true` and modern rule schema |
| `baseline` | `prek` | `>= 0.4.0` | `--hook-stage` and `--show-diff-on-failure` CLI contract |
| `baseline` | `bash` | `>= 4.0.0` | Associative/array safety for `install.sh`, global hooks, and `bash-syntax` (`bash -n`) |
| `shell` | `shellcheck` | `>= 0.9.0` | `-x` external source following and stable directive support |
| `shell` | `shfmt` | `>= 3.6.0` | `-d` diff-check and `-w -i 2 -ci -sr` formatting flag stability |
| `container` | `hadolint` | `>= 2.12.0` | Modern OCI/BuildKit `Dockerfile` syntax support |
| `python` | `ruff` | `>= 0.4.0` | Unified `ruff check` and `ruff format` (`--check`) CLI |
| `python` | `mypy` | `>= 1.8.0` | Modern `pyproject.toml` configuration support |
| `python` | `pyright` | `>= 1.1.350` | Fast Python static type checking with `pyproject.toml` support |
| `python` | `bandit` | `>= 1.7.5` | Python SAST CLI with `pyproject.toml` config support |
| `python` | `pip-audit` | `>= 2.7.0` | PyPA vulnerability scanner for `requirements.txt` / `pyproject.toml` |
| `go` | `go` | `>= 1.22.0` | Modern module/workspace routing (`go version`) |
| `go` | `golangci-lint` | `>= 1.59.0` | Supports late v1 and v2 (`version: "2"` in `.golangci.yml` for v2) |
| `go` | `gosec` | `>= 2.18.0` | Go security SAST checker (`gosec ./...`) |
| `go` | `govulncheck` | `>= 1.0.0` | Official Go vulnerability scanner (`govulncheck ./...`) |
| `javascript` | `node` | `>= 20.0.0` | Active LTS floor for `npx` project-local linters |
| `ruby` | `ruby` | `>= 3.2.0` | Supported Ruby 3.2+ floor for syntax validation (`ruby -c`), Bundler, and InSpec overlays |
| `ruby` | `rubocop` | `>= 1.60.0` | Modern RuboCop plugin/department configuration floor |
| `opentofu` | `opentofu` (`tofu`) | `>= 1.6.0` | `tofu fmt` / `tofu validate` GA floor |
| `terraform` | `terraform` | `>= 1.5.0` | `terraform fmt` / `terraform validate` floor |
| `opentofu` / `terraform` | `tflint` | `>= 0.50.0` | HCL2 plugin configuration floor (`tflint` shared across both profiles; 31 profile-tool entries across 11 profiles, 30 unique formulae/casks) |
| `docs` | `yamllint` | `>= 1.35.0` | `-d relaxed` preset and modern Python 3.12+ compatibility |
| `docs` | `yamlfmt` | `>= 0.13.0` | Google YAML formatter and `-lint` check mode |
| `docs` | `actionlint` | `>= 1.7.0` | Current GitHub Actions runner/context schema support |
| `docs` | `zizmor` | `>= 1.0.0` | Static security analysis for GitHub Actions workflows |
| `docs` | `markdownlint-cli` (`markdownlint`) | `>= 0.39.0` | `--fix` flag and modern CommonMark rule floor |
| `security` | `semgrep` | `>= 1.50.0` | `semgrep scan --config=auto --error --metrics=off` |
| `security` | `osv-scanner` | `>= 1.7.0` | `osv-scanner scan` subcommand syntax |
| `security` | `syft` | `>= 1.0.0` | `-o cyclonedx-json=...` v1 CLI contract |
| `security` | `grype` | `>= 0.74.0` | `dir:. --fail-on` CLI contract |
| `security` | `checkov` | `>= 3.2.0` | Policy-as-code IaC SAST scanner (`checkov -d . --quiet --compact`) |

Use explicit `brew upgrade` to maintain tools independently of caulking releases.
Onboarding can use `caulking bootstrap` or `brew bundle install --file=brewfiles/<profile>.Brewfile --no-upgrade`
to avoid unrequested updates. Doctor accepts newer versions without artificial
upper bounds. Project-local runtime and dependency constraints remain project-owned.

Caulking updates are needed for behavior changes, new profiles/hooks, or revised
compatibility requirements, not every upstream tool release.
