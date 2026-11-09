# Cloud.gov toolchain bootstrap research and implementation plan

**Status:** Consolidated implementation in `cloud-gov/caulking`; `cloud-gov/pre-commit-templates` frozen as compatibility endpoint.
**Date:** 2026-11-09
**Implementation owner:** `cloud-gov/caulking` (global hooks, selective `brewfiles/` bundles, `caulking.sh` toolchain CLI, `.pre-commit-hooks.yaml`, `starter-configs/`, and ADRs).

## Current ownership decision

Caulking is now the consolidated single repository for:
1. Global Git hooks (`pre-commit`, `pre-push`), filename denylist, and tailored `gitleaks` policy.
2. Selective workstation tooling profiles (`.caulking-profiles`) and composable Brewfiles (`brewfiles/<profile>.Brewfile`).
3. Minimum supported SemVer floor verification in `caulking doctor` (allowing developers to run `brew upgrade` freely without needing a caulking release per upstream tool patch).
4. Reusable hook definitions (`.pre-commit-hooks.yaml`), self-contained Python/Go hooks (`cloud_gov_pre_commit_checks/`, `pyproject.toml`, `go.mod`), and `starter-configs/`.
5. Unified SemVer release management via Release Please (`VERSION`, `.release-please-manifest.json`, `release-please-config.json`).

`cloud-gov/pre-commit-templates` is frozen as a read-only compatibility endpoint so existing pinned tags (`v0.5.3`, `v0.6.0`, etc.) continue serving consumers until they migrate their `repo:` URL to `https://github.com/cloud-gov/caulking`.

See [current implementation and verification](toolchain-bootstrap.md) and [ADR-0002](adr/ADR-0002-template-consolidation-and-brewfile-bundles.md). Earlier split-repository proposals below are preserved as research and review history.

## Summary

Automate workstation setup with a small caulking bootstrap integration around
existing package managers. Start with general-task's missing Hadolint and Python
YAML dependency. Install selected dependencies during explicit setup, check them
before use, and provide the same executable environment to terminal and Git hooks.
Expand profiles after the pilot proves useful. This is not a proposal to build a
general-purpose package manager or move installation code into this template repo.

## Evidence and limitations

Read-only GitHub inventory captured 387 credential-visible cloud-gov repositories:
235 archived, 67 forks (50 also archived), leaving **135 active nonfork repos**.
119 have a primary language; 16 do not. Visibility was not captured, so this is
neither a public-only census nor guaranteed complete private-repository coverage.

| Primary language | Count |
| --- | ---: |
| Shell | 39 |
| Python | 26 |
| JavaScript | 13 |
| Go | 11 |
| HTML | 9 |
| Ruby | 6 |
| HCL | 5 |
| TypeScript | 3 |
| Astro, CSS, Dockerfile, Java, Mermaid, Perl, PHP | 1 each |
| None | 16 |

Default-branch language APIs, complete recursive trees, and selected configs were
sampled for 20 active nonfork repos: caulking, general-task, deploy-bosh,
terraform-provision, site, docs, deploy-stratos, aws-broker,
external-domain-broker, uaa-bot, sandbox-bot, cg-oracle-database-19c-stig-overlay,
pages-core, pages-editor, cg-ui, csb, cf-hello-worlds, pre-commit-templates,
compliance, vestigia. Five sampled repos were private. No private source contents
are reproduced here. The following are sample observations, not org-wide rates:

- YAML present in 20/20; Dockerfile-named files in 10/20.
- HCL in five, but two were fixtures; three operational IaC examples.
- Six root pre-commit configs and one additional custom hook script.
- No Rust manifests in the sample; no Rust-primary repos in the inventory.
- Ruby/InSpec/RSpec is a real coverage gap; Java/Maven appears in example apps.
- Primary language hides YAML, IaC, Docker, docs, and secondary runtimes.

Representative public evidence:

| Repository/path | Existing tools or requirements |
| --- | --- |
| [general-task config](https://github.com/cloud-gov/general-task/blob/main/.pre-commit-config.yaml) | v0.5.3 hygiene, ShellCheck, shfmt, Hadolint |
| [aws-broker config](https://github.com/cloud-gov/aws-broker/blob/main/.pre-commit-config.yaml) | Go formatting/vet, golangci-lint, shell checks |
| [aws-broker lint config](https://github.com/cloud-gov/aws-broker/blob/main/.golangci.yml) | golangci-lint v2 schema |
| [external-domain-broker config](https://github.com/cloud-gov/external-domain-broker/blob/main/.pre-commit-config.yaml) | Black/Flake8; do not force Ruff migration |
| [terraform-provision config](https://github.com/cloud-gov/terraform-provision/blob/main/.pre-commit-config.yaml) | yamlfmt, shell, OpenTofu-or-Terraform formatting |
| [pages-core package](https://github.com/cloud-gov/pages-core/blob/main/package.json) | Project-local ESLint, Prettier, JS tests |
| [sandbox-bot Gemfile](https://github.com/cloud-gov/sandbox-bot/blob/main/Gemfile) | Ruby/Bundler, RSpec/WebMock |
| [docs package](https://github.com/cloud-gov/docs/blob/main/package.json) | Docusaurus/MDX; Markdown checking |
| [Java examples](https://github.com/cloud-gov/cf-hello-worlds/tree/main/java-hello) | Maven; on-demand Java coverage |

Inspected revisions:

- templates HEAD: `fdc9551daaf9bf16c889e8bfa4e0cb7a07cf60b2`.
- caulking main: `68c6d45f9b2cefe334672e6715323a2b776806c4`.
- general-task main: `c55bcad45d13bb7c94a77dc52fa56f9666bfcd0f`.

Counts are computed from the captured gh inventory; sampled observations are
agent-assisted research, not independent audits. Re-run before broad rollout:
`gh repo list cloud-gov --limit 500 --json name,isArchived,isFork,primaryLanguage,description,updatedAt`.
Use paginated inventory if the organization outgrows this limit.

## Current behavior: source excerpts

The relevant template at v0.5.3, and current Hadolint definition, use:

```yaml
- id: hadolint
  entry: hadolint
  language: system
```

YAML/JSON checks invoke an external interpreter:

```yaml
entry: python3 -c "import sys, yaml; [yaml.safe_load(open(f)) for f in sys.argv[1:]]"
language: system
```

Therefore, PyYAML must be importable by the specific Python selected at execution.
Installing the pre-commit application does not establish that import.

[Caulking install.sh](https://github.com/cloud-gov/caulking/blob/68c6d45f9b2cefe334672e6715323a2b776806c4/install.sh)
calls `install_gitleaks_if_missing`, `install_prek_if_missing`, and
`install_precommit_if_missing`; it does not install Hadolint, ShellCheck, or shfmt.
It writes an upstream-gitleaks configuration with `[extend] useDefault = true`.
It currently attempts pip/pipx removal for some existing pre-commit installations;
the bootstrap must preserve existing user-managed installations instead.

[The installed wrapper](https://github.com/cloud-gov/caulking/blob/68c6d45f9b2cefe334672e6715323a2b776806c4/hooks/hook-wrapper.sh)
first checks forbidden files, then gitleaks, then runs:

```bash
prek run --hook-stage "$stage" --show-diff-on-failure
```

It falls back to pre-commit. A configured repo without either runner currently
prints a note and succeeds; propose an actionable nonzero failure for that case.
The wrapper checks `SKIP=gitleaks` before global scanning. Consequently, setting
that variable globally to deduplicate a repo hook also bypasses the global scan.
Any correction must use child-only repo-runner state after global scanning passes.
Repeated `--config` arguments in the current gitleaks invocation must be tested:
do not assume they merge global and repo configuration correctly.

Caulking's default verification checks runner availability, not another repo's
toolchain. general-task's selected hooks do not run its image tests; those expect
a built Linux task environment. Linters and tests are distinct setup targets.

## Options considered

| Option | Advantages | Limits | Recommendation |
| --- | --- | --- | --- |
| Thin selective Homebrew bootstrap | Existing macOS workflow; low implementation cost | Rolling versions, shared global packages | MVP |
| mise runtime/tool profiles | Multi-version selection, explicit exec, macOS/Linux | New dependency/backends/trust surface; auto-install must be controlled | Prototype after measured version conflicts |
| uv isolated Python environments | Reuses existing Python tooling, locks/dependency isolation | Python only; libraries such as PyYAML need an environment, not a CLI tool install | Optional Python adapter after evaluation |
| Self-installing upstream hooks | Framework already manages isolated dependencies | First-run network and differing tool environments | Preserve existing opt-in variants |
| Bespoke binary/package manager | Full control | Download verification, platform matrices, update burden | Avoid |

Homebrew explicitly says Brewfile has no reproducible version lock. `--no-upgrade`
prevents implicit upgrades but does not recreate exact versions on a new machine.
Record installed versions and compatibility checks honestly; exact-version needs
must use a suitable existing manager or remain unresolved.

## Small MVP: caulking integration, general-task pilot

### Requirements

1. Proposed `caulking bootstrap --repo PATH`: install only known dependencies
   selected by the repo. `--dry-run` prints the plan without installing. A deliberate
   bootstrap invocation authorizes selected installs; Git operations never invoke it.
2. Proposed `caulking doctor --repo PATH [--json]`: no downloads or installation;
   reports satisfied, missing, incompatible, runner-managed, or unresolved needs.
   Return nonzero for unmet declared needs. With no parser environment, report
   bootstrap-required rather than trying to parse or install.
3. Proposed `caulking run --repo PATH --all-files`: run the configured hook suite
   through the same scoped environment used by global hooks. Does not run full
   application tests unless they are explicitly declared as hooks.
4. MVP dependency map: native hygiene scripts need Bash/core utilities;
   check-yaml/check-json need managed Python (including PyYAML for YAML);
   shellcheck/shfmt-check/hadolint map to their Homebrew formulae.
5. templates owns a small data-only hook/dependency map with release provenance;
   caulking bundles a reviewed snapshot. Initially support tested v0.5.3 and
   v0.6.0 tuples mapped to immutable provider commits. No runtime metadata service,
   plugin system, or arbitrary provider fetcher is needed for this pilot.
6. Parse repository YAML as bounded data with a safe loader. Inspect only provider,
   pinned revision, hook ids, and known configuration fields. Never execute hook
   entry commands, repo Brewfiles, or task scripts to discover dependencies.
   Unknown hooks/providers, unsupported revisions, entry/language/dependency
   overrides are unresolved; explain the missing coverage explicitly. A separately
   reviewed explicit profile can accommodate team alternatives later.
7. Explicit initial setup obtains a supported Python via the existing package
   manager and creates one caulking-owned venv with pinned/hash-checked PyYAML.
   This environment can serve the parser and syntax hooks; no ambient global pip
   install or second bespoke Python environment manager. Pin package artifacts
   after validating the platform matrix; actual versions are not selected here.
8. Resolve absolute installed CLI paths using the manager; give the repo runner a
   deterministic tool PATH plus a controlled system fallback. Do not rely on an
   interactive shell startup file. Never prepend repo tool paths to global gitleaks
   execution. Project-specific Python execution is an opt-in later profile.
9. Install missing compatible formulae, leave compatible existing ones alone.
   No implicit upgrade, downgrade, unlink, cleanup, global config rewrite, or
   pip/pipx uninstall. An incompatible shared version produces a clear conflict.
   Failed setup leaves existing caulking hooks and environment usable; build venv
   in a temporary location, validate, then activate it atomically.
10. Preserve system hooks and opt-in self-contained hooks. Bootstrap does not
    duplicate runner-owned environments. First-run runner downloads remain their
    existing behavior; optional warming happens during setup. Document scanner
    database/network requirements separately from cached tool availability.

### Acceptance criteria

- Fresh macOS setup with a minimal PATH resolves Hadolint, shell tools, and PyYAML
  for a clean general-task-like fixture using its pinned hook config.
- Bad Dockerfile and bad YAML fixtures fail; known-good fixtures pass. Running
  general-task may still reveal genuine lint violations, not a setup failure.
- Doctor before bootstrap reports missing runtime without installing anything.
- Doctor after bootstrap identifies resolved absolute paths and observed versions.
- Repeating bootstrap with satisfied requirements makes no install/upgrade calls.
- Warmed doctor and syntax/lint fixtures work without network. Cold-cache offline
  requests fail explicitly. No blanket offline guarantee for vulnerability scanners.
- Repo configs with unknown providers, mutable revisions, overridden entries,
  unsafe YAML, oversized inputs, or dependency overrides cannot add install commands.
- Terminal and GUI-like minimal environments select the same tool paths.
- Two repos with incompatible requirements show a conflict without changing the
  first repo's tools. The MVP does not promise side-by-side Homebrew versions.
- Existing pre-commit/mise/pipx installations and global hooksPath remain intact.
- A configured repo missing a runner fails clearly; gitleaks and forbidden-file
  enforcement continue regardless of dependency-check failures.
- Global/default gitleaks detection, repo allowlist behavior, and child-only
  deduplication have end-to-end tests before any scanning integration change ships.
- Native macOS verification is required. Linux container parser/contract tests are
  useful, but do not establish native Linux delivery or macOS platform coverage.
- All changed shell scripts pass `shellcheck -x`; template changes pass `make verify`.

## Coverage roadmap and ownership

| Profile | Install/manage | Remain project-owned |
| --- | --- | --- |
| Baseline | gitleaks + tailored config, prek; compatible pre-commit fallback | Repo hooks and exceptions |
| Shell/container (pilot) | ShellCheck, shfmt, Hadolint | Docker builds/image tests |
| Python | Selected Ruff or existing Black/Flake8; optional Bandit/pip-audit | Runtime constraints, mypy deps, pytest, lockfile environment |
| Go | Go version from project, gofmt/vet, matching golangci-lint major; optional gosec/govulncheck | Module dependencies, go test |
| JS/TS | Compatible Node and declared package manager | Local ESLint/Prettier/TypeScript/Biome, npm/yarn/pnpm audit, tests |
| IaC/YAML | Repo-selected Terraform OR OpenTofu, TFLint, yamlfmt/yamllint if configured | Providers, backend init, plugin config, validation credentials |
| Ruby | Compatible Ruby/Bundler; selected syntax/RuboCop support | Gemfile.lock, RSpec/InSpec profiles and tests |
| Docs | Selected Markdown/MDX checks | Site dependencies/builds/link checks |
| Optional scanning | Semgrep, OSV; Grype/Syft for declared manual tasks | Rules, databases/mirrors, thresholds |
| Operator tools | Separate opt-in CF/BOSH/CredHub/AWS/jq/yq profiles | Credentials, access, deployment workflows |
| Java / other languages | On-demand Java/Maven after usage confirmation | Maven/Gradle wrapper, app tests; Ruby/SQL gap assessment |

Keep native tools narrow: Hadolint being implemented in Haskell does not mean
developers need a Haskell toolchain; similarly Rust-built CLIs do not imply Rust
application demand. Preserve team selections. Existing security ADR exclusions
apply; historical ownership/CVE assertions must be revalidated before new adoption.

## Delivery work packages

1. **Pilot contract and metadata (templates):** small dependency data schema,
   known hook/revision fixtures, proposed ADR. No installation implementation here.
2. **Bootstrap and doctor (caulking):** Homebrew calls, one managed venv, data-only
   parsing, clear tool status, dry-run and repeatability tests.
3. **Runner environment (caulking):** share resolved paths with manual execution
   and global hooks; preserve gitleaks path/config; address missing-runner behavior.
4. **Pilot adoption (general-task):** onboarding command, native macOS trial with
   Mark; fixture and actual-repo results distinguish setup from lint findings.
5. **Measured expansion:** Python/Go/JS/IaC/Ruby/docs profiles and explicit opt-in
   frozen project dependency setup. Never install missing npm packages implicitly
   through npx; use local package-manager execution with download fallback disabled.
6. **Linux and version isolation:** define distro/arch support; test manager choices
   against two real incompatible repos, offline caches, corporate proxy/CA, rollback.
   Adopt mise/uv through a separate ADR only if they reduce measured complexity.

Sequence 1-4 before 5-6. Estimate 1-2 engineer-days for the contract/metadata,
3-5 for bootstrap/doctor, 2-3 for runner integration/tests, and 1-2 for pilot/docs:
**7-12 engineer-days**, rough planning estimate, not a commitment. Validate with
maintainers before scheduling. No organization-wide adoption until pilot gates pass.

## Review history

Nexus discovery/registry/OSS searches returned no matching results; primary-source
documentation below supplied the package-manager evidence. Architecture/security
expert calls timed out. Nexus orchestration returned a generic decomposition but
its three dispatched workers failed with unknown model context windows, so it
provided no verified expert design.

First full-panel vote: `job-vote-bfa2a54d-0272-4715-b209-10da11320ce6`, record
`vote-1793896928632-yiml2la`: **no_quorum** (1 approve, 1 reject, 5 unverifiable
abstentions). Missing inlined artifact prevented five seats inspecting evidence.
The substantive rejection cited overengineering and unclear repo ownership. This
revision narrows the MVP to thin caulking integration, a single venv and bundled
metadata, and makes scope, estimates, evidence, and acceptance gates explicit.
An artifact-bound second review is required; no first-round approval is claimed.

Second artifact-bound vote: `job-vote-9c62461b-934e-45db-bd39-4528affa5dbe`,
record `vote-1793897716570-e7o4yut`: **no_quorum**, with 5 approve, 1 reject,
and 1 unverifiable abstention. The absolute-quorum policy was retained; this is
favorable review feedback, not formal approval. The scope steward still required
repository access beyond the inlined plan. The contrarian preferred a simpler
repo bootstrap or existing self-installing hooks and questioned the implementation
cost and direct-runner environment divergence.

In response, add a **timeboxed 1 engineer-day feasibility spike before work
package 1**: compare a reviewed static shell/container profile driven by existing
Homebrew commands with the config-derived map, using general-task. If the static
profile meets the onboarding/doctor/path requirements with materially less code,
use it for the pilot and defer auto-selection metadata. Also test direct prek,
IDE-configured runner execution, and global Git hooks separately: only caulking's
resolved runner environment is promised until direct-runner integration is proved.
This follow-up revision has not been re-voted. Maintainer scope/platform/ownership
decisions and a verifiable review remain prerequisites for implementation rollout.

Before merging implementation, specify parser byte/depth/alias limits, subprocess
timeouts, canonical repo path handling, and controlled PATH fallback; add metadata
snapshot drift checks if the config-derived design survives the spike. No scanner
or package-manager readiness is inferred from plan votes.

## Maintainer direction and Homebrew delivery

William confirmed on 2026-11-05:

- Start with a macOS pilot; native Linux follows.
- Prefer Homebrew-style installation and lifecycle management.
- Install language-appropriate tools selectively, because repos need different sets.
- Existing mise/uv/asdf adoption is unknown; they are not initial prerequisites.

### Proposed packaging contract

Evaluate a cloud.gov Homebrew tap and a `caulking` formula. The tap location and
formula name are placeholders until repository ownership and existing taps are
checked. A formula should install the caulking CLI, its profile data, and its own
runtime dependencies using Homebrew conventions. Investigate Homebrew's standard
Python virtualenv support for the CLI's PyYAML dependency instead of adding an
independent venv lifecycle manager where that support suffices.

The package baseline is gitleaks and prek plus the runtime required by caulking.
Preserve pre-commit fallback for existing users; installing both runners should
not be necessary for a fresh setup. Install-time package operations must not
configure global Git hooks or modify a user's shell configuration. Run explicit
caulking setup after package installation to configure hooks and tailored gitleaks
policy. Formula upgrades and removals must not silently rewrite that policy.

Proposed user journey (not currently available commands):

```bash
brew install <cloud-gov-tap>/caulking
caulking setup
caulking bootstrap --repo . --dry-run
caulking bootstrap --repo .
caulking doctor --repo .
```

Start with reviewed declarative profiles, not language-specific formula copies:

- `shell`: ShellCheck and shfmt.
- `container`: Hadolint; additive to shell when the repo needs both.
- Later `python`, `go`, `javascript`, `ruby`, `iac`, and `docs` profiles select
  compatible runtime/native tools; project packages remain project-local.
- Heavy scanners and operator CLIs are selected additions, not baseline installs.

Use one bootstrap implementation with these composable profiles. A repo may
declare required profiles as data; hook-to-profile auto-selection is an optional
next step after the pilot. File/language detection can suggest profiles but must
not enable checks or install every tool for a language merely because a fixture
or example exists. general-task should select shell + container + syntax needs.
Do not install both Terraform and OpenTofu by default or assume a universal
Node/Python/Ruby version works across projects.

Homebrew owns package upgrades through explicit `brew upgrade` workflows.
Bootstrap installs missing requirements without upgrading compatible installed
packages. Doctor checks compatibility after upgrades and identifies unresolved
exact-version needs. Homebrew formula dependency support is not evidence that all
tools can share one interpreter: test both the formula's Python and syntax-hook
execution paths before claiming the PyYAML problem solved.

The feasibility spike should therefore compare static profile composition using
Homebrew (including packaging a caulking CLI) against config-derived selection.
Verify formula installation, upgrade and removal in an isolated macOS test
environment; user Git configuration and tailored policy must remain explicit.

### Remaining ownership decisions

- Which cloud.gov repository/tap should publish the formula, and who maintains it?
- Who reviews profile additions, compatibility ranges, and catalog updates?
- What project-level declaration format gives teams a simple, durable way to
  select profiles? Prefer a small data contract over duplicated installation scripts.

This maintainer-directed packaging refinement has not been re-voted. Earlier
Nexus feedback is planning input, not approval of a Homebrew formula implementation.

## Feasibility implementation results (2026-11-05)

The spike selected static profiles. A local caulking checkout now contains
`caulking.sh`, `scripts/toolchain.sh`, and `tests/toolchain.sh`, with an explicit
`make test-toolchain` target. These are uncommitted prototype changes, not released
interfaces. `.caulking-profiles` declares baseline/shell/container as bounded
data-only names. No YAML discovery layer is required for this scope.

Independent review fixed four issues: ancestor config discovery, Homebrew's
Ruby-provisioning side effects during named list queries, gitleaks minimum-version
enforcement, and unbounded version probes. Doctor now inspects opt/Cellar paths;
probes have five-second direct-child deadlines. The 46 isolated checks passed
under Bash 3.2 and current Bash. Real native Homebrew doctor resolved all six
profile tools; local system-hook fixtures passed good files, failed a bad Dockerfile
with Hadolint DL3007, and rejected a configless child directory. No package installs
or global Git configuration changes were made.

Research located the existing `cloud-gov/homebrew-cloudgov` tap. Publish a future
`caulking` formula there rather than creating a new tap. A private PyYAML venv can
be built with Homebrew's low-level Python virtualenv helpers while keeping Bash
source. Prefer a dedicated syntax command rather than redirecting all project
Python hooks. Caulking has no public source tags/releases at research time, so
formula source URL/hash publication requires a real release first.

The prototype still lacks Python/PyYAML, global-hook environment integration,
JSON diagnostics, and a published formula; it does not fully solve general-task
onboarding. Details and remaining gates live in caulking's
`docs/toolchain-bootstrap.md`.

Third planning vote `job-vote-b2788651-0c0e-4d65-93ff-96853ac491b7`, record
`vote-1793905916533-1i3ep9j`, returned 6 approve, 0 reject, 1 unverifiable abstention:
**no_quorum** under absolute-quorum policy. The contrarian favored the narrower
static-profile scope. Formal approval is not claimed. An attempted Nexus
code-review workflow failed input validation (`files` required), providing no
review evidence; an artifact-bound implementation panel was requested separately.

Implementation panel `job-vote-4f8e37fa-bdea-40cf-9f53-02333f0cb3aa`, record
`vote-1793907647583-0hlo2hz`, returned **no_quorum**: 1 security approval, 1
architect parsing error, and 1 unverifiable scope-steward abstention. No consensus
approval is claimed. Caulking's existing `make test` suite passed alongside the
new toolchain checks. Native formula install/upgrade/removal remains untested.

Consolidation and selective Brewfile bundles specification vote
`job-vote-76e4c3fc-37c8-47e7-90cd-167a52da0150`, record `vote-1794244071006-yqyunpa`,
returned **approved** (100% approval among responding seats: 6 approve, 0 reject,
1 unverifiable abstention across 5 distinct models and 4 model families). The
panel approved consolidating `.pre-commit-hooks.yaml`, `starter-configs/`,
self-contained Python/Go hooks, selective `brewfiles/<profile>.Brewfile` bundles,
and minimum supported SemVer floors in `caulking doctor` into `cloud-gov/caulking`
while freezing `cloud-gov/pre-commit-templates` as a compatibility endpoint.

## References

- [Homebrew Bundle](https://docs.brew.sh/Brew-Bundle-and-Brewfile): no lockfile,
  no-upgrade semantics, scoped execution; Brewfiles are executable Ruby.
- [mise tools](https://mise.jdx.dev/dev-tools/): multi-version selection, exec,
  configurable automatic installs; do not delegate unreviewed repo config to it.
- [uv tools](https://docs.astral.sh/uv/concepts/tools/): isolated Python CLI
  environments; project-aware tools need project dependencies.
- [pre-commit languages](https://pre-commit.com/#supported-languages).
- [Template ADR-0002](https://github.com/cloud-gov/pre-commit-templates/blob/main/docs/adr/ADR-0002-supply-chain-security.md),
  [Template ADR-0006](https://github.com/cloud-gov/pre-commit-templates/blob/main/docs/adr/ADR-0006-selfcontained-hook-variants.md),
  [Template ADR-0007](https://github.com/cloud-gov/pre-commit-templates/blob/main/docs/adr/ADR-0007-gitleaks-via-upstream-hook.md).
