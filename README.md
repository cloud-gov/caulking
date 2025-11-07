# Caulking

A small utility that keeps your Git repositories from leaking secrets, skipping hooks, or quietly drifting out of compliance.
It’s designed to be boring, fast, and hard to screw up.

---

## What it does

Caulking gives you:

- **A real Python CLI** (`caulking`) built with [Typer](https://typer.tiangolo.com/) — not a pile of brittle shell glue.
- **Pre-commit integration** that automatically enforces:

  - [`ruff`](https://docs.astral.sh/ruff) for linting and formatting
  - [`mypy`](https://mypy.readthedocs.io) for strict typing
  - [`bandit`](https://bandit.readthedocs.io) for security checks
  - [`gitleaks`](https://github.com/gitleaks/gitleaks) for secret scanning
  - [`detect-secrets`](https://github.com/Yelp/detect-secrets) for baseline validation

- **A “doctor”** that checks your local environment and pre-commit setup for sanity.
- **A clean transition path** away from global hook hacks — no black magic hiding in `/usr/local`.

You can think of it as a safety net for engineers who care about not shipping accidents.

> **Note:** the original Caulking was a solid bash tool that did its job.
> This rewrite keeps its practicality but trades shell tricks for maintainable Python.

---

## Philosophy

- If something’s broken, fail loudly.
- Every developer should see the same results.
- Security and hygiene checks are mandatory, not optional.
- Hooks should be silent when everything’s fine and blunt when it isn’t.
- Clarity beats cleverness. Always.

If you enjoy debugging your own YAML, this probably isn’t for you — and that’s fine.

---

## Prerequisites (macOS)

Caulking assumes you’re on an up-to-date Mac. You don’t need much, but you do need a sane base environment.

### 1. Xcode Command Line Tools

Install them once. They provide Git, Make, and a compiler.

```bash
xcode-select --install
```

### 2. Homebrew

We use it for everything else. If you don’t have it: https://brew.sh/

### 3. Python 3.11+ (preferably 3.12)

Caulking runs on modern Python only.

```bash
brew install python@3.12
```

Confirm:

```bash
python3 --version
```

### 4. uv (preferred dependency manager)

Caulking relies on [uv](https://docs.astral.sh/uv) to manage its environment cleanly.

```bash
brew install uv
```

(You can use `pipx` if you insist, but we test primarily with `uv`.)

### 5. Git

Comes with the Xcode tools. Just verify:

```bash
git --version
```

That’s it. No Docker, no weird SDKs.

---

## Quickstart (the smart way)

### 1. Remove any legacy Caulking installs

If you used the old bash version, it may have left global hooks behind. Clean them up:

```bash
# Preview what will be removed
caulking uninstall-legacy
# Actually remove them
caulking uninstall-legacy --apply
```

If you don’t have `caulking` yet, clone the repo and bootstrap:

```bash
git clone https://github.com/cloud-gov/caulking.git
cd caulking
make bootstrap
```

That installs dependencies, syncs your environment, and installs pre-commit hooks locally.

---

### 2. Install Caulking globally

You can install it once and use it everywhere.

```bash
uv tool install .
# or
pipx install .
```

Confirm it’s available:

```bash
caulking doctor
```

If it reports a healthy environment, you’re set.

---

### 3. Configure Caulking per repository

From the root of any project you want protected:

```bash
caulking smart-install --apply
```

That command builds or merges a `.pre-commit-config.yaml` for your tech stack — Python, Node, Go, Rust, whatever.

Then install the hooks:

```bash
pre-commit install --install-hooks
```

Every `git commit` now automatically runs your hygiene checks.

---

### 4. Keep it up to date

```bash
caulking update
```

That refreshes all hooks and rule sets. It’s fast, so don’t overthink it.

---

### 5. Verify

Run:

```bash
caulking doctor
```

If you see green, relax.
If you see red, fix it. The tool isn’t being fussy — it’s right.

---

## Typical workflow

| Command                 | Purpose                                      |
| ----------------------- | -------------------------------------------- |
| `make qa`               | Run all checks: lint, type, security, tests  |
| `make fmt`              | Format code with Ruff                        |
| `make lint`             | Run Ruff linting                             |
| `make type`             | Run mypy strict typing                       |
| `make sec`              | Run Bandit, Gitleaks, and Detect-Secrets     |
| `make test`             | Run pytest                                   |
| `make hooks.install`    | Install or update pre-commit hooks           |
| `make hooks.clean`      | Clear cached hook environments and reinstall |
| `make uninstall.legacy` | Remove old global Caulking setups            |

You can skip hooks if you must:

```bash
git commit -n
```

But if you commit a secret that way, that’s on you.

---

## Design intent

Caulking should be simple, predictable, and almost invisible.
It should fail clearly, not mysteriously.
It’s meant to remove friction — not introduce another layer of ceremony.

It exists so you can stop worrying about whether your code is safe to push and just get back to shipping it.

---

## Troubleshooting

- **Doctor fails:** Something’s missing. Read the message — it’s probably right.
- **Hooks don’t run:** Try `pre-commit install --install-hooks` again.
- **Old `gitleaks` warnings:** Update your binary (`make hooks.update`).
- **Too many lint errors:** Run `make fmt` and move on.

## Author’s note

Caulking exists because “remember to check before you commit” is not a real policy.
Good tools take care of you quietly — until you ignore them.
That’s what Caulking does: it automates discipline, so you can focus on real work.
