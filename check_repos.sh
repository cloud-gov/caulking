#!/usr/bin/env bash
set -euo pipefail

MAXDEPTH=5
USER_DOMAIN=gsa.gov

XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
EXPECTED_HOOKS_PATH="${XDG_CONFIG_HOME}/git/hooks"

fail() {
  echo "$@" >&2
  echo "Usage: $0 root_dir (check_hooks_path | check_hooks_gitleaks | check_user_email)" >&2
  exit 2
}

[ $# = 2 ] || fail "need two args"
if [ ! -d "$1" ]; then
  fail "first argument must be a directory"
else
  root=$1
fi

case $2 in
  check_hooks_gitleaks | check_hooks_path | check_user_email)
    option=$2
    ;;
  *) fail "invalid second argument" ;;
esac

exit_status=0

check_hooks_gitleaks() {
  local hooks_gitleaks
  hooks_gitleaks="$(cd "$gitrepo" && git config --bool hooks.gitleaks || true)"
  [[ "$hooks_gitleaks" == "true" ]]
}

check_hooks_path() {
  # Ensure repos are not overriding the hookspath.
  # We care about the effective local value (not the origin), because local overrides are the issue.
  local hooks_path
  hooks_path="$(cd "$gitrepo" && git config --get core.hooksPath || true)"
  if [[ -n "$hooks_path" ]]; then
    return 1
  fi

  # Ensure the global hookspath points to our expected XDG location.
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

# read gitrepo list from `find` using process substitution so exit_status isn't in a subshell
while read -r gitrepo; do
  # find returns .git directories; we want repo root
  gitrepo="$(dirname "$gitrepo")"

  if ! eval "$option"; then
    echo "FAIL $option for repository: $gitrepo" >&2
    exit_status=1
  fi
done <<< "$(find "$root" -name '.git' -type d -maxdepth "$MAXDEPTH" 2> /dev/null)"

exit "$exit_status"
