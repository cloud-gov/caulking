#!/usr/bin/env bash
set -euo pipefail

# verify.sh - sanity checks for Caulking (XDG layout)

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$ROOT_DIR/scripts/pretty.sh"

die() {
  p_err "$*"
  exit 2
}

have() { command -v "$1" >/dev/null 2>&1; }

XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
HOOK_DIR="$XDG_CONFIG_HOME/git/hooks"
GITLEAKS_CFG="$XDG_CONFIG_HOME/gitleaks/config.toml"

tmpdir=""
repo=""

cleanup() {
  [[ -n "${repo:-}" && -d "${repo:-}" ]] && rm -rf "$repo" || true
  [[ -n "${tmpdir:-}" && -d "${tmpdir:-}" ]] && rm -rf "$tmpdir" || true
}
trap cleanup EXIT

print_header() {
  printf '\n%b\n' "${BOLD}== $1 ==${RESET}"
}

declare -a SUMMARY_LINES=()
add_summary() { SUMMARY_LINES+=("$1"); }

check_binaries() {
  print_header "Checking binaries"

  if ! have gitleaks; then
    die "gitleaks not found in PATH (run: make install)"
  fi

  # Optional: prek
  if have prek; then
    add_summary "prek: $(prek --version 2>/dev/null || echo 'present')"
  else
    add_summary "prek: not installed (optional)"
  fi

  gitleaks version >/dev/null 2>&1 || die "gitleaks failed to run"
  add_summary "gitleaks: $(gitleaks version 2>/dev/null | tail -n 1)"
}

check_global_git_config() {
  print_header "Checking global git configuration"

  local hookspath=""
  hookspath="$(git config --global core.hooksPath || true)"

  [[ -n "$hookspath" ]] || die "global core.hooksPath not set (expected: $HOOK_DIR). Run: make install"
  [[ "$hookspath" == "$HOOK_DIR" ]] || die "global core.hooksPath is '$hookspath' (expected: $HOOK_DIR)"

  status_line "Global hooksPath" "$hookspath" "$GREEN"
  add_summary "global core.hooksPath OK"
}

check_installed_hooks() {
  print_header "Checking installed hook scripts"

  [[ -d "$HOOK_DIR" ]] || die "hook dir missing: $HOOK_DIR"

  local h=""
  for h in pre-commit pre-push; do
    local p="$HOOK_DIR/$h"
    [[ -f "$p" ]] || die "missing hook: $p"
    [[ -x "$p" ]] || die "hook not executable: $p"
    status_line "$h" "present + executable" "$GREEN"
  done

  add_summary "hooks installed + executable"
}

check_gitleaks_config() {
  print_header "Checking gitleaks global config"

  [[ -f "$GITLEAKS_CFG" ]] || die "missing gitleaks config: $GITLEAKS_CFG"

  grep -qE '^\[extend\]' "$GITLEAKS_CFG" || die "gitleaks config does not contain [extend]"
  grep -qE '^\s*useDefault\s*=\s*true\s*$' "$GITLEAKS_CFG" || die "gitleaks config does not set useDefault = true"

  status_line "gitleaks config" "extends defaults" "$GREEN"
  add_summary "gitleaks config extends defaults"
}

git_init_test_repo() {
  tmpdir="$(mktemp -d "${TMPDIR:-/tmp}/caulking.verify.XXXXXX")"
  repo="$tmpdir/repo"
  mkdir -p "$repo"
  (cd "$repo" && git init -q .)

  (cd "$repo" && git config user.name "Caulking Verify")
  (cd "$repo" && git config user.email "verify@gsa.gov")
}

attempt_commit() {
  local msg="$1"
  (cd "$repo" && git add -A)
  (cd "$repo" && git commit -m "$msg" >/dev/null 2>&1)
}

functional_test_secret_commit_blocked() {
  print_header "Functional test: secret commit should FAIL (pre-commit blocks)"

  git_init_test_repo

  cat >"$repo/secrets.md" <<'EOF'
aws_secret_access_key = WT8ftNba7siVx5UOoGzJSyd82uNCZAC8LCllzcWp
EOF

  set +e
  attempt_commit "should fail" >/dev/null 2>&1
  local rc=$?
  set -e

  [[ "$rc" -ne 0 ]] || die "Secret commit was NOT blocked (expected non-zero exit)"

  status_line "Secret commit" "blocked (expected)" "$GREEN"
  add_summary "secret commit blocked"
}

functional_test_clean_commit_allowed() {
  print_header "Functional test: clean commit should PASS"

  rm -rf "$repo" || true
  git_init_test_repo

  cat >"$repo/ok.md" <<'EOF'
Just a plain old file.
EOF

  set +e
  attempt_commit "clean commit" >/dev/null 2>&1
  local rc=$?
  set -e

  [[ "$rc" -eq 0 ]] || die "Clean commit was blocked (expected success). Run: git commit -m test (in any repo) to see hook output."

  status_line "Clean commit" "allowed (expected)" "$GREEN"
  add_summary "clean commit allowed"
}

functional_test_uninstall_restores_previous_hookspath_isolated() {
  print_header "Functional test: uninstall restores previous hooksPath (isolated)"

  # This test MUST NOT touch the user's real global git config.
  # We isolate by setting GIT_CONFIG_GLOBAL and HOME.
  local iso
  iso="$(mktemp -d "${TMPDIR:-/tmp}/caulking.hookspath.XXXXXX")"

  local iso_home="$iso/home"
  local iso_xdg="$iso/xdg"
  local iso_gitconfig="$iso/gitconfig"
  local prev_hookspath="$iso/prev-hooks"

  mkdir -p "$iso_home" "$iso_xdg" "$prev_hookspath"
  : > "$iso_gitconfig"

  (
    export HOME="$iso_home"
    export XDG_CONFIG_HOME="$iso_xdg"
    export GIT_CONFIG_GLOBAL="$iso_gitconfig"

    # Set a "previous" hookspath that is NOT Caulking's target.
    git config --global core.hooksPath "$prev_hookspath"

    # Run install (should store previous and set to XDG hooks dir)
    "$ROOT_DIR/install.sh" >/dev/null

    local after_install
    after_install="$(git config --global --get core.hooksPath || true)"
    [[ "$after_install" == "$iso_xdg/git/hooks" ]] || die "install did not set core.hooksPath as expected (got: $after_install)"

    # Run uninstall (should restore prior value)
    "$ROOT_DIR/uninstall.sh" >/dev/null

    local after_uninstall
    after_uninstall="$(git config --global --get core.hooksPath || true)"
    [[ "$after_uninstall" == "$prev_hookspath" ]] || die "uninstall did not restore previous core.hooksPath (got: $after_uninstall)"
  )

  rm -rf "$iso" || true

  status_line "hooksPath restore" "restored previous value (isolated)" "$GREEN"
  add_summary "uninstall restores previous core.hooksPath (isolated)"
}

main() {
  print_header "Caulking verify"
  check_binaries
  check_global_git_config
  check_installed_hooks
  check_gitleaks_config
  functional_test_secret_commit_blocked
  functional_test_clean_commit_allowed
  functional_test_uninstall_restores_previous_hookspath_isolated

  printf '\n'
  {
    printf '%s\n' "All checks passed."
    printf '\n'
    printf '%s\n' "Date: $(date -u +"%Y-%m-%d %H:%M:%S UTC")"
    printf '\n'
    local l=""
    for l in "${SUMMARY_LINES[@]}"; do
      printf '%s\n' "$l"
    done
  } | kv_list | pretty_box "Caulking Audit [OK]" "$GREEN"
}

main "$@"
