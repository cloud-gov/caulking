#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/caulking-uninstall.XXXXXX")"
trap 'rm -rf "$TMP"' EXIT
export HOME="$TMP/home" XDG_CONFIG_HOME="$TMP/xdg"
export GIT_CONFIG_GLOBAL="$HOME/.gitconfig" GIT_CONFIG_NOSYSTEM=1
unset GIT_CONFIG_COUNT GIT_CONFIG_PARAMETERS GIT_DIR GIT_WORK_TREE GIT_COMMON_DIR
mkdir -p "$HOME" "$XDG_CONFIG_HOME/git/hooks" "$XDG_CONFIG_HOME/caulking" "$XDG_CONFIG_HOME/gitleaks"
HOOK_DIR="$XDG_CONFIG_HOME/git/hooks"
for artifact in pre-commit pre-push commit-msg .caulking-wrapper.sh; do
  printf 'owned artifact\n' > "$HOOK_DIR/$artifact"
done
printf 'user hook\n' > "$HOOK_DIR/post-checkout"
printf 'custom policy\n' > "$XDG_CONFIG_HOME/gitleaks/config.toml"
git config --global user.name 'preserved user'
git config --global hooks.gitleaks true
git config --global core.hooksPath "$HOOK_DIR"
printf '%s\n' '/previous/user hooks' > "$XDG_CONFIG_HOME/caulking/previous_hookspath"
bash "$ROOT/uninstall.sh"
for artifact in pre-commit pre-push commit-msg .caulking-wrapper.sh; do
  [[ ! -e "$HOOK_DIR/$artifact" ]]
done
[[ "$(< "$HOOK_DIR/post-checkout")" == 'user hook' ]]
[[ "$(< "$XDG_CONFIG_HOME/gitleaks/config.toml")" == 'custom policy' ]]
[[ "$(git config --global --get core.hooksPath)" == '/previous/user hooks' ]]
[[ "$(git config --global --get user.name)" == 'preserved user' ]]
[[ "$(git config --global --get hooks.gitleaks)" == true ]]
# Existing no-previous-path behavior remains an unset, preserving other config.
rm "$XDG_CONFIG_HOME/caulking/previous_hookspath"
bash "$ROOT/uninstall.sh"
if git config --global --get core.hooksPath; then exit 1; fi
[[ "$(git config --global --get user.name)" == 'preserved user' ]]
[[ -f "$HOOK_DIR/post-checkout" ]]
printf 'PASS: uninstall removes wrapper, preserves unrelated hooks/policy/config\n'
