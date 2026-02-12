#!/usr/bin/env bash
set -euo pipefail

# Caulking hook wrapper (XDG layout)
# Installed as: ~/.config/git/hooks/{pre-commit,pre-push}
#
# Responsibilities:
# - Run gitleaks with the global XDG config
# - Optionally merge a repo allowlist config (.gitleaks.repo.toml) if present
# - Respect SKIP=gitleaks if the user insists
# - Attempt to run any repo-local hook at .git/hooks/<stage> (best-effort)
#   without recursion

stage="$(basename "$0")"

say() { printf "%s\n" "$*"; }

XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
GITLEAKS_CFG="$XDG_CONFIG_HOME/gitleaks/config.toml"

# Prevent recursion if repo-local hook calls into the global hook path
export CAULKING_HOOK_ACTIVE="${CAULKING_HOOK_ACTIVE:-}"
if [[ "${CAULKING_HOOK_ACTIVE}" == "1" ]]; then
  exit 0
fi
export CAULKING_HOOK_ACTIVE="1"

# If user explicitly asked to skip gitleaks for this commit/push, allow it.
# (No prompting in a hook wrapper — prompting breaks automation.)
if [[ "${SKIP:-}" == "gitleaks" ]]; then
  say "SKIP=gitleaks set; skipping gitleaks scan."
else
  if ! command -v gitleaks >/dev/null 2>&1; then
    say "ERROR: gitleaks not found in PATH"
    exit 2
  fi

  if [[ ! -f "$GITLEAKS_CFG" ]]; then
    say "ERROR: global gitleaks config not found: $GITLEAKS_CFG"
    say "Run: make install (or ./install.sh)"
    exit 2
  fi

  # Optional repo-specific allowlist config (keeps global conservative).
  repo_root="$(git rev-parse --show-toplevel 2>/dev/null || true)"
  repo_cfg=""
  if [[ -n "$repo_root" && -f "$repo_root/.gitleaks.repo.toml" ]]; then
    repo_cfg="$repo_root/.gitleaks.repo.toml"
  fi

  # pre-commit: staged scan
  if [[ "$stage" == "pre-commit" ]]; then
    if [[ -n "$repo_cfg" ]]; then
      gitleaks git --staged --config "$GITLEAKS_CFG" --config "$repo_cfg" --verbose
    else
      gitleaks git --staged --config "$GITLEAKS_CFG" --verbose
    fi
  else
    # pre-push: scan current repo history changes relative to upstream.
    # This is intentionally conservative; if it’s too noisy, we can tune.
    if [[ -n "$repo_cfg" ]]; then
      gitleaks git --config "$GITLEAKS_CFG" --config "$repo_cfg" --verbose
    else
      gitleaks git --config "$GITLEAKS_CFG" --verbose
    fi
  fi
fi

# Run repo-local hook if present (best effort), avoiding recursion:
# - We only run .git/hooks/<stage> if core.hooksPath is set (it is)
# - We must not call ourselves again, so only run if it's a different file
git_dir="$(git rev-parse --git-dir 2>/dev/null || true)"
if [[ -n "$git_dir" ]]; then
  local_hook="$git_dir/hooks/$stage"
  if [[ -f "$local_hook" && -x "$local_hook" ]]; then
    # If the local hook is literally this wrapper, don't recurse.
    local_hook_abs="$(cd "$(dirname "$local_hook")" && pwd)/$(basename "$local_hook")"
    if [[ "$local_hook_abs" != "$0" ]]; then
      "$local_hook" "$@" || exit $?
    fi
  fi
fi

exit 0
