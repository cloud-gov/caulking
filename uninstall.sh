#!/usr/bin/env bash
set -euo pipefail

XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
HOOK_DIR="$XDG_CONFIG_HOME/git/hooks"

say() { printf "%s\n" "$*"; }

say "Removing core.hooksPath (global)..."
git config --global --unset core.hooksPath || true

say "Removing installed hooks from: $HOOK_DIR"
rm -f "$HOOK_DIR/pre-commit" "$HOOK_DIR/pre-push" "$HOOK_DIR/commit-msg" || true

say "Uninstall complete."
say "Note: global gitleaks config is left in place: $XDG_CONFIG_HOME/gitleaks/config.toml"
