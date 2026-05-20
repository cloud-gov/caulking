# =====================================================================
# FILE: Makefile
# =====================================================================

CAULKING_VERSION := $(shell cat VERSION)
MIN_GITLEAKS_VERSION := 8.21.0

.DEFAULT_GOAL := help

.PHONY: help install uninstall verify audit clean ensure-tools test lint status \
        docker-test docker-full docker-shell docker-debian docker-alpine \
        docker-ci docker-fresh docker-upgrade docker-all

help:
	@echo "Caulking ($(CAULKING_VERSION))"
	@echo ""
	@echo "Usage:"
	@echo "  make <target>"
	@echo ""
	@echo "Targets:"
	@echo "  help          Show this help"
	@echo "  ensure-tools  Ensure required tools are installed (gitleaks required; prek optional)"
	@echo "  install       Install global hooks + gitleaks config (XDG layout)"
	@echo "  status        Quick health check (hooks installed? gitleaks working?)"
	@echo "  verify        Verify install + run functional tests"
	@echo "  audit         Alias for verify (intentionally boring)"
	@echo "  uninstall     Remove installed hooks and restore prior core.hooksPath (if recorded)"
	@echo "  lint          Run repo lint/format hooks over all files (prek/pre-commit)"
	@echo "  test          Run repo tests (fast bash tests)"
	@echo "  clean         Print manual reset instructions (does not delete ~/.config)"
	@echo ""
	@echo "Docker (local Linux testing):"
	@echo "  docker-test    Run bash tests in Ubuntu container (fast)"
	@echo "  docker-full    Run full install + verify + test (Ubuntu)"
	@echo "  docker-shell   Interactive shell in Ubuntu container"
	@echo ""
	@echo "Docker (multi-distro and CI simulation):"
	@echo "  docker-debian  Test on Debian 12"
	@echo "  docker-alpine  Test on Alpine Linux (musl libc)"
	@echo "  docker-ci      Simulate GitHub Actions CI environment"
	@echo "  docker-fresh   Test fresh install (no gitleaks pre-installed)"
	@echo "  docker-upgrade Test upgrade from previous version"
	@echo "  docker-all     Run ALL distro tests (comprehensive)"
	@echo ""
	@echo "Notes:"
	@echo "  - Hooks install to:  $${XDG_CONFIG_HOME:-$$HOME/.config}/git/hooks"
	@echo "  - gitleaks config:   $${XDG_CONFIG_HOME:-$$HOME/.config}/gitleaks/config.toml"
	@echo ""
	@echo "macOS Testing:"
	@echo "  - Docker cannot run macOS containers (Apple licensing)"
	@echo "  - Use native 'make test' for macOS testing"
	@echo "  - CI uses GitHub Actions macos-latest runner"
	@echo ""

test:
	@./tests/run.sh

lint:
	@./scripts/lint.sh

ensure-tools:
	@MIN_GITLEAKS_VERSION="$(MIN_GITLEAKS_VERSION)" ./scripts/ensure-tools.sh

install: ensure-tools
	@echo "== Installing (XDG layout) =="
	@./install.sh
	@echo ""
	@echo "Next: make verify"

uninstall:
	@echo "== Uninstalling (XDG layout) =="
	@./uninstall.sh

verify:
	@./verify.sh

audit: ensure-tools
	@./verify.sh

status:
	@./scripts/status.sh

clean:
	@echo "NOTE: clean no longer deletes ~/.config by default."
	@echo "If you need to reset install state:"
	@echo "  rm -rf '$${XDG_CONFIG_HOME:-$$HOME/.config}/git/hooks' '$${XDG_CONFIG_HOME:-$$HOME/.config}/gitleaks' '$${XDG_CONFIG_HOME:-$$HOME/.config}/caulking'"
	@echo "  git config --global --unset core.hooksPath || true"
	@echo "  git config --global --unset hooks.gitleaks || true"

# -----------------------------------------------------------------------------
# Docker targets for local Linux testing
# -----------------------------------------------------------------------------
docker-test:
	@docker compose run --rm test

docker-full:
	@docker compose run --rm full

docker-shell:
	@docker compose run --rm shell

# -----------------------------------------------------------------------------
# Multi-distro and CI simulation
# -----------------------------------------------------------------------------
docker-debian:
	@docker compose run --rm debian

docker-alpine:
	@docker compose run --rm alpine

docker-ci:
	@docker compose run --rm ci

docker-fresh:
	@docker compose run --rm fresh-install

docker-upgrade:
	@docker compose run --rm upgrade

# Run all distro tests (comprehensive pre-release check)
docker-all:
	@echo "=== Running all Docker tests ==="
	@echo ""
	@echo "--- Ubuntu (default) ---"
	@docker compose run --rm full
	@echo ""
	@echo "--- Debian 12 ---"
	@docker compose run --rm debian
	@echo ""
	@echo "--- Alpine Linux ---"
	@docker compose run --rm alpine
	@echo ""
	@echo "--- CI Simulation ---"
	@docker compose run --rm ci
	@echo ""
	@echo "--- Fresh Install (error handling) ---"
	@docker compose run --rm fresh-install
	@echo ""
	@echo "--- Upgrade Test ---"
	@docker compose run --rm upgrade
	@echo ""
	@echo "=== All Docker tests PASSED ==="
