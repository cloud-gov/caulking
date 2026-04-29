#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$ROOT_DIR/scripts/lib.sh"

on_err_trap
enable_xtrace_if_debug

MAXDEPTH=5
USER_DOMAIN=gsa.gov

# Load standard XDG paths
eval "$(caulking_export_paths)"
EXPECTED_HOOKS_PATH="$HOOK_DIR"

usage() {
  err "Usage: $0 root_dir (check_hooks_path | check_hooks_gitleaks | check_user_email)"
  exit 2
}

[[ $# -eq 2 ]] || usage
root="$1"
option="$2"

[[ -d "$root" ]] || die "first argument must be a directory"

case "$option" in
  check_hooks_gitleaks | check_hooks_path | check_user_email) ;;
  *) die "invalid second argument: $option" ;;
esac

need_cmd git
need_cmd find

exit_status=0

check_hooks_gitleaks() {
  local hooks_gitleaks
  hooks_gitleaks="$(cd "$gitrepo" && git config --bool hooks.gitleaks || true)"
  [[ "$hooks_gitleaks" == "true" ]]
}

check_hooks_path() {
  local hooks_path
  hooks_path="$(cd "$gitrepo" && git config --get core.hooksPath || true)"
  if [[ -n "$hooks_path" ]]; then
    return 1
  fi

  local global_hooks_path
  global_hooks_path="$(git config --global --get core.hooksPath || true)"
  [[ "$global_hooks_path" == "$EXPECTED_HOOKS_PATH" ]]
}

check_user_email() {
  local user_email user_domain
  user_email="$(cd "$gitrepo" && git config --get user.email || true)"
  user_domain="$(printf "%s" "$user_email" | awk -F@ '{print $2}')"
  [[ "$user_domain" == "$USER_DOMAIN" ]]
}

# Use NUL separation to handle weird paths.
while IFS= read -r -d '' gitdir; do
  gitrepo="$(dirname "$gitdir")"

  if ! "$option"; then
    err "FAIL $option for repository: $gitrepo"
    exit_status=1
  else
    debug "OK $option for repository: $gitrepo"
  fi
done < <(find "$root" -maxdepth "$MAXDEPTH" -name '.git' -type d -print0 2> /dev/null)

exit "$exit_status"
