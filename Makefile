# Makefile — Caulking
# Keep it simple. Keep it reproducible. Be a good neighbor in other repos.
#
# Conventions:
# - All tools run via `uv run` to keep versions sane.
# - Ruff runs first. If style is broken, fix it before you waste time elsewhere.
# - Hooks are client-side and blocking by default; you can bypass when necessary.
#
# Pro tips:
# - To bypass hooks in a pinch: `git commit -n` (not recommended).
# - To skip specific hooks once: `SKIP=ruff,gitleaks pre-commit run --all-files`.
# - To repair a broken local pre-commit env: `make hooks.clean && make hooks.install`.

SHELL := /bin/bash -o pipefail

# ---------------------------------------------------------------------
# Paths & naming
# ---------------------------------------------------------------------
REPO_ROOT      := $(shell pwd)
SRC_DIR        := src
PKG_NAME       := caulking
PKG_DIR        := $(SRC_DIR)/$(PKG_NAME)
TESTS_DIR      := tests
RULES_DIR      := rules
TEMPLATES_DIR  := templates

# ---------------------------------------------------------------------
# Tool shims (keep them short and obvious)
# ---------------------------------------------------------------------
UV             := uv
PYTHON         := $(UV) run python
RUFF           := $(UV) run ruff
MYPY           := $(UV) run mypy
BANDIT         := $(UV) run bandit
PYTEST         := $(UV) run pytest
PRECOMMIT      := $(UV) run pre-commit
GITLEAKS       := $(UV) run gitleaks
DETECTSECRETS  := $(UV) run detect-secrets

# Config files
PYPROJECT      := pyproject.toml
PRECOMMIT_YML  := .pre-commit-config.yaml
GITLEAKS_TOML  := $(RULES_DIR)/gitleaks.toml
DS_BASELINE    := $(RULES_DIR)/detect-secrets.baseline

# Defaults
.DEFAULT_GOAL := help

# Grouped phony targets
.PHONY: help bootstrap sync fmt lint type sec test qa all \
        hooks.install hooks.update hooks.clean hooks.run hooks.doctor \
        tools.versions gitleaks.scan ds.audit ensure.all-repos \
        uninstall.legacy clean distclean

# ---------------------------------------------------------------------
# Help
# ---------------------------------------------------------------------
help:
	@printf "\nCaulking — developer targets\n\n"
	@printf "  make bootstrap        Install deps and pre-commit hooks using uv\n"
	@printf "  make sync             Resolve and install env via uv (incl. dev extras)\n"
	@printf "  make fmt              Run Ruff formatter\n"
	@printf "  make lint             Ruff check (no format). Fix with: '$(RUFF) check . --fix'\n"
	@printf "  make type             mypy (strict)\n"
	@printf "  make sec              Bandit, gitleaks (git mode), detect-secrets (baseline)\n"
	@printf "  make test             Pytest\n"
	@printf "  make qa               fmt + lint + type + sec + test\n"
	@printf "  make all              alias for 'qa'\n"
	@printf "\nHooks & doctor:\n"
	@printf "  make hooks.install    Install pre-commit hooks (pre-commit & pre-push)\n"
	@printf "  make hooks.update     Update hook versions (autoupdate)\n"
	@printf "  make hooks.clean      Clear pre-commit caches and reinstall hooks\n"
	@printf "  make hooks.run        Run all hooks on all files\n"
	@printf "  make hooks.doctor     Run Caulking Doctor checks\n"
	@printf "\nScans:\n"
	@printf "  make gitleaks.scan    Run gitleaks in 'git --pre-commit' mode (no --source)\n"
	@printf "  make ds.audit         Run detect-secrets with the repo baseline\n"
	@printf "\nFleet ops:\n"
	@printf "  make ensure.all-repos ROOT=~/dev  Install hooks across repos under ROOT\n"
	@printf "  make uninstall.legacy             Remove legacy global hooks and settings\n"
	@printf "\nMaintenance:\n"
	@printf "  make tools.versions   Print versions for the toolchain\n"
	@printf "  make clean            Remove build/test artifacts\n"
	@printf "  make distclean        clean + drop uv caches (aggressive)\n\n"

# ---------------------------------------------------------------------
# Bootstrap / env sync
# ---------------------------------------------------------------------
bootstrap: sync hooks.install
	@printf "Bootstrap complete. If hooks didn’t install, run: 'make hooks.install'\n"

sync:
	$(UV) sync --all-extras --dev

# ---------------------------------------------------------------------
# Code quality pipeline (Ruff-first, then type, then security, then tests)
# ---------------------------------------------------------------------
fmt:
	$(RUFF) format .

lint:
	$(RUFF) check .

type:
	$(MYPY) --strict $(PKG_DIR)

sec:
	# Bandit is configured in pyproject.toml; no shell=True nonsense anywhere.
	$(BANDIT) -q -c $(PYPROJECT) -r $(SRC_DIR)
	# gitleaks: pre-commit style git mode; no legacy --source flags.
	$(MAKE) gitleaks.scan
	# detect-secrets: compare against the repo’s baseline.
	$(MAKE) ds.audit

test:
	$(PYTEST) -q

qa: fmt lint type sec test

all: qa

# ---------------------------------------------------------------------
# Hooks management
# ---------------------------------------------------------------------
hooks.install:
	# Install both pre-commit and pre-push. Blocking by default; bypass with:
	#   - one-time: SKIP=ruff,gitleaks $(PRECOMMIT) run --all-files
	#   - blunt-force: git commit -n   (not recommended)
	$(PRECOMMIT) install -t pre-commit -t pre-push

hooks.update:
	# Pull latest stable hooks. Then re-install to refresh the git hooks.
	$(PRECOMMIT) autoupdate
	$(PRECOMMIT) install -t pre-commit -t pre-push

hooks.clean:
	# If pre-commit goes sideways, this tends to fix it.
	rm -rf $$HOME/.cache/pre-commit || true
	$(PRECOMMIT) install -t pre-commit -t pre-push

hooks.run:
	# Run all configured hooks across the tree.
	$(PRECOMMIT) run --all-files -v

hooks.doctor:
	# Validate toolchain, hook wiring, and gitleaks semantics.
	$(UV) run $(PKG_NAME).doctor

# ---------------------------------------------------------------------
# Individual scanners
# ---------------------------------------------------------------------
gitleaks.scan:
	# Git mode; this mirrors the hook behavior. No --source. Config lives in rules/.
	$(GITLEAKS) git --pre-commit --no-banner --no-color --log-level=error --redact --config=$(GITLEAKS_TOML)

ds.audit:
	# Honor the repository baseline. If you’re adding a known-good secret sample
	# for tests, update the baseline consciously.
	$(DETECTSECRETS) scan --baseline $(DS_BASELINE) >/dev/null
	$(DETECTSECRETS) audit --baseline $(DS_BASELINE) --report --fail-on-unaudited --no-update

# ---------------------------------------------------------------------
# Fleet operations (be careful, but it’s handy)
# ---------------------------------------------------------------------
# Example:
#   make ensure.all-repos ROOT=~/git
# Will walk the tree, find repos, and install/refresh hooks locally.
ensure.all-repos:
ifndef ROOT
	$(error Set ROOT to the directory containing your git repos, e.g., ROOT=~/dev)
endif
	$(UV) run $(PKG_NAME) ensure-all-repos "$(ROOT)" --update --maxdepth 6

# ---------------------------------------------------------------------
# Legacy cleanup (for folks migrating from the old caulking)
# ---------------------------------------------------------------------
uninstall.legacy:
	# Removes legacy global hook paths, shell rc snippets, and stray files.
	# Safe by default; pass APPLY=1 to actually modify.
	@if [ -x scripts/caulking-uninstall-legacy.sh ]; then \
		if [ "$(APPLY)" = "1" ]; then \
			scripts/caulking-uninstall-legacy.sh --apply; \
		else \
			scripts/caulking-uninstall-legacy.sh; \
			printf "\nRun 'make uninstall.legacy APPLY=1' to apply changes.\n"; \
		fi \
	else \
		printf "No legacy uninstaller found at scripts/caulking-uninstall-legacy.sh\n"; \
	fi

# ---------------------------------------------------------------------
# Versions / housekeeping
# ---------------------------------------------------------------------
tools.versions:
	@echo "== Toolchain versions =="
	@$(UV) --version
	@$(PYTHON) --version
	@$(RUFF) --version
	@$(MYPY) --version
	@$(BANDIT) --version
	@$(PYTEST) --version 2>/dev/null || true
	@$(PRECOMMIT) --version
	@$(GITLEAKS) version || true
	@$(DETECTSECRETS) --version || true

clean:
	# Keep it predictable. Don’t delete things people might care about.
	rm -rf .pytest_cache .mypy_cache .ruff_cache .coverage *.egg-info dist build || true

distclean: clean
	# Nuke uv caches for a hard reset.
	$(UV) cache clean || true
