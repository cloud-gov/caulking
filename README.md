# Caulking

**Operator:** GSA / cloud.gov | **License:** CC0 (Public Domain)

Caulking installs **global Git hooks** that run **gitleaks** so you don't accidentally commit or push secrets.

It's intentionally boring:

- deterministic install
- predictable XDG layout
- explicit verify/audit
- minimal moving parts

If you want fancy, you're in the wrong repo. If you want "it works the same every time," welcome.

---

## What it does

After install, Git will use a global hooks directory:

- Hooks live at: `~/.config/git/hooks/`
  - `pre-commit` (scans staged changes)
  - `pre-push` (scans the pushed range)
- Git is configured to use this globally (done by `make install`):
  - `git config --global core.hooksPath ~/.config/git/hooks`

Caulking also writes a global gitleaks config:

- `~/.config/gitleaks/config.toml`

**Important:** the global config must extend defaults, or you've built security theater:

```toml
[extend]
useDefault = true
```

---

## What gets blocked

Caulking prevents two categories of leaks:

### 1. Content-based detection (gitleaks)

Gitleaks scans staged content for patterns matching:

- AWS access keys and secrets
- GitHub/GitLab tokens
- Private keys (RSA, DSA, ECDSA, Ed25519)
- API keys and bearer tokens
- Database connection strings
- And 100+ other secret patterns

See the [gitleaks rule list](https://github.com/gitleaks/gitleaks#rules) for details.

### 2. Filename-based blocking (built-in denylist)

Caulking blocks commits containing high-risk file types regardless of content:

- Private keys: `.pem`, `.key`, `.p12`, `.pfx`, `.jks`
- SSH keys: `id_rsa`, `id_ed25519`, `id_ecdsa`, `ssh_host_*_key`
- Credentials: `.env`, `.envrc`, `.netrc`, `.git-credentials`
- Cloud configs: `.aws/credentials`, `.kube/config`, `.docker/config.json`
- Terraform state: `.tfstate`, `.tfvars`

This denylist cannot be bypassed via allowlist. If you need to commit a `.pem` file, you are doing something wrong.

---

## Prerequisites

Required:

- `git` (configured with user.name and user.email)
- `bash` 4.0+
- `gitleaks` v8.21.0+

Recommended (auto-installed via Homebrew on macOS):

- `brew` (macOS package manager)
- `prek` (fast Git hook manager, preferred) **or** `pre-commit` (for running repo-local hooks)

**Note:** If you have `brew` installed, `make install` will automatically install `gitleaks` and `prek` if they're missing, while preserving any existing user-managed `pre-commit` installation.

### Installing gitleaks

**macOS (Homebrew):**

```bash
brew install gitleaks
```

If gitleaks is missing during `make install`, Caulking will attempt to install it via Homebrew automatically.

**Linux (manual):**

```bash
# Download latest release (adjust version and arch as needed)
GITLEAKS_VERSION=8.30.1
ARCH=x64  # or arm64 for ARM systems

curl -sSfL -o /tmp/gitleaks.tar.gz \
  "https://github.com/gitleaks/gitleaks/releases/download/v${GITLEAKS_VERSION}/gitleaks_${GITLEAKS_VERSION}_linux_${ARCH}.tar.gz"

sudo tar xzf /tmp/gitleaks.tar.gz -C /usr/local/bin gitleaks
rm /tmp/gitleaks.tar.gz

# Verify installation
gitleaks version
```

**Linux (package managers):**

```bash
# Arch Linux (AUR)
yay -S gitleaks

# NixOS
nix-env -iA nixpkgs.gitleaks
```

For other distributions, see the [gitleaks releases page](https://github.com/gitleaks/gitleaks/releases).

---

## Quick start

```bash
git clone https://github.com/cloud-gov/caulking.git
cd caulking
make install
make verify
```

If `make verify` passes, you'll see an audit box confirming all checks passed with a verification ID for compliance records.

If `make verify` fails, it will tell you what is broken and how to fix it. The output is not lyrical, but it is correct.

---

## Daily use

Once installed, you don't "run" Caulking.

You just work:

```bash
git commit -m "..."
git push
```

If you stage or push something that looks like a secret, gitleaks blocks it. That is the whole point.

### When a commit is blocked

If you stage a secret, the commit will fail with output showing:

- The matched rule (e.g., `aws-access-token`)
- The file and line number
- A snippet of the matched content

The commit does not proceed. Fix the issue before continuing.

---

## Ignoring false positives (do this properly)

False positives happen. The correct fix is to teach the scanner, not to train yourself to ignore warnings.

### Per-repo allowlist (preferred)

Add a file named `.gitleaks.repo.toml` at the root of your repository:

```toml
title = "Repo allowlist"

[extend]
useDefault = true

[allowlist]
description = "Allow known-safe patterns for this repo"

regexes = [
  # Example: fake test secret used in fixtures
  "FAKE_TEST_SECRET_12345",
]

paths = [
  # Example: allow generated artifacts or fixtures
  "fixtures/.*",
]
```

This is the **right default** for:

- test fixtures
- fake credentials
- intentionally embedded example tokens
- generated files you do not control

It keeps the global policy strict while allowing local exceptions where they make sense.

### Global allowlist (use sparingly)

The global gitleaks config lives at:

```text
~/.config/gitleaks/config.toml
```

It contains a small allowlist section:

```toml
[allowlist]
regexes = [
  "(?i)example(_|-)?key",
  "(?i)dummy(_|-)?secret",
]
```

Only put patterns here that are:

- universally safe across _all_ repos you work in
- genuinely non-secret examples

If you find yourself wanting to add lots of entries here, you are probably doing the wrong thing. Move them into a per-repo allowlist instead.

### One-time break-glass (last resort)

If you need to bypass gitleaks for a single operation:

```bash
SKIP=gitleaks git commit -m "..."
SKIP=gitleaks git push
```

This bypasses gitleaks pattern scanning only. The filename denylist cannot be bypassed.

This is an escape hatch, not a workflow.
If you use it often, your rules are wrong and you should fix them.

---

## Linting this repo (contributors)

### Releases and stable versions

Use the latest published non-prerelease tag for stable installation; `main` is
development. Historical VERSION labels do not establish published tags. See
[release management](docs/releases.md) for Release Please, initial bootstrap,
Conventional Commits, and independent Homebrew tool upgrades.

### Selective workstation toolchain & Brewfile bundles

Caulking includes 11 selective Homebrew bundles (`brewfiles/<profile>.Brewfile`)
covering 31 profile tools (`gitleaks >=8.21.0`, `prek >=0.4.0`, `bash >=4.0.0`,
`shellcheck >=0.9.0`, `shfmt >=3.6.0`, `hadolint >=2.12.0`, `ruff >=0.4.0`,
`mypy >=1.8.0`, `pyright >=1.1.350`, `bandit >=1.7.5`, `pip-audit >=2.7.0`,
`go >=1.22.0`, `golangci-lint >=1.59.0`, `gosec >=2.18.0`, `govulncheck >=1.0.0`,
`node >=20.0.0`, `ruby >=3.2.0`, `rubocop >=1.60.0`, `opentofu >=1.6.0`,
`terraform >=1.5.0`, `tflint >=0.50.0`, `yamllint >=1.35.0`, `yamlfmt >=0.13.0`,
`actionlint >=1.7.0`, `zizmor >=1.0.0`, `markdownlint-cli >=0.39.0`,
`semgrep >=1.50.0`, `osv-scanner >=1.7.0`, `syft >=1.0.0`, `grype >=0.74.0`,
`checkov >=3.2.0`), plus profile-aware bootstrap/diagnostics for
`baseline`, `shell`, `container`, `python`, `go`, `javascript`, `ruby`,
`opentofu`, `terraform`, `docs`, and `security`:

```bash
./caulking.sh bootstrap --profile baseline --profile shell --profile container --dry-run
./caulking.sh doctor --profile baseline --profile shell --profile container
make test-toolchain
```

Repositories can declare required profiles in `.caulking-profiles` (one profile
per line). `caulking doctor` enforces justified minimum supported SemVer floors
for each tool while allowing developers to run `brew upgrade` freely without
waiting for a caulking release.

### Reusable pre-commit hooks and starter configurations

Caulking is the consolidated home for cloud.gov's reusable pre-commit hooks
(`.pre-commit-hooks.yaml`) and copy-to-start configurations (`starter-configs/`),
superseding the frozen `cloud-gov/pre-commit-templates` repository:

- **65 reusable hooks** across hygiene, shell (`shellcheck`, `shfmt`,
  `shfmt-check`, `bash-syntax`), Python (`ruff-check`, `ruff-format`,
  `ruff-format-check`, `mypy`, `pyright`, `bandit`, `pip-audit`), Go (`go-fmt`,
  `go-vet`, `golangci-lint`, `gosec`, `govulncheck`), JS/TS (`eslint`,
  `prettier`, `tsc`, `biome-check`), Ruby (`ruby-check`, `rubocop`,
  `rubocop-check`, `bundle-audit`), IaC (`opentofu`, `terraform`, `tflint`,
  `checkov`), containers (`hadolint`), documentation/YAML/CI (`yamlfmt`,
  `yamlfmt-check`, `yamllint`, `actionlint`, `zizmor`, `markdownlint`,
  `markdownlint-check`), compliance (`check-gsa-email`), and universal scanners
  (`semgrep`, `osv-scanner`, `syft`, `grype`).
- **5-Pillar Per-Language Minimum Baseline Matrix (`FMT`, `LINT`, `CHECK`, `SAST`, `SCA`)**
  spanning all 11 profiles, 31 profile tools, 65 reusable hooks, and 9 starter
  configurations.
- **Self-contained syntax and Go hooks** (`check-yaml-selfcontained`,
  `check-json-selfcontained`, `gofmt-selfcontained`, `go-vet-selfcontained`,
  `gosec-selfcontained`, `govulncheck-selfcontained`) that provision isolated
  environments for CI and containers without ambient `PyYAML` or Go installations.
- **9 starter configurations** in `starter-configs/` paired with `.caulking-profiles`
  bundles (`container-repo`, `docs-yaml-repo`, `go-repo`, `go-repo-selfcontained`,
  `javascript-repo`, `opentofu-repo`, `python-repo`, `ruby-repo`, and
  `terraform-repo`).

See [toolchain bootstrap](docs/toolchain-bootstrap.md),
[release management](docs/releases.md), [ADR-0002](docs/adr/ADR-0002-template-consolidation-and-brewfile-bundles.md),
and [troubleshooting](TROUBLESHOOTING.md) for details. Run `make check-consolidated`
to validate all hooks, profiles, Python checks, and release invariants.

### Repository linting

This repo includes a local `.pre-commit-config.yaml` for formatting and linting itself.

```bash
make lint
```

Uses:

- `prek` if available
- otherwise `pre-commit`

If neither is installed, it fails loudly. This is deliberate.

---

## Verify / Audit

Verify proves that enforcement actually works:

```bash
make verify
```

The verify output includes a verification ID (e.g., `caulk-20260429-221622-bb9a4a92`) with user, host, platform, and timestamp for audit documentation.

For a quick status check:

```bash
make status
```

This shows whether hooks are installed and gitleaks is working, without running the full functional test suite.

Audit is intentionally boring and currently aliases verify:

```bash
make audit
```

If you want pretty dashboards, write one. This tool is about not leaking secrets.

---

## Install details

### Where things go (XDG paths)

Caulking follows the [XDG Base Directory Specification](https://specifications.freedesktop.org/basedir-spec/basedir-spec-latest.html). All files go under `~/.config/`:

Hooks:

- `~/.config/git/hooks/pre-commit`
- `~/.config/git/hooks/pre-push`

Gitleaks config:

- `~/.config/gitleaks/config.toml`

State:

- `~/.config/caulking/previous_hookspath`

This exists solely to restore your previous `core.hooksPath` on uninstall. It is not a feature. It is housekeeping.

---

## Upgrading

Pull the latest version and reinstall:

```bash
cd caulking
git pull
make install
make verify
```

Caulking does not have automatic updates. You are responsible for keeping it current.

---

## Troubleshooting

### Hooks installed but not running

```bash
git config --global --get core.hooksPath
ls -la ~/.config/git/hooks
```

If that path is wrong or the files aren’t executable, your hooks won’t run. This is not subtle.

### Install fails with permission issues

```bash
chmod +x install.sh uninstall.sh verify.sh hooks/*.sh scripts/*.sh tests/*.sh
```

Then rerun:

```bash
make install
```

### Someone bypassed hooks

If a repo sets a **local** `core.hooksPath`, it can override the global one.

Check a tree of repos with:

```bash
./check_repos.sh <root_dir> check_hooks_path
```

This scans all git repositories under `<root_dir>` and reports any that set a local `core.hooksPath`. Fix the offenders. Don't normalize bypassing guardrails.

### Windows

Caulking requires a POSIX shell. On Windows, use WSL (Windows Subsystem for Linux). Native Windows (Git Bash, PowerShell) is not supported.

---

## Uninstall

```bash
make uninstall
```

This:

- removes installed hook scripts
- restores your previous `core.hooksPath` if recorded
- leaves your global gitleaks config in place (on purpose)

If you want to fully nuke state, you can remove the XDG directories yourself. That is your call.

---

## Security reporting

Do **not** report security issues in public GitHub issues.

Follow `SECURITY.md` and cloud.gov’s security.txt.

---

## License

This project is public domain (CC0). See `LICENSE.md`.
