#!/usr/bin/env bash
# =====================================================================
# FILE: hooks/hook-wrapper.sh
# =====================================================================

set -euo pipefail

# Caulking hook wrapper (XDG layout)
# Installed as: ~/.config/git/hooks/{pre-commit,pre-push}
#
# Responsibilities:
# - Block obviously-sensitive file types/names from being committed (high-signal DLP guardrail)
# - Run gitleaks with the global XDG config
# - Optionally merge a repo allowlist config (.gitleaks.repo.toml) if present
# - Respect SKIP=gitleaks if the user insists
# - Optionally run repo-level pre-commit/pre-push suite (.pre-commit-config.yaml) via prek/pre-commit
# - Attempt to run any repo-local hook at .git/hooks/<stage> (best-effort)
#   without recursion or double-running

stage="$(basename "$0")"

# shellcheck disable=SC2329
want_debug() { [[ "${CAULKING_DEBUG:-0}" != "0" ]]; }
dbg() { want_debug && printf "CAULKING_DEBUG: %s\n" "$*" >&2 || true; }

say() { printf "%s\n" "$*"; }

# Treat SKIP as a comma-separated list (common convention).
skip_has() {
  local want="$1"
  local s="${SKIP:-}"
  [[ -z "$s" ]] && return 1
  s="${s// /}"
  case ",$s," in
    *",$want,"*) return 0 ;;
    *) return 1 ;;
  esac
}

# Error trap: only noisy when debug is enabled.
# shellcheck disable=SC2154
trap 'rc=$?; if want_debug; then dbg "failed rc=$rc stage=$stage file=${BASH_SOURCE[0]} line=$LINENO cmd=${BASH_COMMAND:-}"; fi; exit $rc' ERR

# For pre-push, git provides ref update lines on stdin.
# We must preserve stdin so repo-local hooks still work.
push_input=""
cleanup_push_input() {
  [[ -n "${push_input:-}" && -f "${push_input:-}" ]] && rm -f "$push_input" || true
}
trap cleanup_push_input EXIT

if [[ "$stage" == "pre-push" ]]; then
  push_input="$(mktemp "${TMPDIR:-/tmp}/caulking.prepush.XXXXXX")"
  cat > "$push_input" || true
fi

XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
GITLEAKS_CFG="$XDG_CONFIG_HOME/gitleaks/config.toml"

print_false_positive_hint() {
  cat << 'EOF'
gitleaks blocked this operation.

If you think this is a false positive:
  1) Prefer fixing the pattern or adding a repo allowlist in .gitleaks.repo.toml
  2) Break-glass for a single operation:
       SKIP=gitleaks git commit -m "..."
       SKIP=gitleaks git push

(Use break-glass sparingly; it bypasses secret scanning.)
EOF
}

print_forbidden_file_hint() {
  cat << 'EOF'
Caulking blocked a forbidden file from being committed.

Why:
  These file types commonly contain private keys, certificates, credentials, or secret stores.

What to do instead:
  - Put secrets in an approved secret manager and reference them at runtime.
  - If this is a legitimate test fixture, rename it to a safe extension and/or add it to an allowlist policy
    (do NOT commit real keys).

EOF
}

# -------------------------------------------------------------------
# High-signal "forbidden files" guardrail (content-agnostic)
# - Only runs for pre-commit (staged files)
# - Intentionally narrow to avoid false positives
# -------------------------------------------------------------------
enforce_forbidden_staged_files() {
  [[ "$stage" == "pre-commit" ]] || return 0

  local staged
  staged="$(git diff --cached --name-only --diff-filter=ACMR 2> /dev/null || true)"
  [[ -n "$staged" ]] || return 0

  local -a deny_patterns=(
    '\.pem$'
    '\.key$'
    '\.der$'
    '\.p12$'
    '\.pfx$'
    '\.pkcs8$'
    '\.jks$'
    '\.keystore$'
    '\.kdbx$'
    '\.agekey$'

    '(^|/)id_rsa$'
    '(^|/)id_dsa$'
    '(^|/)id_ecdsa$'
    '(^|/)id_ed25519$'
    '(^|/)ssh_host_.*_key$'
    '(^|/)ssh_host_.*_key\.pub$'

    '(^|/)\.env(\..*)?$'
    '(^|/)\.envrc$'
    '(^|/)\.netrc$'
    '(^|/)\.git-credentials$'

    '(^|/)\.aws/credentials$'
    '(^|/)\.aws/config$'
    '(^|/)\.aws-vault/keys/.*$'
    '(^|/)\.cf/config\.json$'
    '(^|/)\.flyrc$'
    '(^|/)\.docker/config\.json$'

    '(^|/)\.kube/config$'
    '(^|/)kubeconfig(\..*)?$'

    '\.tfstate$'
    '\.tfstate\.backup$'
    '(^|/)terraform\.tfstate\.d/.*$'
    '(^|/)\.terraform/.*$'
    '(^|/)\.terraformrc$'
    '(^|/)credentials\.tfrc\.json$'

    '(^|/)(shadow|passwd|group|gshadow)$'

    '(^|/)\.npmrc$'
    '(^|/)\.pypirc$'

    '(^|/)\.vault-token$'
  )

  local f pat
  while IFS= read -r f; do
    [[ -n "$f" ]] || continue
    for pat in "${deny_patterns[@]}"; do
      if [[ "$f" =~ $pat ]]; then
        say "ERROR: forbidden file staged: $f"
        print_forbidden_file_hint
        exit 1
      fi
    done
  done <<< "$staged"
}

# Prevent recursion if repo-local hook calls into the global hook path
export CAULKING_HOOK_ACTIVE="${CAULKING_HOOK_ACTIVE:-}"
if [[ "${CAULKING_HOOK_ACTIVE}" == "1" ]]; then
  exit 0
fi
export CAULKING_HOOK_ACTIVE="1"

enforce_forbidden_staged_files

if skip_has "gitleaks"; then
  say "SKIP includes gitleaks; skipping gitleaks scan."
else
  command -v gitleaks > /dev/null 2>&1 || {
    say "ERROR: gitleaks not found in PATH"
    exit 2
  }

  if [[ ! -f "$GITLEAKS_CFG" ]]; then
    say "ERROR: global gitleaks config not found: $GITLEAKS_CFG"
    say "Run: make install (or ./install.sh)"
    exit 2
  fi

  repo_root="$(git rev-parse --show-toplevel 2> /dev/null || true)"
  repo_cfg=""
  if [[ -n "$repo_root" && -f "$repo_root/.gitleaks.repo.toml" ]]; then
    repo_cfg="$repo_root/.gitleaks.repo.toml"
  fi

  run_gitleaks_git() {
    if [[ -n "$repo_cfg" ]]; then
      gitleaks git --config "$GITLEAKS_CFG" --config "$repo_cfg" --verbose "$@"
    else
      gitleaks git --config "$GITLEAKS_CFG" --verbose "$@"
    fi
  }

  run_gitleaks_or_hint() {
    if ! run_gitleaks_git "$@"; then
      print_false_positive_hint
      exit 1
    fi
  }

  if [[ "$stage" == "pre-commit" ]]; then
    run_gitleaks_or_hint --staged
  else
    # Pre-push scanning flow:
    # ========================
    # Git provides ref updates on stdin: <local_ref> <local_sha> <remote_ref> <remote_sha>
    #
    # Cases:
    # 1. local_sha is all zeros  -> Branch deletion, skip scan (nothing to scan)
    # 2. remote_sha is all zeros -> New branch, scan all commits not on any remote branch
    # 3. Both set                -> Normal push, scan commits in range remote_sha..local_sha
    # 4. No stdin (empty)        -> Fallback to scanning HEAD vs remote (force push safety net)
    #
    # The --log-opts flag passes git-log options to gitleaks for commit range selection.
    remote_name="${1:-origin}"
    remote_url="${2:-}"

    had_input=0

    while IFS=' ' read -r local_ref local_sha _ remote_sha; do
      [[ -n "${local_ref:-}" ]] || continue
      had_input=1

      if [[ "$local_sha" =~ ^0{40}$ ]]; then
        continue
      fi

      if [[ "$remote_sha" =~ ^0{40}$ ]]; then
        run_gitleaks_or_hint --log-opts="$local_sha --not --remotes=$remote_name"
      else
        run_gitleaks_or_hint --log-opts="$remote_sha..$local_sha"
      fi
    done < "${push_input:-/dev/stdin}"

    if [[ "$had_input" -eq 0 ]]; then
      head_sha="$(git rev-parse HEAD 2> /dev/null || true)"
      if [[ -n "$head_sha" ]]; then
        run_gitleaks_or_hint --log-opts="$head_sha --not --remotes=$remote_name"
      fi
      : "${remote_url:=}"
    fi
  fi
fi

export CAULKING_RAN_REPO_SUITE="${CAULKING_RAN_REPO_SUITE:-0}"

run_repo_precommit_suite() {
  local repo_root
  repo_root="$(git rev-parse --show-toplevel 2> /dev/null || true)"
  [[ -n "$repo_root" ]] || return 0
  [[ -f "$repo_root/.pre-commit-config.yaml" ]] || return 0

  if [[ "${CAULKING_SKIP_REPO_HOOKS:-}" == "1" ]]; then
    say "CAULKING_SKIP_REPO_HOOKS=1; skipping repo pre-commit suite."
    return 0
  fi

  if skip_has "pre-commit" || skip_has "prek"; then
    say "SKIP includes pre-commit/prek; skipping repo pre-commit suite."
    return 0
  fi

  if command -v prek > /dev/null 2>&1; then
    prek run --hook-stage "$stage" --show-diff-on-failure || exit $?
    export CAULKING_RAN_REPO_SUITE="1"
    return 0
  fi

  if command -v pre-commit > /dev/null 2>&1; then
    pre-commit run --hook-stage "$stage" --show-diff-on-failure || exit $?
    export CAULKING_RAN_REPO_SUITE="1"
    return 0
  fi

  say "NOTE: .pre-commit-config.yaml present, but neither prek nor pre-commit is installed."
  return 0
}

run_repo_precommit_suite

git_dir="$(git rev-parse --git-dir 2> /dev/null || true)"
if [[ -n "$git_dir" && "${CAULKING_RAN_REPO_SUITE:-0}" != "1" ]]; then
  local_hook="$git_dir/hooks/$stage"
  if [[ -f "$local_hook" && -x "$local_hook" ]]; then
    local_hook_abs="$(cd "$(dirname "$local_hook")" && pwd)/$(basename "$local_hook")"
    if [[ "$local_hook_abs" != "$0" ]]; then
      if [[ "$stage" == "pre-push" && -n "${push_input:-}" ]]; then
        "$local_hook" "$@" < "$push_input" || exit $?
      else
        "$local_hook" "$@" || exit $?
      fi
    fi
  fi
fi

exit 0
