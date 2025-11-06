# Caulking

A small utility that keeps your Git repositories from leaking secrets, skipping hooks, or silently drifting out of compliance.
It’s designed to be boring, fast, and hard to screw up.

---

## What It Does

Caulking provides:

- **A proper Python CLI** (`caulking`) built with [Typer](https://typer.tiangolo.com/) — no brittle shell glue.
- **Pre-commit integration** that enforces:
  - [`ruff`](https://docs.astral.sh/ruff) formatting and linting first (because style is cheap to fix)
  - [`mypy`](https://mypy.readthedocs.io) strict typing
  - [`bandit`](https://bandit.readthedocs.io) security checks
  - [`gitleaks`](https://github.com/gitleaks/gitleaks) scans without the ancient `--source` flag
  - [`detect-secrets`](https://github.com/Yelp/detect-secrets) baseline validation
- **A “Doctor” mode** that inspects your local environment and pre-commit configuration for sanity.
- **A transition path** away from legacy global hooks — no black magic hiding in `/usr/local`.

You can think of it as a lightweight self-defense mechanism for engineers who actually care about not shipping accidents.

---

## Philosophy

- If something breaks, it should **fail loudly and immediately**.
- Every tool should run the same way on every developer’s machine.
- Security and hygiene checks are not optional.
- A good hook is one you can trust to run silently when it should, and shout when it must.

If you like fiddling with YAML until it barely works, this is not your tool.

---

## Quick Start

You’ll need [uv](https://docs.astral.sh/uv) installed.
Then:

```bash
make bootstrap
```

That installs dependencies, syncs the dev environment, and installs pre-commit hooks.

You can confirm everything’s healthy with:

```bash
make hooks.doctor
```

If you see a green checkmark, you’re fine. If you see red, fix it before committing.

---

## Typical Workflow

| Command                 | What it does                                                             |
| ----------------------- | ------------------------------------------------------------------------ |
| `make qa`               | Run the full quality gate: format, lint, type-check, security-scan, test |
| `make fmt`              | Format code with Ruff                                                    |
| `make lint`             | Run Ruff linting                                                         |
| `make type`             | Run strict typing via mypy                                               |
| `make sec`              | Run Bandit, Gitleaks, and Detect-Secrets                                 |
| `make test`             | Run pytest                                                               |
| `make hooks.install`    | Install local pre-commit and pre-push hooks                              |
| `make hooks.update`     | Update hook versions to match the latest stable                          |
| `make hooks.clean`      | Clear cached hook environments and reinstall                             |
| `make hooks.run`        | Run all hooks across all files                                           |
| `make uninstall.legacy` | Remove old global Caulking hook setups (safe preview by default)         |

If you’re the type who can’t resist skipping hooks, at least be explicit about it:

```bash
git commit -n
```

But remember — if your code leaks a secret, that’s on you.

---

## Philosophy on Dependencies

We keep them minimal, pinned, and reproducible.
Everything runs inside the `uv` environment, so there’s no need to pollute your system Python.
If you add dependencies, **justify them** and document why.

---

## CI/CD

If you really must run this in CI, just do:

```bash
make qa
```

That’ll give you the same checks developers see locally.
If you disable something in CI, you’d better have a written reason.

---

## Troubleshooting

- **`pre-commit` complaining about missing environments:**
  Run `make hooks.clean`.

- **`gitleaks` yelling about `--source`:**
  You’re using an old version. Run `make hooks.update`.

- **`ruff` flagging hundreds of style issues:**
  Just run `make fmt`. Don’t argue with the linter; it’s faster.

- **`doctor` says something is missing:**
  Read the message. It’s probably right.

---

## Uninstalling Old Caulking Hooks

If you’re migrating from the pre-Python era:

```bash
make uninstall.legacy
# or, to actually apply changes:
make uninstall.legacy APPLY=1
```

This removes global hooks, stray symlinks, and random rc-file snippets.
You’ll thank yourself later.

---

## Project Goals

1. Be maintainable by adults.
2. Fail predictably.
3. Prefer clarity over cleverness.
4. Require no extra explanation.

---

## Author’s Note

This project exists because security shouldn’t depend on people remembering to do the right thing.
It should be automatic, quiet when happy, and honest when broken.

That’s what Caulking does.
