#!/usr/bin/env bash
set -euo pipefail

# Simple, predictable bootstrapper for clone-and-go installs.
# macOS: uses Homebrew for gitleaks + pre-commit
# Linux: installs pre-commit + detect-secrets (fallback); gitleaks optional
# Then ensures ~/.local/bin is on PATH by appending to rc files (with backups).
# Finally, configures a local venv and editable install so `python -m caulking` works.

here="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

need() { command -v "$1" >/dev/null 2>&1; }

os="$(uname -s | tr '[:upper:]' '[:lower:]')"

# ------------------------------------------------------------------------------
# 1) Tooling
# ------------------------------------------------------------------------------
if [[ "$os" == "darwin" ]]; then
  if ! need brew; then
    echo "Homebrew is required on macOS. Install from https://brew.sh"
    exit 1
  fi
  brew list --versions pre-commit >/dev/null 2>&1 || brew install pre-commit
  brew list --versions gitleaks   >/dev/null 2>&1 || brew install gitleaks
else
  need python3 || { echo "python3 required"; exit 1; }
  need pip3    || { echo "pip3 required"; exit 1; }
  pip3 install --user pre-commit detect-secrets >/dev/null
  if ! need gitleaks; then
    echo "NOTICE: gitleaks not found; audit will fallback to detect-secrets."
  fi
fi

# ------------------------------------------------------------------------------
# 2) Ensure ~/.local/bin on PATH (with explicit backups and console output)
# ------------------------------------------------------------------------------
XDG_BIN_HOME="${XDG_BIN_HOME:-$HOME/.local/bin}"
mkdir -p "$XDG_BIN_HOME"

backup_ts="$(date +%Y%m%d-%H%M%S)"
backup_dir="$HOME/.caulking-install-backup/$backup_ts"
mkdir -p "$backup_dir"

rc_files=(
  "$HOME/.zshrc"
  "$HOME/.bashrc"
  "$HOME/.bash_profile"
  "$HOME/.profile"
)

add_path_line='export PATH="$HOME/.local/bin:$PATH"'
added_any=0

ensure_path_in_rc() {
  local rc="$1"
  [[ -f "$rc" ]] || return 0
  if grep -qE '(^|\s)export PATH="?\$HOME/.local/bin' "$rc"; then
    # Already present; nothing to do.
    return 0
  fi
  cp -a "$rc" "$backup_dir/$(basename "$rc")"
  echo "[caulking] Backed up $(basename "$rc") -> $backup_dir/$(basename "$rc")"
  {
    echo ""
    echo "# Added by caulking install on $backup_ts"
    echo "$add_path_line"
  } >> "$rc"
  echo "[caulking] Appended PATH update to $rc"
  added_any=1
}

# Only append when actually needed.
case ":$PATH:" in
  *":$HOME/.local/bin:"*) ;;
  *) for rc in "${rc_files[@]}"; do ensure_path_in_rc "$rc"; done ;;
esac

if [[ $added_any -eq 1 ]]; then
  echo "[caulking] Note: open a new shell or 'source' your rc file(s) to pick up PATH changes."
else
  echo "[caulking] PATH already includes $HOME/.local/bin — no rc files modified."
fi

# ------------------------------------------------------------------------------
# 3) Local venv + editable install
# ------------------------------------------------------------------------------
if [[ ! -d "$here/.venv" ]]; then
  python3 -m venv "$here/.venv"
  "$here/.venv/bin/python" -m pip install --upgrade pip
fi
"$here/.venv/bin/pip" install -e "$here"

echo "OK: prerequisites installed."
echo "Try:  make smart-install     # enhance current repo's .pre-commit-config.yaml"
echo "     make audit              # quick local audit"
echo "     make audit.report       # write md/json artifacts under artifacts/audit/"
