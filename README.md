# Caulking

Caulking installs **global Git hooks** that run **gitleaks** to prevent secrets from being committed or pushed.

This repo is intentionally boring:

- deterministic install
- predictable layout (XDG)
- easy verify / audit
- tests that prove it works

---

## What you get

After `make install`, you’ll have:

### Global hooks (XDG)

Installed into:

- `~/.config/git/hooks/pre-commit`
- `~/.config/git/hooks/pre-push`

Git is configured to use that directory globally:

- `git config --global core.hooksPath ~/.config/git/hooks`

### Global gitleaks config (XDG)

Installed into:

- `~/.config/gitleaks/config.toml`

**Important:** the global config must **extend defaults**:

```toml
[extend]
useDefault = true
```

If you don’t extend defaults, you drop core detectors and your protection becomes theater.

---

## Quick start

### Clone

```bash
git clone <repo-url>
cd caulking
```

### Install

```bash
make install
```

Install does:

- ensures `gitleaks` exists (Homebrew best-effort on macOS)
- installs global hook wrappers into `~/.config/git/hooks/`
- sets `core.hooksPath` globally to the XDG hook directory
- writes or upgrades `~/.config/gitleaks/config.toml` to extend defaults

### Verify

```bash
make verify
```

Verify checks:

- `gitleaks` runs
- `core.hooksPath` is set correctly
- hooks exist and are executable
- global gitleaks config extends defaults
- functional behavior:
  - committing a known fake secret is blocked
  - committing a clean file succeeds

---

## Audit

```bash
make audit
```

Audit is intentionally boring. It proves enforcement works:

- ensures required tools exist
- runs verification checks
- performs functional tests that show secrets are blocked

Some audit checks assume a `@gsa.gov` email in Git config because this repo enforces a GSA developer baseline.

---

## How it works

### Enforcement model

Enforcement is done via:

- global `core.hooksPath`
- a hook wrapper installed at `~/.config/git/hooks/<stage>`

The hook wrapper:

- runs `gitleaks` using the global config at `~/.config/gitleaks/config.toml`
- optionally merges a repo allowlist (`.gitleaks.repo.toml`) if present
- respects `SKIP=gitleaks` if the user explicitly sets it
- attempts to run any repo-local hook at `.git/hooks/<stage>` (best-effort), without recursion

### About `hooks.gitleaks`

Treat `hooks.gitleaks` as legacy.
Enforcement comes from:

- the global hook path
- the wrapper actually running `gitleaks`

If a repo sets `core.hooksPath` locally, it can bypass global hooks.
The audit tooling checks for this.

---

## Skipping gitleaks (break-glass only)

If you accept the risk for a single operation:

```bash
SKIP=gitleaks git commit -m "..."
```

This is a last resort. Prefer fixing patterns, allowlists, or rules.

---

## Repository hygiene

To remove junk and normalize permissions (safe by default):

```bash
./scripts/cleanup-vestigial.sh --apply
```

This:

- removes common untracked cruft
- normalizes executable bits on scripts
- refuses to run if the repo is already messy

It does **not** rewrite tracked files unless explicitly asked.

---

## CI behavior

GitHub Actions runs:

- install
- verify
- audit

This ensures:

- hooks install cleanly
- enforcement works
- regressions are caught before merge

---

## Security reporting

Do **not** report security issues in public GitHub issues.

Use the instructions in `SECURITY.md` and cloud.gov’s security.txt:

- [https://cloud.gov/.well-known/security.txt](https://cloud.gov/.well-known/security.txt)

---

## Contribution policy

This project is operated by GSA to support federal missions.

We accept contributions from:

- U.S. federal employees
- contractors under a current U.S. government agreement
- GSA-approved collaborators

We do **not** accept unsolicited external contributions.

If you have ideas, open an issue first so we can discuss and port them internally if appropriate.

---

## Uninstall

```bash
make uninstall
```

This:

- unsets `core.hooksPath` globally
- removes installed hooks from `~/.config/git/hooks/`
- leaves your global gitleaks config in place

---

## Troubleshooting

### Hooks installed but not running

```bash
git config --global --get core.hooksPath
ls -la ~/.config/git/hooks
```

### Install fails with permission errors

```bash
chmod +x install.sh scripts/*.sh hooks/*.sh
```

### Verify fails

Run:

```bash
./verify.sh
```

The output is explicit about what is broken and how to fix it.

---

## Public domain

This project is in the worldwide public domain (CC0).

See `LICENSE.md`.
