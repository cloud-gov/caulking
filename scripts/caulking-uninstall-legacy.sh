#!/usr/bin/env bash
# Uninstall legacy Caulking setup (global hooksPath, git template dirs, rc shims).
# macOS/Linux safe. Idempotent. Creates backups before changes.
# Usage:
#   bash scripts/caulking-uninstall-legacy.sh            # dry-run
#   bash scripts/caulking-uninstall-legacy.sh --apply    # apply changes
#   bash scripts/caulking-uninstall-legacy.sh --apply --repos-dir "$HOME/git"
#   bash scripts/caulking-uninstall-legacy.sh --apply --force-system

set -euo pipefail

# ------------------------------ options ---------------------------------------
DRY_RUN=1
REPOS_DIR=""
FORCE_SYSTEM=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --apply)
      DRY_RUN=0; shift
      ;;
    --repos-dir)
      REPOS_DIR="${2:-}"; shift 2
      ;;
    --force-system)
      FORCE_SYSTEM=1; shift
      ;;
    -h|--help)
      cat <<'EOF'
Uninstall legacy Caulking setup.

Options:
  --apply           Apply changes (default is dry-run).
  --repos-dir PATH  Recursively scan for git repos and unset local hooksPath
                    if it points to legacy hooks.
  --force-system    Attempt to clear system-level git config (needs sudo).
EOF
      exit 0
      ;;
    *)
      printf 'Unknown option: %s\n' "$1" >&2
      exit 2
      ;;
  esac
done

say()  { printf '%s\n' "$*"; }
run()  { if [[ $DRY_RUN -eq 1 ]]; then say "DRY: $*"; else eval "$*"; fi }
exists() { command -v "$1" >/dev/null 2>&1; }

ts="$(date +"%Y%m%d-%H%M%S")"
backup_root="${HOME}/.caulking-uninstall-backup/${ts}"
mkdir -p "${backup_root}"

# --------------------------- legacy candidates --------------------------------
LEGACY_HOOK_PATHS=(
  "${HOME}/.git-support/hooks"
  "${HOME}/.githooks"
  "${HOME}/.config/git/hooks"
)
LEGACY_TEMPLATE_DIRS=(
  "${HOME}/.git-support/template"
  "${HOME}/.git-template"
)
LEGACY_DIRS=(
  "${HOME}/.git-support"
  "${HOME}/.caulking"
  "${HOME}/.gitleaks"
)

# Lines containing any of these patterns in rc files will be removed.
RC_PATTERNS=(
  "git-support"
  "caulking"
  "gitleaks[[:space:]]+protect"
  "core\.hooksPath"
  "init\.templateDir"
)

RC_FILES=(
  "${HOME}/.zshrc"
  "${HOME}/.bashrc"
  "${HOME}/.bash_profile"
  "${HOME}/.profile"
  "${HOME}/.config/fish/config.fish"
)

backup_file() {
  local f="$1"
  [[ -e "$f" || -L "$f" ]] || return 0
  local rel="${f/#$HOME\//}"
  local dest="${backup_root}/${rel}"
  run "mkdir -p \"$(dirname "$dest")\""
  run "cp -a \"$f\" \"$dest\""
  say "Backed up: $f -> $dest"
}

remove_dir() {
  local d="$1"
  if [[ -d "$d" || -L "$d" ]]; then
    backup_file "$d"
    run "rm -rf \"$d\""
    say "Removed directory: $d"
  fi
}

# --------------------------- git config cleanup -------------------------------
cleanup_git_config() {
  say "== Git config cleanup =="

  local global_hooks
  global_hooks="$(git config --global core.hooksPath || true)"
  if [[ -n "${global_hooks}" ]]; then
    for p in "${LEGACY_HOOK_PATHS[@]}"; do
      if [[ "${global_hooks}" == "${p}" ]]; then
        say "Found global core.hooksPath -> ${global_hooks} ; unsetting"
        run "git config --global --unset core.hooksPath"
        break
      fi
    done
  else
    say "No global core.hooksPath set."
  fi

  local global_tmpl
  global_tmpl="$(git config --global init.templateDir || true)"
  if [[ -n "${global_tmpl}" ]]; then
    for t in "${LEGACY_TEMPLATE_DIRS[@]}"; do
      if [[ "${global_tmpl}" == "${t}" ]]; then
        say "Found global init.templateDir -> ${global_tmpl} ; unsetting"
        run "git config --global --unset init.templateDir"
        break
      fi
    done
  else
    say "No global init.templateDir set."
  fi

  if [[ $FORCE_SYSTEM -eq 1 ]]; then
    if exists sudo; then
      local sys_hooks
      sys_hooks="$(git config --system core.hooksPath || true)"
      for p in "${LEGACY_HOOK_PATHS[@]}"; do
        if [[ "${sys_hooks:-}" == "${p}" ]]; then
          say "Found system core.hooksPath -> ${sys_hooks} ; unsetting (sudo)"
          run "sudo git config --system --unset core.hooksPath"
          break
        fi
      done
      local sys_tmpl
      sys_tmpl="$(git config --system init.templateDir || true)"
      for t in "${LEGACY_TEMPLATE_DIRS[@]}"; do
        if [[ "${sys_tmpl:-}" == "${t}" ]]; then
          say "Found system init.templateDir -> ${sys_tmpl} ; unsetting (sudo)"
          run "sudo git config --system --unset init.templateDir"
          break
        fi
      done
    else
      say "sudo not available; skipping --force-system operations."
    fi
  fi
}

# ----------------------------- rc file cleanup --------------------------------
build_rc_regex() {
  local IFS='|'
  printf '(%s)' "${RC_PATTERNS[*]}"
}

cleanup_rc_files() {
  say "== Shell rc cleanup =="
  local regex
  regex="$(build_rc_regex)"

  for rc in "${RC_FILES[@]}"; do
    [[ -f "$rc" ]] || continue
    if grep -E -q "${regex}" "$rc"; then
      backup_file "$rc"
      if [[ $DRY_RUN -eq 1 ]]; then
        say "Would remove legacy lines from: $rc"
      else
        # portable: BSD/GNU sed
        sed -E "/${regex}/d" "$rc" > "${rc}.tmp"
        mv "${rc}.tmp" "$rc"
        say "Cleaned: $rc"
      fi
    fi
  done
}

# ----------------------------- repo scan (opt) --------------------------------
unset_local_hooks_in_repo() {
  local repo="$1"
  local local_hooks
  local_hooks="$(git -C "$repo" config core.hooksPath || true)"
  if [[ -n "${local_hooks}" ]]; then
    for p in "${LEGACY_HOOK_PATHS[@]}"; do
      if [[ "${local_hooks}" == "${p}" ]]; then
        say "Repo: $repo has local core.hooksPath -> ${local_hooks} ; unsetting"
        run "git -C \"$repo\" config --unset core.hooksPath"
        return
      fi
    done
  fi
}

repo_scan() {
  [[ -n "$REPOS_DIR" ]] || return 0
  say "== Scanning repos under: $REPOS_DIR =="
  if [[ ! -d "$REPOS_DIR" ]]; then
    say "Repos dir does not exist: $REPOS_DIR"
    return 0
  fi
  while IFS= read -r -d '' d; do
    unset_local_hooks_in_repo "$d"
  done < <(find "$REPOS_DIR" -type d -name ".git" -prune -print0 | xargs -0 -n1 dirname -z)
}

# ------------------------------ main flow -------------------------------------
say "Caulking legacy uninstaller (dry-run=$DRY_RUN)"
say "Backup dir: ${backup_root}"
cleanup_git_config
cleanup_rc_files

say "== Removing legacy directories =="
for d in "${LEGACY_DIRS[@]}"; do
  remove_dir "$d"
done

repo_scan

say ""
if [[ $DRY_RUN -eq 1 ]]; then
  say "Dry-run complete. To apply, re-run with:  bash scripts/caulking-uninstall-legacy.sh --apply"
  say "Backups (if applied) would be stored under: ${backup_root}"
else
  say "Applied cleanup. Backups stored under: ${backup_root}"
  say ""
  say "Next steps (per-repo):"
  say "  1) uv sync --all-extras --dev"
  say "  2) uv run pre-commit install"
  say "  3) uv run caulking install"
  say "  4) uv run caulking scan"
fi
