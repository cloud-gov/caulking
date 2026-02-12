# Caulking

Caulking installs **global Git hooks** that run **gitleaks** to prevent secrets from being committed or pushed.

This repo is intentionally boring:

- deterministic install
- predictable layout (XDG)
- easy verify/audit
- tests that prove it works

---

## What you get

After `make install`, you’ll have:

### Global hooks (XDG)

Installed into:

- `~/.config/git/hooks/pre-commit`
- `~/.config/git/hooks/pre-push`

And Git is configured to use that directory globally:

- `git config --global core.hooksPath ~/.config/git/hooks`

### Global gitleaks config (XDG)

Installed into:

- `~/.config/gitleaks/config.toml`

**Important:** the global config must **extend defaults** (`[extend] useDefault = true`).  
If you don’t extend defaults, you silently drop core detectors and your “protection” becomes theater.

---

## Quick start

### Clone (with submodules)

This repo uses Bats via submodules.

```bash
git clone --recurse-submodules <repo-url>
cd caulking
```

If you already cloned without submodules:

```bash
git submodule sync --recursive
git submodule update --init --recursive
```

### Install

```bash
make install
```

What install does:

- ensures `gitleaks` exists (Homebrew best-effort on macOS)
- installs the global hook wrapper as `~/.config/git/hooks/pre-commit` and `pre-push`
- sets `core.hooksPath` globally to the XDG hook directory
- writes `~/.config/gitleaks/config.toml` (or upgrades it) to extend defaults

### Verify

```bash
make verify
```

This validates:

- `gitleaks` runs
- `core.hooksPath` is set to the expected global hook dir
- hooks exist and are executable
- the global gitleaks config extends defaults
- functional behavior:
  - committing a known fake secret is blocked
  - committing a clean file succeeds

---

## Audit (policy checks + tests)

```bash
make audit
```

Audit does:

- ensures tools
- runs `selftest.sh` (repo-specific checks)
- runs Bats tests in `caulked.bats`

Some audit checks assume you’re using a `@gsa.gov` email for Git config, because the repo asserts a “GSA developer baseline.”

---

## How it works

### The hook wrapper

The enforcement point is:

- global `core.hooksPath`
- wrapper script installed at `~/.config/git/hooks/<stage>`

Hook wrapper responsibilities:

- run `gitleaks` using the global config at `~/.config/gitleaks/config.toml`
- respect `SKIP=gitleaks` if the user insists (don’t prompt in a hook)
- attempt to run any repo-local hook at `.git/hooks/<stage>` (best-effort), without recursion

### What about `hooks.gitleaks`?

Treat `hooks.gitleaks` as **legacy/policy toggle**, not enforcement.

Enforcement is:

- the global hook path
- the hook wrapper actually running `gitleaks`

If a repo sets `core.hooksPath` locally, it can bypass global hooks. That’s why the audit includes checks to detect local overrides.

---

## Skipping gitleaks (when you must)

If you’re doing something truly intentional and you accept the risk, you can skip for a single operation:

```bash
SKIP=gitleaks git commit -m "..."
```

This is a last resort. Prefer fixing the pattern, updating allowlists, or adjusting rules.

---

## Running tests manually

### Bats (core tests)

```bash
./test/bats/bin/bats -p caulked.bats
```

Filter tests:

```bash
./test/bats/bin/bats -p caulked.bats --filter "leak prevention.*"
```

### Development tests

```bash
./test/bats/bin/bats -p development.bats
```

---

## Keeping Bats submodules updated

This repo pins submodules to specific commits. To force your working tree to match the pinned commits:

```bash
git submodule sync --recursive
git submodule update --init --recursive
```

If you intend to **bump** the pinned versions (and commit that change), do:

```bash
git submodule update --remote --merge --recursive
git status
# review changes, then commit the updated submodule SHAs
```

---

## Repository hygiene

If you’ve been iterating hard and want to remove junk + normalize permissions:

```bash
./scripts/cleanup-vestigial.sh --apply
```

If you want it to also update submodules to pinned commits:

```bash
./scripts/cleanup-vestigial.sh --apply --update-submodules
```

---

## Security reporting

Please do not file security issues in public GitHub issues.

Use the reporting instructions in `SECURITY.md` and cloud.gov’s `security.txt`.

---

## Public domain

This project is in the worldwide public domain (CC0).
See `LICENSE.md`.

---

## “If it breaks”

Common failure modes:

### `make install` fails with permission denied

Fix executable bits:

```bash
chmod +x install.sh scripts/*.sh hooks/*.sh || true
```

### Hooks installed but don’t run

Check:

```bash
git config --global --get core.hooksPath
ls -la ~/.config/git/hooks
```

### Bats doesn’t output anything / returns rc=0 instantly

Usually you’re invoking the wrong bats entrypoint or you have submodule mismatch.
Use the repo’s bats binary:

```bash
./test/bats/bin/bats --version
./test/bats/bin/bats --list-tests caulked.bats
./test/bats/bin/bats -p caulked.bats
```

If needed:

```bash
git submodule sync --recursive
git submodule update --init --recursive
```
