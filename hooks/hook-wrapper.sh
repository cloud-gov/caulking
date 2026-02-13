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

print_false_positive_hint() {
  cat <<'EOF'
gitleaks blocked this operation.

If you think this is a false positive:
  1) Prefer fixing the pattern or adding a repo allowlist in .gitleaks.repo.toml
  2) Break-glass for a single operation:
       SKIP=gitleaks git commit -m "..."
       SKIP=gitleaks git push

(Use break-glass sparingly; it bypasses secret scanning.)
EOF
}

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

  # Helper: run gitleaks git with the right config set + optional log opts
  run_gitleaks_git() {
    # Usage: run_gitleaks_git <extra args...>
    if [[ -n "$repo_cfg" ]]; then
      gitleaks git --config "$GITLEAKS_CFG" --config "$repo_cfg" --verbose "$@"
    else
      gitleaks git --config "$GITLEAKS_CFG" --verbose "$@"
    fi
  }

  # Run gitleaks and print a short false-positive / break-glass hint on failure.
  run_gitleaks_or_hint() {
    # Usage: run_gitleaks_or_hint <extra args...>
    if ! run_gitleaks_git "$@"; then
      print_false_positive_hint
      exit 1
    fi
  }

  if [[ "$stage" == "pre-commit" ]]; then
    # Staged-only scan: fast + precise.
    run_gitleaks_or_hint --staged
  else
    # pre-push: scan ONLY what is being pushed (avoid scanning entire repo history).
    #
    # Git provides lines on stdin:
    #   <local_ref> <local_sha> <remote_ref> <remote_sha>
    #
    # We compute a rev-list range for each ref and pass it via --log-opts.
    #
    # - Normal update:    remote_sha..local_sha
    # - New branch push:  remote_sha is all zeros; scan commits reachable from local_sha
    #                    but not already in the remote-tracking refs for that remote.

    remote_name="${1:-origin}"
    remote_url="${2:-}"

    had_input=0

    # NOTE: Must read 4 fields (remote_ref is present); discard it with "_".
    while IFS=' ' read -r local_ref local_sha _ remote_sha; do
      [[ -n "${local_ref:-}" ]] || continue
      had_input=1

      # Deletions: local_sha is all zeros
      if [[ "$local_sha" =~ ^0{40}$ ]]; then
        continue
      fi

      if [[ "$remote_sha" =~ ^0{40}$ ]]; then
        # New branch / new ref on remote.
        # Scan commits reachable from local_sha that are NOT already on remote-tracking refs.
        #
        # Use git rev-list syntax in --log-opts:
        #   <local_sha> --not --remotes=<remote_name>
        #
        # This avoids invalid ranges like:
        #   0000000000..<sha>
        #
        run_gitleaks_or_hint --log-opts="$local_sha --not --remotes=$remote_name"
      else
        # Update existing ref: scan only the range being pushed.
        run_gitleaks_or_hint --log-opts="$remote_sha..$local_sha"
      fi
    done

    if [[ "$had_input" -eq 0 ]]; then
      # Extremely defensive fallback: scan commits not on the remote.
      # (Still much better than scanning full history.)
      head_sha="$(git rev-parse HEAD 2>/dev/null || true)"
      if [[ -n "$head_sha" ]]; then
        run_gitleaks_or_hint --log-opts="$head_sha --not --remotes=$remote_name"
      fi
      : "${remote_url:=}"
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
