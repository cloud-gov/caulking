# Caulking

Caulking installs **global Git hooks** that run **gitleaks** so you don’t accidentally commit or push secrets.

It’s intentionally boring:

- deterministic install
- predictable XDG layout
- explicit verify/audit
- minimal moving parts

If you want fancy, you’re in the wrong repo. If you want “it works the same every time,” welcome.

---

## What it does

After install, Git will use a global hooks directory:

- Hooks live at: `~/.config/git/hooks/`
  - `pre-commit` (scans staged changes)
  - `pre-push` (scans the pushed range)
- Git is set to use it globally:
  - `git config --global core.hooksPath ~/.config/git/hooks`

Caulking also writes a global gitleaks config:

- `~/.config/gitleaks/config.toml`

**Important:** the global config must extend defaults, or you’ve built security theater:

```toml
[extend]
useDefault = true
```

---

## Prerequisites

Required:

- `git`
- `bash`
- `gitleaks` v8+ (Caulking will try to install/upgrade via Homebrew on macOS)

Optional (but useful):

- `brew` (macOS install helper)
- `prek` **or** `pre-commit` (only needed if you want to run repo lint/format hooks via `make lint`)

---

## Quick start

```bash
git clone <repo-url>
cd caulking
make install
make verify
```

If `make verify` fails, it will tell you what is broken and how to fix it. The output is not lyrical, but it is correct.

---

## Daily use

Once installed, you don’t “run” Caulking.

You just work:

```bash
git commit -m "..."
git push
```

If you stage or push something that looks like a secret, gitleaks blocks it. That is the whole point.

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

## Verify / Audit

Verify proves that enforcement actually works:

```bash
make verify
```

Audit is intentionally boring and currently aliases verify:

```bash
make audit
```

If you want pretty dashboards, write one. This tool is about not leaking secrets.

---

## Install details

### Where things go (XDG)

Hooks:

- `~/.config/git/hooks/pre-commit`
- `~/.config/git/hooks/pre-push`

Gitleaks config:

- `~/.config/gitleaks/config.toml`

State:

- `~/.config/caulking/previous_hookspath`

This exists solely to restore your previous `core.hooksPath` on uninstall. It is not a feature. It is housekeeping.

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

Fix the offenders. Don’t normalize bypassing guardrails.

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
