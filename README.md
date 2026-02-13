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

That’s it.

If `make verify` fails, it will tell you exactly what is wrong and what to do next. Read the output. It’s not poetry, but it is honest.

---

## Daily use

Once installed, you don’t “run” Caulking.

You just do normal work:

```bash
git commit -m "..."
git push
```

If you stage or push something that looks like a secret, gitleaks blocks it.

---

## Linting this repo (contributors)

This repo also includes a local `.pre-commit-config.yaml` for formatting/linting the repo itself.

Run it with:

```bash
make lint
```

It uses:

- `prek` if available
- otherwise `pre-commit`

If neither is installed, it fails with a clear message. That’s intentional.

---

## Verify / Audit

Verify proves the hook setup works and that enforcement actually blocks a known fake secret.

```bash
make verify
```

Audit is intentionally boring and currently aliases verify:

```bash
make audit
```

If you’re looking for a 40-page compliance narrative, you’re again in the wrong repo.

---

## Install details

### Where things go (XDG)

Hooks:

- `~/.config/git/hooks/pre-commit`
- `~/.config/git/hooks/pre-push`

Gitleaks config:

- `~/.config/gitleaks/config.toml`

State:

- `~/.config/caulking/previous_hookspath` (used to restore your prior `core.hooksPath` on uninstall)

---

## Skipping gitleaks (break-glass)

If you _really_ need to bypass gitleaks for a single operation:

```bash
SKIP=gitleaks git commit -m "..."
SKIP=gitleaks git push
```

This is not a feature. It’s an escape hatch. Use it like a fire extinguisher: rarely, and with regret.

If you’re hitting false positives, the right fix is:

- adjust the pattern (best)
- add a **repo** allowlist in `.gitleaks.repo.toml` (acceptable)
- bloating global allowlists (usually a mistake)

---

## Troubleshooting

### Hooks installed but not running

```bash
git config --global --get core.hooksPath
ls -la ~/.config/git/hooks
```

You want `core.hooksPath` to be `~/.config/git/hooks` and the hook files to be executable.

### Install fails with permission issues

```bash
chmod +x install.sh uninstall.sh verify.sh hooks/*.sh scripts/*.sh tests/*.sh
```

Then retry `make install`.

### Someone bypassed hooks

If a repo sets a **local** `core.hooksPath`, it can override the global one.

You can check a directory tree of repos with:

```bash
./check_repos.sh <root_dir> check_hooks_path
```

---

## Uninstall

```bash
make uninstall
```

This:

- removes installed hook scripts from `~/.config/git/hooks/`
- restores your previous `core.hooksPath` if Caulking recorded one
- leaves your global gitleaks config in place (on purpose)

---

## Security reporting

Please don’t report vulnerabilities in public GitHub issues.

Follow the instructions in [`SECURITY.md`](SECURITY.md) and Cloud.gov’s security.txt.

---

## License

This project is public domain (CC0). See [`LICENSE.md`](LICENSE.md).
