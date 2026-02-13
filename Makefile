# =====================================================================
# FILE: Makefile
# =====================================================================

# NOTE: Keep CAULKING_VERSION human-friendly if you want,
# but consider moving SemVer to a VERSION file for release automation.
CAULKING_VERSION := $(shell cat VERSION)

MIN_GITLEAKS_VERSION := 8.18.0

.DEFAULT_GOAL := help

.PHONY: help install uninstall verify audit clean ensure-tools

help:
	@echo "Caulking ($(CAULKING_VERSION))"
	@echo ""
	@echo "Usage:"
	@echo "  make <target>"
	@echo ""
	@echo "Targets:"
	@echo "  help         Show this help"
	@echo "  ensure-tools Ensure required tools are installed (gitleaks required; prek optional)"
	@echo "  install      Install global hooks + gitleaks config (XDG layout)"
	@echo "  verify       Verify install + run functional tests"
	@echo "  audit        Alias for verify (intentionally boring)"
	@echo "  uninstall    Remove installed hooks and restore prior core.hooksPath (if recorded)"
	@echo "  clean        Print manual reset instructions (does not delete ~/.config)"
	@echo ""
	@echo "Notes:"
	@echo "  - Hooks install to:  $${XDG_CONFIG_HOME:-$$HOME/.config}/git/hooks"
	@echo "  - gitleaks config:   $${XDG_CONFIG_HOME:-$$HOME/.config}/gitleaks/config.toml"
	@echo ""

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

# Audit is intentionally boring: prove the enforcement works.
# verify.sh includes a safe, isolated test confirming uninstall restores
# a prior core.hooksPath value when present.
audit: ensure-tools
	@./verify.sh

clean:
	@echo "NOTE: clean no longer deletes ~/.config by default."
	@echo "If you need to reset install state:"
	@echo "  rm -rf '$${XDG_CONFIG_HOME:-$$HOME/.config}/git/hooks' '$${XDG_CONFIG_HOME:-$$HOME/.config}/gitleaks' '$${XDG_CONFIG_HOME:-$$HOME/.config}/caulking'"
	@echo "  git config --global --unset core.hooksPath || true"
	@echo "  git config --global --unset hooks.gitleaks || true"
