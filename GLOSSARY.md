# Caulking

Caulking is cloud.gov's workstation secret-prevention, repository hook provider, and developer toolchain manager. It enforces global Git pre-commit and pre-push guardrails while provisioning and verifying the language tools required by each repository's `.pre-commit-config.yaml`.

## Language

### Global Guardrails

**Global Hook**:
A workstation-wide Git hook (`pre-commit` or `pre-push`) installed under the user's XDG configuration directory via `core.hooksPath` that intercepts every commit and push across all repositories on the machine.
_Avoid_: Local hook, repo hook, wrapper

**Filename Denylist**:
The non-bypassable policy that blocks commits containing high-risk credential or state filenames (such as `.pem`, `.key`, `.env`, `id_rsa`, or `.tfstate`) regardless of file contents.
_Avoid_: Blocklist, ignore list, forbidden paths

**Global Secret Scan**:
The mandatory `gitleaks` content scan executed by a Global Hook against staged changes (`pre-commit`) or pushed commit ranges (`pre-push`) using the global policy and an optional Repository Allowlist.
_Avoid_: Repo gitleaks hook, local scan

**Repository Allowlist**:
A repository-root `.gitleaks.repo.toml` file that extends the default `gitleaks` ruleset to allowlist known-safe test fixtures or fake tokens for that repository only.
_Avoid_: Global config, skip flag, exception file

### Hooks and Configurations

**Hook Provider**:
A Git repository exposing reusable hook definitions in a root `.pre-commit-hooks.yaml` manifest that consuming repositories reference by `repo:` and immutable release tag (`rev:`) in `.pre-commit-config.yaml`.
_Avoid_: Template repo, starter config, plugin

**System Hook**:
A hook in `.pre-commit-hooks.yaml` (declared with `language: system` or `language: unsupported`) that expects its underlying analyzer executable to be provisioned on the host workstation rather than inside a runner-managed virtualenv.
_Avoid_: Native hook, local hook, ambient hook

**Self-Contained Hook**:
A hook in `.pre-commit-hooks.yaml` (suffixed `-selfcontained` and declared with `language: python` or `language: golang`) whose runtime and pinned dependencies are automatically provisioned in an isolated cache by the Runner.
_Avoid_: Isolated hook, container hook, bundled hook

**Starter Configuration**:
A copy-to-start `.pre-commit-config.yaml` file in `starter-configs/` representing the recommended 5-pillar hook baseline for a single language archetype.
_Avoid_: Template, inherited config, profile

### Toolchain and Onboarding

**Stack**:
A language or configuration ecosystem detected in a repository's tracked files (`shell`, `container`, `python`, `go`, `javascript`, `ruby`, `opentofu`, `terraform`, or `docs`) used by `caulking detect` and `caulking init` to recommend hooks.
_Avoid_: Profile, bundle, language pack

**Profile Bundle**:
A named, composable Homebrew Bundle file (`brewfiles/<profile>.Brewfile`) grouping the Homebrew formulae or casks for a domain (`baseline`, `shell`, `container`, `python`, `go`, `javascript`, `ruby`, `opentofu`, `terraform`, `docs`, `security`).
_Avoid_: Stack, `.caulking-profiles`, tap

**Minimum Version Floor**:
The lowest SemVer version of a tool that Caulking's `doctor` and `run` commands accept as compatible, allowing developers to run `brew upgrade` freely without upper-bound locks.
_Avoid_: Pinned version, exact lock, Brewfile constraint

**Scoped PATH**:
The deterministic executable search path constructed by Caulking from verified Homebrew `opt/<formula>/bin` directories and system utilities when running a repository's hooks, isolating execution from interactive shell drift.
_Avoid_: Ambient PATH, global PATH, virtualenv

**Runner**:
The hook execution engine (`prek` by default, or `pre-commit` as a fallback) that evaluates a repository's `.pre-commit-config.yaml` after the Filename Denylist and Global Secret Scan pass.
_Avoid_: Wrapper, dispatcher, installer
