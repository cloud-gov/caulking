# Caulking — boring, predictable, and fast.
# This Makefile keeps the happy path one command away.

SHELL := /bin/bash
.DEFAULT_GOAL := help

# Tools
UV      ?= uv
PY      ?= $(UV) run python
RUFF    ?= $(UV) run ruff
MYPY    ?= $(UV) run mypy
BANDIT  ?= $(UV) run bandit
PYTEST  ?= $(UV) run pytest
BREW    ?= brew

# Pretty output helpers
GREEN  := \033[32m
RED    := \033[31m
YELLOW := \033[33m
BOLD   := \033[1m
RESET  := \033[0m

# ---------------------------------------------------------------------
# Setup
# ---------------------------------------------------------------------

.PHONY: help
help: ## Show this help.
	@awk 'BEGIN {FS = ":.*##"; printf "\n  $(BOLD)Targets$(RESET)\n"} /^[a-zA-Z0-9_\-]+:.*?##/ { printf "  $(BOLD)%-22s$(RESET) %s\n", $$1, $$2 }' $(MAKEFILE_LIST)
	@echo

.PHONY: sync
sync: ## Create/refresh the virtualenv with dev extras
	$(UV) sync --extra dev

.PHONY: bootstrap
bootstrap: ## Install global prerequisites via Homebrew (macOS)
	@command -v $(BREW) >/dev/null 2>&1 || { echo "$(RED)Homebrew not found$(RESET)"; exit 1; }
	@$(BREW) install pre-commit gitleaks || true

.PHONY: enforce
enforce: ## Enforce global pre-commit hooks for all repos on this machine
	git config --global core.hooksPath "$$HOME/.config/pre-commit"
	mkdir -p "$$HOME/.config/pre-commit"
	@printf "$(YELLOW)Global enforcement enabled at %s$(RESET)\n" "$$HOME/.config/pre-commit"

# ---------------------------------------------------------------------
# Core checks
# ---------------------------------------------------------------------

.PHONY: lint
lint: ## Ruff lint + autofix
	$(RUFF) check . --fix

.PHONY: type
type: ## mypy strict type checking
	$(MYPY) --strict .

.PHONY: sec
sec: ## Bandit security scan (src only)
	$(BANDIT) -q -c pyproject.toml -r src

.PHONY: test
test: ## Run unit tests
	$(PYTEST) -q

.PHONY: cover
cover: ## Run tests with coverage summary
	$(PYTEST) --cov=src/caulking --cov-report=term-missing

# ---------------------------------------------------------------------
# CLI convenience
# ---------------------------------------------------------------------

.PHONY: explain
explain: ## Explain what will run and why, based on config
	$(PY) -m caulking explain

.PHONY: smart-install
smart-install: ## Dry-run smart install (plan only)
	$(PY) -m caulking smart-install .

.PHONY: smart-install.apply
smart-install.apply: ## Apply smart install (requires --apply)
	$(PY) -m caulking smart-install . --apply

.PHONY: audit
audit: ## Print audit report to console (non-artifact)
	$(PY) -m caulking audit

.PHONY: audit.report
audit.report: ## Write full audit artifacts under artifacts/audit/<timestamp>/
	$(PY) -m caulking audit --format md --out artifacts/audit

# ---------------------------------------------------------------------
# Hygiene
# ---------------------------------------------------------------------

.PHONY: clean
clean: ## Remove caches/artifacts
	@rm -rf .pytest_cache .mypy_cache .ruff_cache .coverage dist build
	@find . -name '__pycache__' -type d -prune -exec rm -rf {} +


.PHONY: preflight
preflight: ## Run environment preflight checks (tools, PATH, hooksPath, config presence)
	$(PY) -m caulking preflight .
