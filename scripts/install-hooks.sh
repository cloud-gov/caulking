#!/usr/bin/env bash
set -euo pipefail

# Installs a user-global pre-commit hook that delegates to caulking.
# Modes:
#   advisory (default): warn if repo lacks secret scanning
#   --enforce: ensure gitleaks is present, bootstrap a minimal pre-commit config if none exists.

MODE="${1:-advisory}"  # advisory | --enforce

XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
XDG_BIN_HOME="${XDG_BIN_HOME:-$HOME/.local/bin}"
HOOKS_DIR="${HOOKS_DIR:-$HOME/.githooks}"
CAULKING_BIN="${CAULKING_BIN:-$XDG_BIN_HOME/caulking}"

if [ ! -x "$CAULKING_BIN" ]; then
  echo "caulking not found at $CAULKING_BIN — run scripts/install.sh first"
  exit 1
fi

mkdir -p "$HOOKS_DIR"
hook_path="$HOOKS_DIR/pre-commit"

if [ -f "$hook_path" ]; then
  ts="$(date +%Y%m%d-%H%M%S)"
  cp -a "$hook_path" "${hook_path}.bak.${ts}"
  echo "[caulking] Backed up existing global pre-commit -> ${hook_path}.bak.${ts}"
fi

cat > "$hook_path" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || echo "")"
if [ -z "$REPO_ROOT" ]; then
  exit 0
fi

CAULKING_BIN="${CAULKING_BIN:-$HOME/.local/bin/caulking}"
if [ ! -x "$CAULKING_BIN" ]; then
  echo "[global hook] caulking not found; skipping" >&2
  exit 0
fi

# If the repo already has a pre-commit config, prefer normal pre-commit flow.
if [ -f "$REPO_ROOT/.pre-commit-config.yaml" ]; then
  if command -v pre-commit >/dev/null 2>&1; then
    pre-commit run --hook-stage=pre-commit
    exit $?
  else
    # Fallback to caulking to avoid hard dependency on global pre-commit
    "$CAULKING_BIN" smart-install -c "$REPO_ROOT/.pre-commit-config.yaml" --no-augment
    exit $?
  fi
fi

# No config present. Hand off to caulking shim with chosen mode.
CAULKING_MODE_PLACEHOLDER
exit $?
EOF
chmod +x "$hook_path"

if [ "$MODE" = "--enforce" ]; then
  sed -i.bak 's|CAULKING_MODE_PLACEHOLDER|"$CAULKING_BIN" shim-pre-commit --enforce|' "$hook_path"
  rm -f "$hook_path.bak"
  echo "[caulking] global hook installed in ENFORCE mode at $hook_path"
else
  sed -i.bak 's|CAULKING_MODE_PLACEHOLDER|"$CAULKING_BIN" shim-pre-commit|' "$hook_path"
  rm -f "$hook_path.bak"
  echo "[caulking] global hook installed in ADVISORY mode at $hook_path"
fi

git config --global core.hooksPath "$HOOKS_DIR"
echo "[caulking] git core.hooksPath -> $HOOKS_DIR"
echo "Revert with: git config --global --unset core.hooksPath"
