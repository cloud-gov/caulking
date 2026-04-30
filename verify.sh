#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$ROOT_DIR/scripts/lib.sh"
# shellcheck source=/dev/null
source "$ROOT_DIR/scripts/pretty.sh"

on_err_trap
enable_xtrace_if_debug

# Get caulking version
CAULKING_VERSION="$(cat "$ROOT_DIR/VERSION" 2> /dev/null | head -n1 | cut -d' ' -f1 || echo 'unknown')"

die_pretty() {
  p_err "$*"
  exit 2
}

have_local() { command -v "$1" > /dev/null 2>&1; }

# Load standard XDG paths
eval "$(caulking_export_paths)"

# Generate verification ID for audit trail
# Format: caulk-YYYYMMDD-HHMMSS-<short-hash>
generate_verification_id() {
  local timestamp user host
  timestamp="$(date -u +"%Y%m%d-%H%M%S")"
  user="$(whoami)"
  host="$(hostname)"
  # Create a short hash from user+host+timestamp for uniqueness
  local hash_input="${user}:${host}:${timestamp}:${CAULKING_VERSION}"
  local short_hash
  if have_local shasum; then
    short_hash="$(printf '%s' "$hash_input" | shasum -a 256 | cut -c1-8)"
  elif have_local sha256sum; then
    short_hash="$(printf '%s' "$hash_input" | sha256sum | cut -c1-8)"
  else
    # Fallback: use simple checksum
    short_hash="$(printf '%s' "$hash_input" | cksum | cut -d' ' -f1)"
  fi
  printf 'caulk-%s-%s' "$timestamp" "$short_hash"
}

# Get platform info
get_platform_info() {
  local os arch
  os="$(uname -s)"
  arch="$(uname -m)"
  case "$os" in
    Darwin)
      local macos_ver
      macos_ver="$(sw_vers -productVersion 2> /dev/null || echo 'unknown')"
      printf 'macOS %s (%s)' "$macos_ver" "$arch"
      ;;
    Linux)
      if [[ -f /etc/os-release ]]; then
        # shellcheck disable=SC1091
        local distro
        distro="$(. /etc/os-release && echo "${NAME:-Linux} ${VERSION_ID:-}")"
        printf '%s (%s)' "$distro" "$arch"
      else
        printf 'Linux (%s)' "$arch"
      fi
      ;;
    *)
      printf '%s (%s)' "$os" "$arch"
      ;;
  esac
}

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

  if ! have_local gitleaks; then
    die_pretty "gitleaks not found in PATH (run: make install)"
  fi

  if have_local prek; then
    add_summary "prek: $(prek --version 2> /dev/null || echo 'present')"
  else
    add_summary "prek: not installed (optional)"
  fi

  gitleaks version > /dev/null 2>&1 || die_pretty "gitleaks failed to run"
  add_summary "gitleaks: $(gitleaks version 2> /dev/null | tail -n 1)"
}

check_global_git_config() {
  print_header "Checking global git configuration"

  local hookspath=""
  hookspath="$(git config --global core.hooksPath || true)"

  [[ -n "$hookspath" ]] || die_pretty "global core.hooksPath not set (expected: $HOOK_DIR). Run: make install"
  [[ "$hookspath" == "$HOOK_DIR" ]] || die_pretty "global core.hooksPath is '$hookspath' (expected: $HOOK_DIR)"

  status_line "Global hooksPath" "$hookspath" "$GREEN"
  add_summary "global core.hooksPath OK"
}

check_installed_hooks() {
  print_header "Checking installed hook scripts"

  [[ -d "$HOOK_DIR" ]] || die_pretty "hook dir missing: $HOOK_DIR"

  local h=""
  for h in pre-commit pre-push; do
    local p="$HOOK_DIR/$h"
    [[ -f "$p" ]] || die_pretty "missing hook: $p"
    [[ -x "$p" ]] || die_pretty "hook not executable: $p"
    status_line "$h" "present + executable" "$GREEN"
  done

  add_summary "hooks installed + executable"
}

check_gitleaks_config() {
  print_header "Checking gitleaks global config"

  [[ -f "$GITLEAKS_CFG" ]] || die_pretty "missing gitleaks config: $GITLEAKS_CFG"

  grep -qE '^\[extend\]' "$GITLEAKS_CFG" || die_pretty "gitleaks config does not contain [extend]"
  grep -qE '^\s*useDefault\s*=\s*true\s*$' "$GITLEAKS_CFG" || die_pretty "gitleaks config does not set useDefault = true"

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
  (cd "$repo" && git commit -m "$msg" > /dev/null 2>&1)
}

functional_test_secret_commit_blocked() {
  print_header "Functional test: secret commit should FAIL (pre-commit blocks)"

  git_init_test_repo

  cat > "$repo/secrets.md" << 'EOF'
aws_secret_access_key = WT8ftNba7siVx5UOoGzJSyd82uNCZAC8LCllzcWp
EOF

  set +e
  attempt_commit "should fail" > /dev/null 2>&1
  local rc=$?
  set -e

  [[ "$rc" -ne 0 ]] || die_pretty "Secret commit was NOT blocked (expected non-zero exit)"

  status_line "Secret commit" "blocked (expected)" "$GREEN"
  add_summary "secret commit blocked"
}

functional_test_clean_commit_allowed() {
  print_header "Functional test: clean commit should PASS"

  rm -rf "$repo" || true
  git_init_test_repo

  cat > "$repo/ok.md" << 'EOF'
Just a plain old file.
EOF

  set +e
  attempt_commit "clean commit" > /dev/null 2>&1
  local rc=$?
  set -e

  [[ "$rc" -eq 0 ]] || die_pretty "Clean commit was blocked (expected success). Run: git commit -m test (in any repo) to see hook output."

  status_line "Clean commit" "allowed (expected)" "$GREEN"
  add_summary "clean commit allowed"
}

functional_test_uninstall_restores_previous_hookspath_isolated() {
  print_header "Functional test: uninstall restores previous hooksPath (isolated)"

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

    git config --global core.hooksPath "$prev_hookspath"

    "$ROOT_DIR/install.sh" > /dev/null

    local after_install
    after_install="$(git config --global --get core.hooksPath || true)"
    [[ "$after_install" == "$iso_xdg/git/hooks" ]] || die_pretty "install did not set core.hooksPath as expected (got: $after_install)"

    "$ROOT_DIR/uninstall.sh" > /dev/null

    local after_uninstall
    after_uninstall="$(git config --global --get core.hooksPath || true)"
    [[ "$after_uninstall" == "$prev_hookspath" ]] || die_pretty "uninstall did not restore previous core.hooksPath (got: $after_uninstall)"
  )

  rm -rf "$iso" || true

  status_line "hooksPath restore" "restored previous value (isolated)" "$GREEN"
  add_summary "uninstall restores previous core.hooksPath (isolated)"
}

check_precommit_runner() {
  print_header "Checking pre-commit runner (prek / pre-commit)"

  if [[ ! -f "$ROOT_DIR/.pre-commit-config.yaml" ]]; then
    status_line "pre-commit config" "not present (skipped)" "$GRAY"
    add_summary "pre-commit runner: skipped (no config)"
    return 0
  fi

  if "$ROOT_DIR/scripts/verify-precommit-runner.sh" > /dev/null 2>&1; then
    status_line "pre-commit runner" "callable (prek/pre-commit OK)" "$GREEN"
    add_summary "pre-commit runner callable"
  else
    "$ROOT_DIR/scripts/verify-precommit-runner.sh" || die_pretty "pre-commit runner validation failed"
  fi
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
  check_precommit_runner

  # Generate verification ID for audit trail
  local verification_id
  verification_id="$(generate_verification_id)"

  printf '\n'
  {
    printf '%s\n' "All checks passed."
    printf '\n'
    printf '%s\n' "Verification ID: $verification_id"
    printf '\n'
    printf '%s\n' "User: $(whoami)"
    printf '%s\n' "Host: $(hostname)"
    printf '%s\n' "Platform: $(get_platform_info)"
    printf '%s\n' "Date: $(date -u +"%Y-%m-%dT%H:%M:%SZ")"
    printf '\n'
    printf '%s\n' "caulking: $CAULKING_VERSION"
    local l=""
    for l in "${SUMMARY_LINES[@]}"; do
      printf '%s\n' "$l"
    done
  } | kv_list | pretty_box "Caulking Audit [OK]" "$GREEN"
}

main "$@"
