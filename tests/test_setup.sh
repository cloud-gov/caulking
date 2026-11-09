#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SETUP_BASH="$BASH"
if ! "$SETUP_BASH" -c '((BASH_VERSINFO[0] >= 4))'; then
  for candidate in /opt/homebrew/opt/bash/bin/bash /usr/local/opt/bash/bin/bash; do
    if [[ -x "$candidate" ]] && "$candidate" -c '((BASH_VERSINFO[0] >= 4))'; then
      SETUP_BASH="$candidate"
      break
    fi
  done
fi
if ! "$SETUP_BASH" -c '((BASH_VERSINFO[0] >= 4))'; then
  printf '%s\n' 'SKIP: setup tests require Bash >=4'
  exit 0
fi

TMP="$(mktemp -d "${TMPDIR:-/tmp}/caulking.setup.XXXXXX")"
trap 'chmod -R u+w "$TMP"; rm -rf "$TMP"' EXIT
export HOME="$TMP/home" XDG_CONFIG_HOME="$TMP/xdg"
export GIT_CONFIG_GLOBAL="$HOME/.gitconfig" GIT_CONFIG_NOSYSTEM=1
unset GIT_CONFIG_COUNT GIT_CONFIG_PARAMETERS GIT_DIR GIT_WORK_TREE GIT_COMMON_DIR
unset BASH_ENV ENV
mkdir -p "$HOME" "$TMP/bin" "$TMP/app/scripts" "$TMP/app/hooks"
cp "$ROOT/caulking.sh" "$ROOT/install.sh" "$TMP/app/"
cp "$ROOT/scripts/lib.sh" "$ROOT/scripts/toolchain.sh" "$TMP/app/scripts/"
cp "$ROOT/hooks/hook-wrapper.sh" "$TMP/app/hooks/"
# A package tree must never be modified by setup, including its file modes.
chmod -R a-w "$TMP/app"
source_before="$(
  ls -lR "$TMP/app"
  cksum "$TMP/app/"*.sh "$TMP/app/scripts/lib.sh" "$TMP/app/hooks/hook-wrapper.sh"
)"

for cmd in git install mkdir cp grep date dirname cat rm chmod; do
  ln -s "$(command -v "$cmd")" "$TMP/bin/$cmd"
done
ln -s "$SETUP_BASH" "$TMP/bin/bash"
cat > "$TMP/bin/gitleaks" << 'SH'
#!/bin/sh
[ "$1" = version ] || exit 90
printf '%s\n' "${FAKE_GITLEAKS_VERSION:-8.21.0}"
exit "${FAKE_GITLEAKS_EXIT:-0}"
SH
cat > "$TMP/bin/prek" << 'SH'
#!/bin/sh
[ "$1" = --version ] || exit 90
printf '%s\n' 'prek 0.3.0'
exit "${FAKE_RUNNER_EXIT:-0}"
SH
cp "$TMP/bin/prek" "$TMP/bin/pre-commit"
for cmd in brew pip pipx uv; do
  cat > "$TMP/bin/$cmd" << 'SH'
#!/bin/sh
printf '%s\n' "$0 $*" >> "$HOME/mutation"
exit 99
SH
done
chmod +x "$TMP/bin/gitleaks" "$TMP/bin/prek" "$TMP/bin/pre-commit" \
  "$TMP/bin/brew" "$TMP/bin/pip" "$TMP/bin/pipx" "$TMP/bin/uv"
rm "$TMP/bin/pre-commit"
git config --global user.name 'preserved user'
git config --global core.hooksPath '/previous/hooks'
git config --global hooks.gitleaks true
git_before="$(cksum "$GIT_CONFIG_GLOBAL")"

run_setup() {
  PATH="$TMP/bin" "$SETUP_BASH" "$TMP/app/caulking.sh" setup "$@"
}

expect_failure() {
  local expected="$1" rc=0
  shift
  run_setup "$@" > "$TMP/output" 2>&1 || rc=$?
  [[ "$rc" -eq 2 ]] || {
    cat "$TMP/output"
    printf 'Expected exit 2, got %s\n' "$rc"
    exit 1
  }
  grep -q "$expected" "$TMP/output"
  [[ ! -e "$XDG_CONFIG_HOME" && ! -e "$HOME/mutation" ]]
  [[ "$(cksum "$GIT_CONFIG_GLOBAL")" == "$git_before" ]]
}

expect_failure Usage --unknown
expect_failure Usage --no-install extra
expect_failure Usage --no-install --no-install
chmod u+w "$TMP/app/scripts"
mv "$TMP/app/scripts/toolchain.sh" "$TMP/toolchain.sh"
expect_failure 'Missing readable toolchain helper' --no-install
mv "$TMP/toolchain.sh" "$TMP/app/scripts/toolchain.sh"
chmod a-w "$TMP/app/scripts"
mv "$TMP/bin/gitleaks" "$TMP/gitleaks"
expect_failure 'Missing required command: gitleaks' --no-install
mv "$TMP/gitleaks" "$TMP/bin/gitleaks"
export FAKE_GITLEAKS_VERSION=8.20.9
expect_failure 'gitleaks >=8.21.0 required' --no-install
export FAKE_GITLEAKS_VERSION=nonsense
expect_failure 'Could not parse gitleaks version' --no-install
export FAKE_GITLEAKS_VERSION=8.21.0 FAKE_GITLEAKS_EXIT=1
expect_failure 'gitleaks failed to run' --no-install
unset FAKE_GITLEAKS_EXIT
mv "$TMP/bin/prek" "$TMP/prek"
expect_failure 'Missing required hook runner' --no-install
mv "$TMP/prek" "$TMP/bin/prek"
export FAKE_RUNNER_EXIT=1
expect_failure 'prek failed to run' --no-install
unset FAKE_RUNNER_EXIT
mv "$TMP/bin/git" "$TMP/git"
expect_failure 'Missing required command: git' --no-install
mv "$TMP/git" "$TMP/bin/git"

if [[ -x /bin/bash ]] && ! /bin/bash -c '((BASH_VERSINFO[0] >= 4))'; then
  rc=0
  PATH="$TMP/bin" /bin/bash "$TMP/app/caulking.sh" setup --no-install > "$TMP/output" 2>&1 || rc=$?
  [[ "$rc" -eq 2 && ! -e "$XDG_CONFIG_HOME" ]]
  grep -q 'requires Bash >=4' "$TMP/output"
fi

run_setup --no-install
[[ -x "$XDG_CONFIG_HOME/git/hooks/pre-commit" && -x "$XDG_CONFIG_HOME/git/hooks/pre-push" ]]
cmp "$TMP/app/hooks/hook-wrapper.sh" "$XDG_CONFIG_HOME/git/hooks/.caulking-wrapper.sh"
grep -q '^#!/bin/sh$' "$XDG_CONFIG_HOME/git/hooks/pre-commit"
[[ "$(git config --global --get core.hooksPath)" == "$XDG_CONFIG_HOME/git/hooks" ]]
[[ "$(git config --global --get user.name)" == 'preserved user' ]]
[[ "$(git config --global --get hooks.gitleaks)" == true ]]
[[ "$(cat "$XDG_CONFIG_HOME/caulking/previous_hookspath")" == /previous/hooks ]]
grep -q 'useDefault = true' "$XDG_CONFIG_HOME/gitleaks/config.toml"

# Explicit setup preserves user configuration even if it does not extend defaults.
printf '%s\n' 'title = "custom config"' > "$XDG_CONFIG_HOME/gitleaks/config.toml"
printf '%s\n' 'existing legacy hook' > "$XDG_CONFIG_HOME/git/hooks/commit-msg"
config_before="$(cksum "$XDG_CONFIG_HOME/gitleaks/config.toml")"
export FAKE_GITLEAKS_VERSION=v8.22.0
run_setup --no-install
[[ "$(cksum "$XDG_CONFIG_HOME/gitleaks/config.toml")" == "$config_before" ]]
[[ -f "$XDG_CONFIG_HOME/git/hooks/commit-msg" ]]
[[ "$(cat "$XDG_CONFIG_HOME/caulking/previous_hookspath")" == /previous/hooks ]]

# pre-commit alone is a valid fallback, including non-Homebrew legacy installs.
mv "$TMP/bin/prek" "$TMP/prek"
cp "$TMP/prek" "$TMP/bin/pre-commit"
run_setup --no-install
PATH="$TMP/bin" "$SETUP_BASH" "$TMP/app/install.sh"
rm "$TMP/bin/pre-commit"
mv "$TMP/prek" "$TMP/bin/prek"
PATH="$TMP/bin" "$SETUP_BASH" "$TMP/app/install.sh"
[[ ! -e "$HOME/mutation" ]]
[[ "$(
  ls -lR "$TMP/app"
  cksum "$TMP/app/"*.sh "$TMP/app/scripts/lib.sh" "$TMP/app/hooks/hook-wrapper.sh"
)" == "$source_before" ]]

if command -v ruby > /dev/null 2>&1; then
  ruby -c "$ROOT/packaging/caulking.rb.in"
else
  printf '%s\n' 'SKIP: Ruby unavailable for formula syntax check'
fi
printf '%s\n' 'PASS: setup preflights, isolated config, read-only package, fallback, and formula syntax'
