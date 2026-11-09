#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if ! command -v ruby > /dev/null 2>&1; then
  printf '%s\n' 'SKIP: Ruby required for formula runtime fixture'
  exit 0
fi
RUNTIME_BASH="$BASH"
if ! "$RUNTIME_BASH" -c '((BASH_VERSINFO[0] >= 4))'; then
  for candidate in /opt/homebrew/opt/bash/bin/bash /usr/local/opt/bash/bin/bash; do
    if [[ -x "$candidate" ]] && "$candidate" -c '((BASH_VERSINFO[0] >= 4))'; then
      RUNTIME_BASH="$candidate"
      break
    fi
  done
fi
if ! "$RUNTIME_BASH" -c '((BASH_VERSINFO[0] >= 4))'; then
  printf '%s\n' 'SKIP: Bash >=4 required for package runtime fixture'
  exit 0
fi
TMP="$(mktemp -d "${TMPDIR:-/tmp}/caulking.package.XXXXXX")"
trap 'chmod -R u+w "$TMP"; rm -rf "$TMP"' EXIT
export FIXTURE_PREFIX="$TMP/homebrew space's"
export HOME="$TMP/home" XDG_CONFIG_HOME="$TMP/config space's"
export GIT_CONFIG_GLOBAL="$HOME/.gitconfig" GIT_CONFIG_NOSYSTEM=1
unset GIT_CONFIG_COUNT GIT_CONFIG_PARAMETERS GIT_DIR GIT_WORK_TREE GIT_COMMON_DIR BASH_ENV ENV
mkdir -p "$HOME" "$FIXTURE_PREFIX/opt" "$TMP/hostile" "$TMP/repo"
for tool in bash git gitleaks prek; do
  mkdir -p "$FIXTURE_PREFIX/opt/$tool/bin"
done
ln -s "$RUNTIME_BASH" "$FIXTURE_PREFIX/opt/bash/bin/bash"
ln -s "$(command -v git)" "$FIXTURE_PREFIX/opt/git/bin/git"
cat > "$FIXTURE_PREFIX/opt/gitleaks/bin/gitleaks" << 'SH'
#!/bin/sh
if [ "$1" = version ]; then printf '8.21.0\n'; exit 0; fi
printf '%s\n' "$@" >> "$HOME/gitleaks-args"
exit "${FAKE_SCAN_EXIT:-0}"
SH
cat > "$FIXTURE_PREFIX/opt/prek/bin/prek" << 'SH'
#!/bin/sh
if [ "$1" = --version ]; then printf 'prek 0.3.0\n'; exit 0; fi
printf '%s\n' "$@" >> "$HOME/runner-args"
printf '%s\n' "$PATH" > "$HOME/runner-path"
if [ "${CHECK_BOUND_GIT:-0}" = 1 ]; then
  [ "$(command -v git)" = "$FIXTURE_PREFIX/opt/git/bin/git" ] || exit 91
  git --version > /dev/null || exit 92
fi
exit "${FAKE_SUITE_EXIT:-0}"
SH
chmod +x "$FIXTURE_PREFIX/opt/gitleaks/bin/gitleaks" "$FIXTURE_PREFIX/opt/prek/bin/prek"
for tool in bash git gitleaks prek shellcheck shfmt hadolint brew pip pipx; do
  cat > "$TMP/hostile/$tool" << 'SH'
#!/bin/sh
printf '%s\n' "$0" >> "$HOME/hostile-called"
exit 99
SH
  chmod +x "$TMP/hostile/$tool"
done

# Generate real formula launchers with fixture opt paths, then make Cellar read-only.
(
  cd "$ROOT"
  ruby "$ROOT/tests/lib/formula-fixture.rb" "$ROOT/packaging/caulking.rb.in"
)
ln -s "$FIXTURE_PREFIX/Cellar/caulking/1" "$FIXTURE_PREFIX/opt/caulking"
chmod -R a-w "$FIXTURE_PREFIX/Cellar"
launcher="$FIXTURE_PREFIX/bin/caulking"
PATH=/usr/bin:/bin "$launcher" setup --no-install
! grep -q /Cellar/ "$launcher" "$XDG_CONFIG_HOME/git/hooks/pre-commit" "$XDG_CONFIG_HOME/git/hooks/pre-push"
git -C "$TMP/repo" init -q
git -C "$TMP/repo" config user.name fixture
git -C "$TMP/repo" config user.email fixture@example.test
printf 'repos: []\n' > "$TMP/repo/.pre-commit-config.yaml"
# Manual run must keep the packaged Git ahead of ambient/system Git.
export CHECK_BOUND_GIT=1 CAULKING_GIT=/bad/inherited/git
printf '#!/bin/sh\nexit 99\n' > "$FIXTURE_PREFIX/bin/brew"
chmod +x "$FIXTURE_PREFIX/bin/brew"
PATH="$FIXTURE_PREFIX/bin:/usr/bin:/bin" "$launcher" run --repo "$TMP/repo" --profile baseline
grep -Fq "$FIXTURE_PREFIX/opt/git/bin" "$HOME/runner-path"
unset CHECK_BOUND_GIT CAULKING_GIT
: > "$HOME/runner-args"
printf 'clean\n' > "$TMP/repo/clean.txt"
git -C "$TMP/repo" add clean.txt

run_hook() {
  local stage="$1"
  shift
  (
    cd "$TMP/repo"
    PATH="${HOOK_TEST_PATH:-$TMP/hostile:/usr/bin:/bin}" "$XDG_CONFIG_HOME/git/hooks/$stage" "$@"
  )
}
run_hook pre-commit
grep -qx -- --staged "$HOME/gitleaks-args"
grep -qx -- --config "$HOME/runner-args"
grep -Fxq "$(git -C "$TMP/repo" rev-parse --show-toplevel)/.pre-commit-config.yaml" "$HOME/runner-args"
grep -qx pre-commit "$HOME/runner-args"
expected_path="$FIXTURE_PREFIX/opt/bash/bin:$FIXTURE_PREFIX/opt/git/bin:$FIXTURE_PREFIX/opt/gitleaks/bin:$FIXTURE_PREFIX/opt/prek/bin:$TMP/hostile:/usr/bin:/bin"
[[ "$(cat "$HOME/runner-path")" == "$expected_path" ]]
[[ ! -e "$HOME/hostile-called" ]]
HOOK_TEST_PATH=/usr/bin:/bin run_hook pre-commit
[[ "$(cat "$HOME/runner-path")" == "$FIXTURE_PREFIX/opt/bash/bin:$FIXTURE_PREFIX/opt/git/bin:$FIXTURE_PREFIX/opt/gitleaks/bin:$FIXTURE_PREFIX/opt/prek/bin:/usr/bin:/bin" ]]
runner_before="$(cksum "$HOME/runner-args")"
export FAKE_SCAN_EXIT=7
rc=0
run_hook pre-commit > "$TMP/output" 2>&1 || rc=$?
[[ "$rc" -eq 1 && "$(cksum "$HOME/runner-args")" == "$runner_before" ]]
unset FAKE_SCAN_EXIT
export FAKE_SUITE_EXIT=13
rc=0
run_hook pre-commit > "$TMP/output" 2>&1 || rc=$?
[[ "$rc" -eq 13 ]]
unset FAKE_SUITE_EXIT
mv "$FIXTURE_PREFIX/opt/prek/bin/prek" "$TMP/prek"
rc=0
run_hook pre-commit > "$TMP/output" 2>&1 || rc=$?
[[ "$rc" -eq 2 ]]
grep -q 'configured hook runner is missing' "$TMP/output"
mv "$TMP/prek" "$FIXTURE_PREFIX/opt/prek/bin/prek"
printf 'refs/heads/main 0000000000000000000000000000000000000000 refs/heads/main 1111111111111111111111111111111111111111\n' | run_hook pre-push origin fixture
grep -qx pre-push "$HOME/runner-args"

# Upgrade simulation: the existing CLI and hooks must work after old Cellar removal.
chmod -R u+w "$FIXTURE_PREFIX/Cellar"
mv "$FIXTURE_PREFIX/Cellar/caulking/1" "$FIXTURE_PREFIX/Cellar/caulking/2"
rm "$FIXTURE_PREFIX/opt/caulking"
ln -s "$FIXTURE_PREFIX/Cellar/caulking/2" "$FIXTURE_PREFIX/opt/caulking"
run_hook pre-commit
PATH=/usr/bin:/bin "$launcher" setup --no-install
run_hook pre-commit
[[ ! -e "$HOME/hostile-called" ]]
printf '%s\n' 'PASS: actual formula launchers, minimal PATH, pinned baseline, hook stages, failures, and upgrade'
