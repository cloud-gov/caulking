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

- Private keys: `.pem`, `.key`, `.der`, `.p12`, `.pfx`, `.jks`, `.keystore`, `.kdbx`, `.agekey`
- SSH keys: `id_rsa`, `id_dsa`, `id_ecdsa`, `id_ed25519`, `ssh_host_*_key`
- Credentials: `.env`, `.envrc`, `.netrc`, `.git-credentials`
- Cloud configs: `.aws/credentials`, `.kube/config`, `.docker/config.json`, `.cf/config.json`
- Terraform: `.tfstate`, `.tfstate.backup`, `.terraform/`, `.terraformrc`
- System files: `shadow`, `passwd`, `group`, `gshadow`
- Package auth: `.npmrc`, `.pypirc`, `.vault-token`

This denylist cannot be bypassed via allowlist. If you need to commit a `.pem` file, you are doing something wrong.

---

## Prerequisites

Required:

- `git` (configured with user.name and user.email)
- `bash` 4.0+
- `gitleaks` v8.21.0+

Optional (but useful):

- `brew` (macOS install helper)
- `prek` **or** `pre-commit` (only needed if you want to run repo lint/format hooks via `make lint`)

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

This repo includes a local `.pre-commit-config.yaml` for formatting and linting itself.

```bash
make lint
```

Uses:

- `prek` if available
- otherwise `pre-commit`

If neither is installed, it fails loudly. This is deliberate.

---

## Local testing

Run the test suite:

```bash
make test           # macOS (native)
make docker-test    # Linux (Ubuntu container)
make docker-full    # Full install + verify + test in Linux
```

For cross-distro validation:

```bash
make docker-debian  # Debian 12
make docker-alpine  # Alpine Linux (musl)
make docker-all     # All distros
```

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
