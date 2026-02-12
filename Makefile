# =====================================================================
# FILE: Makefile
# =====================================================================

# NOTE: Keep CAULKING_VERSION human-friendly if you want,
# but consider moving SemVer to a VERSION file for release automation.
CAULKING_VERSION := 3.1.3 (2026-02-06)

MIN_GITLEAKS_VERSION := 8.18.0

.PHONY: install uninstall verify audit clean ensure-tools

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
# verify.sh now includes a safe, isolated test confirming uninstall restores
# a prior core.hooksPath value when present.
audit: ensure-tools
	@./verify.sh

clean:
	@echo "NOTE: clean no longer deletes ~/.config by default."
	@echo "If you need to reset install state:"
	@echo "  rm -rf '$${XDG_CONFIG_HOME:-$$HOME/.config}/git/hooks' '$${XDG_CONFIG_HOME:-$$HOME/.config}/gitleaks' '$${XDG_CONFIG_HOME:-$$HOME/.config}/caulking'"
	@echo "  git config --global --unset core.hooksPath || true"
	@echo "  git config --global --unset hooks.gitleaks || true"
