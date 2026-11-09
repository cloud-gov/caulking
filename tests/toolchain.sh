#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/caulking-toolchain.XXXXXX")"
TMP="$(cd "$TMP" && pwd -P)"
trap 'rm -rf "$TMP"' EXIT
export FAKE_HOME="$TMP/home with spaces"
export FAKE_LOG="$TMP/brew.log" FAKE_RUN="$TMP/run.log"
mkdir -p "$FAKE_HOME/bin" "$FAKE_HOME/opt" "$FAKE_HOME/Cellar" "$FAKE_HOME/Caskroom" "$TMP/fixtures" "$TMP/bin" "$TMP/repo with spaces" "$TMP/other repo"
REPO="$TMP/repo with spaces"
ORIGINAL_PATH="$PATH"

cat > "$FAKE_HOME/bin/brew" << 'FAKE'
#!/bin/bash
set -euo pipefail
printf '%s\n' "$*" >> "$FAKE_LOG"
[[ "${HOMEBREW_NO_AUTO_UPDATE:-}" == 1 ]]
[[ "${HOMEBREW_NO_INSTALL_UPGRADE:-}" == 1 ]]
[[ "${HOMEBREW_NO_INSTALL_CLEANUP:-}" == 1 ]]
case "$1" in
  --prefix)
    [[ "$#" == 1 ]] || exit 90
    if [[ "${FAKE_STALL_PREFIX:-0}" == 1 ]]; then
      printf '%s\n' "$$" > "$FAKE_HOME/stalled.pid"
      exec /bin/sleep 30
    fi
    printf '%s\n' "$FAKE_HOME"
    ;;
  install)
    if [[ "$2" == "--cask" ]]; then
      pkg="${3##*/}"
    else
      pkg="${2##*/}"
    fi
    [[ "${FAKE_FAIL_INSTALL:-}" != "$pkg" && "${FAKE_FAIL_INSTALL:-}" != "$2" ]] || exit 1
    if [[ "$pkg" == tflint && "${FAKE_TFLINT_MODE:-opt}" == cask ]]; then
      /bin/mkdir -p "$FAKE_HOME/Caskroom/tflint/1"
      /bin/cp "$FAKE_HOME/../fixtures/tflint" "$FAKE_HOME/bin/tflint"
    else
      bin_name="$pkg"
      [[ "$pkg" != opentofu ]] || bin_name=tofu
      /bin/mkdir -p "$FAKE_HOME/Cellar/$pkg/1/bin"
      /bin/cp "$FAKE_HOME/../fixtures/$pkg" "$FAKE_HOME/Cellar/$pkg/1/bin/$bin_name"
      /bin/ln -s "$FAKE_HOME/Cellar/$pkg/1" "$FAKE_HOME/opt/$pkg"
    fi
    ;;
  *) exit 90 ;;
esac
FAKE
cat > "$TMP/bin/uname" << 'FAKE'
#!/bin/bash
printf '%s\n' "${FAKE_OS:-Darwin}"
FAKE

make_binary() {
  local formula="$1" bin_name="$1"
  [[ "$formula" != opentofu ]] || bin_name=tofu
  cat > "$TMP/fixtures/$formula" << 'FAKE'
#!/bin/bash
set -euo pipefail
tool="${0##*/}"
if [[ "$tool" == prek && "${1:-}" == run ]]; then
  if [[ -n "${FAKE_ORDER:-}" ]]; then printf 'suite\n' >> "$FAKE_ORDER"; fi
  printf 'cwd=%s\nargs=%s\npath=%s\n' "$PWD" "$*" "$PATH" > "$FAKE_RUN"
  for name in gitleaks prek bash shellcheck shfmt hadolint ruff mypy bandit pip-audit go golangci-lint node tofu terraform tflint semgrep osv-scanner syft grype git; do
    if command -v "$name" > /dev/null; then
      printf '%s=%s\n' "$name" "$(command -v "$name")" >> "$FAKE_RUN"
    fi
  done
  exit "${FAKE_RUN_STATUS:-0}"
fi
[[ "${FAKE_BROKEN:-}" != "$tool" ]] || exit 1
if [[ "${FAKE_STALL_VERSION:-}" == "$tool" ]]; then
  printf '%s\n' "$$" > "$FAKE_HOME/stalled.pid"
  exec /bin/sleep 30
fi
if [[ "${FAKE_VERSION_TOOL:-}" == "$tool" ]]; then
  if [[ "$tool" == gitleaks || "$tool" == go ]]; then
    [[ "$1" == version ]]
  else
    [[ "$1" == --version ]]
  fi
  printf '%s\n' "${FAKE_VERSION_OUTPUT:-}"
  exit 0
fi
case "$tool" in
  bash) printf 'GNU bash, version %s.2.0\n' "${FAKE_BASH_MAJOR:-5}" ;;
  gitleaks) [[ "$1" == version ]]; printf '%s\n' "${FAKE_GITLEAKS_VERSION:-8.21.0}" ;;
  go) [[ "$1" == version ]]; printf 'go version go%s darwin/arm64\n' "${FAKE_GO_VERSION:-1.27.3}" ;;
  prek) [[ "$1" == --version ]]; printf 'prek 0.5.9\n' ;;
  shellcheck) [[ "$1" == --version ]]; printf 'version: 0.11.0\n' ;;
  shfmt) [[ "$1" == --version ]]; printf 'v3.14.1\n' ;;
  hadolint) [[ "$1" == --version ]]; printf 'Haskell Dockerfile Linter 2.15.1\n' ;;
  ruff) [[ "$1" == --version ]]; printf 'ruff 0.11.2\n' ;;
  mypy) [[ "$1" == --version ]]; printf 'mypy 1.15.0\n' ;;
  bandit) [[ "$1" == --version ]]; printf 'bandit 1.9.4\n' ;;
  pip-audit) [[ "$1" == --version ]]; printf 'pip-audit 2.10.1\n' ;;
  golangci-lint) [[ "$1" == --version ]]; printf 'golangci-lint has version 2.15.0\n' ;;
  node) [[ "$1" == --version ]]; printf 'v26.13.0\n' ;;
  tofu) [[ "$1" == --version ]]; printf 'OpenTofu v1.9.0\n' ;;
  terraform) [[ "$1" == --version ]]; printf 'Terraform v1.11.0\n' ;;
  tflint) [[ "$1" == --version ]]; printf 'TFLint version 0.55.1\n' ;;
  semgrep) [[ "$1" == --version ]]; printf '1.110.0\n' ;;
  osv-scanner) [[ "$1" == --version ]]; printf 'osv-scanner version: 2.0.0\n' ;;
  syft) [[ "$1" == --version ]]; printf 'syft 1.20.0\n' ;;
  grype) [[ "$1" == --version ]]; printf 'grype 0.89.0\n' ;;
  *) [[ "$1" == --version ]]; printf '%s 1.2.3\n' "$tool" ;;
esac
FAKE
  chmod +x "$TMP/fixtures/$formula"
  if [[ -d "$FAKE_HOME/opt/$formula/bin" ]]; then
    cp "$TMP/fixtures/$formula" "$FAKE_HOME/opt/$formula/bin/$bin_name"
  fi
}

for formula in gitleaks prek bash shellcheck shfmt hadolint ruff mypy bandit pip-audit go golangci-lint node opentofu terraform tflint semgrep osv-scanner syft grype; do
  make_binary "$formula"
done
chmod +x "$FAKE_HOME/bin/brew" "$TMP/bin/uname"
export PATH="$FAKE_HOME/bin:$TMP/bin:/usr/bin:/bin"

checks=0
expect() {
  local expected="$1" actual=0
  shift
  "$ROOT/caulking.sh" "$@" > "$TMP/output" 2>&1 || actual=$?
  if [[ "$actual" != "$expected" ]]; then
    printf 'FAIL: expected %s, got %s: %s\n' "$expected" "$actual" "$*" >&2
    cat "$TMP/output" >&2
    exit 1
  fi
  checks=$((checks + 1))
}

contains() {
  if ! /usr/bin/grep -F -- "$2" "$1" > /dev/null; then
    printf 'FAIL: %s does not contain %s\n' "$1" "$2" >&2
    exit 1
  fi
}

no_installs() {
  if [[ -f "$FAKE_LOG" ]] && /usr/bin/grep '^install ' "$FAKE_LOG" > /dev/null; then
    printf 'FAIL: unexpected install\n' >&2
    exit 1
  fi
}

for profile in baseline shell container python go javascript opentofu terraform security; do
  if [[ ! -f "$ROOT/brewfiles/$profile.Brewfile" || ! -r "$ROOT/brewfiles/$profile.Brewfile" ]]; then
    printf 'FAIL: missing Brewfile for profile %s\n' "$profile" >&2
    exit 1
  fi
  checks=$((checks + 1))
done

expect 2 bootstrap --repo "$REPO" --profile baseline --profile unknown
expect 2 bootstrap --repo "$REPO" --profile baseline --repo "$TMP/other repo"
expect 2 bootstrap --repo "$REPO" --profile baseline --dry-run --dry-run
expect 2 doctor --repo "$REPO" --profile baseline --dry-run
expect 2 run --repo "$REPO" --profile shell
expect 2 bootstrap --repo "$REPO" --profile
expect 2 bootstrap --repo "$REPO" --profile baseline --upgrade
expect 2 bootstrap --repo "$REPO"
printf 'repos: []\n' > "$TMP/.pre-commit-config.yaml"
expect 2 run --repo "$REPO" --profile baseline
contains "$TMP/output" 'readable direct config:'
printf 'repos: []\n' > "$REPO/.pre-commit-config.yaml"
printf 'baseline\nshell container\n' > "$REPO/.caulking-profiles"
expect 2 bootstrap --repo "$REPO"
# Literal shell syntax must remain data in the profiles file.
# shellcheck disable=SC2016
printf 'baseline\n$(touch %s/pwned)\n' "$TMP" > "$REPO/.caulking-profiles"
expect 2 bootstrap --repo "$REPO"
[[ ! -e "$TMP/pwned" ]]
printf 'baseline\000\n' > "$REPO/.caulking-profiles"
expect 2 bootstrap --repo "$REPO"
for ((i = 0; i < 129; i++)); do printf '# comment\n'; done > "$REPO/.caulking-profiles"
expect 2 bootstrap --repo "$REPO" --profile baseline
printf '%65537s' ' ' > "$REPO/.caulking-profiles"
expect 2 bootstrap --repo "$REPO" --profile baseline
[[ ! -e "$FAKE_LOG" ]]

printf '# composed profiles\n baseline # required runner\nshell\ncontainer\nbaseline' > "$REPO/.caulking-profiles"
expect 0 bootstrap --repo "$REPO" --profile shell --dry-run
contains "$TMP/output" 'Would install Homebrew formula: hadolint'
no_installs
[[ ! -e "$FAKE_LOG" ]]
expect 1 doctor --repo "$REPO"
contains "$TMP/output" 'missing Homebrew formula: bash'
no_installs
[[ ! -e "$FAKE_LOG" ]]

export FAKE_OS=Linux
expect 1 bootstrap --repo "$REPO"
contains "$TMP/output" 'only on macOS'
no_installs
unset FAKE_OS

export FAKE_FAIL_INSTALL=prek
expect 1 bootstrap --repo "$REPO" --profile baseline
contains "$TMP/output" 'install failed: prek; stopping'
[[ ! -e "$FAKE_HOME/Cellar/bash" && ! -f "$FAKE_RUN" ]]
unset FAKE_FAIL_INSTALL
: > "$FAKE_LOG"
expect 0 bootstrap --repo "$REPO" --profile baseline
[[ "$(/usr/bin/grep -c '^install ' "$FAKE_LOG")" == 5 ]]
: > "$FAKE_LOG"
expect 0 bootstrap --repo "$REPO" --profile baseline --profile baseline
no_installs
expect 0 doctor --repo "$REPO"
no_installs

export FAKE_BASH_MAJOR=3
expect 1 doctor --repo "$REPO"
contains "$TMP/output" 'Homebrew bash >=4 required'
expect 1 bootstrap --repo "$REPO"
no_installs
unset FAKE_BASH_MAJOR
for version in 8.20.9 7.99.99 8.21.0-rc.1; do
  export FAKE_GITLEAKS_VERSION="$version"
  expect 1 doctor --repo "$REPO"
  contains "$TMP/output" 'gitleaks >=8.21.0 required'
done
for version in 8.21.0 8.21.1 8.22.0 9.0.0 v8.21.0+build; do
  export FAKE_GITLEAKS_VERSION="$version"
  expect 0 doctor --repo "$REPO"
done
export FAKE_GITLEAKS_VERSION=8.21
expect 1 doctor --repo "$REPO"
contains "$TMP/output" 'unrecognized gitleaks semantic version'
unset FAKE_GITLEAKS_VERSION
no_installs
export FAKE_BROKEN=shfmt
expect 1 run --repo "$REPO"
[[ ! -f "$FAKE_RUN" ]]
no_installs
unset FAKE_BROKEN
rm "$FAKE_HOME/opt/hadolint/bin/hadolint"
expect 1 doctor --repo "$REPO"
contains "$TMP/output" 'missing executable:'
make_binary hadolint

# Ambient tools must neither satisfy doctor nor leak into the scoped runner PATH.
cat > "$TMP/bin/gitleaks" << 'FAKE'
#!/bin/bash
exit 99
FAKE
chmod +x "$TMP/bin/gitleaks"
mv "$FAKE_HOME/opt/gitleaks" "$TMP/gitleaks.opt"
mv "$FAKE_HOME/Cellar/gitleaks" "$TMP/gitleaks.cellar"
expect 1 doctor --repo "$REPO"
mv "$TMP/gitleaks.cellar" "$FAKE_HOME/Cellar/gitleaks"
# Cellar present but opt missing is broken, not a missing installation.
expect 1 bootstrap --repo "$REPO" --profile baseline
no_installs
mv "$TMP/gitleaks.opt" "$FAKE_HOME/opt/gitleaks"
expect 0 run --repo "$REPO"
contains "$FAKE_RUN" "cwd=$REPO"
contains "$FAKE_RUN" "args=run --all-files --config $REPO/.pre-commit-config.yaml"
for formula in gitleaks prek bash shellcheck shfmt hadolint; do
  contains "$FAKE_RUN" "$formula=$FAKE_HOME/opt/$formula/bin/$formula"
done
if /usr/bin/grep -F "$TMP/bin" "$FAKE_RUN" > /dev/null; then
  printf 'FAIL: ambient PATH leaked into runner\n' >&2
  exit 1
fi
export FAKE_RUN_STATUS=7
expect 7 run --repo "$REPO"
unset FAKE_RUN_STATUS
no_installs

# Shell alone is composable and does not implicitly require baseline.
expect 0 doctor --repo "$TMP/other repo" --profile shell

# Exercise expanded profiles: python, go, javascript, opentofu, terraform, security.
: > "$FAKE_LOG"
expect 0 bootstrap --repo "$TMP/other repo" \
  --profile python --profile go --profile javascript \
  --profile opentofu --profile terraform --profile security --dry-run
contains "$TMP/output" 'Would install Homebrew formula: ruff'
contains "$TMP/output" 'Would install Homebrew formula: bandit'
contains "$TMP/output" 'Would install Homebrew formula: pip-audit'
contains "$TMP/output" 'Would install Homebrew formula: golangci-lint'
contains "$TMP/output" 'Would install Homebrew formula: node'
contains "$TMP/output" 'Would install Homebrew formula: opentofu'
contains "$TMP/output" 'Would install Homebrew formula: hashicorp/tap/terraform'
contains "$TMP/output" 'Would install Homebrew formula: --cask terraform-linters/tap/tflint'
contains "$TMP/output" 'Would install Homebrew formula: osv-scanner'
# Selecting both opentofu and terraform must deduplicate tflint in the plan.
[[ "$(/usr/bin/grep -c 'tflint' "$TMP/output")" == 1 ]]
no_installs

export FAKE_TFLINT_MODE=cask
: > "$FAKE_LOG"
expect 0 bootstrap --repo "$TMP/other repo" \
  --profile python --profile go --profile javascript \
  --profile opentofu --profile terraform --profile security
[[ "$(/usr/bin/grep -c '^install ' "$FAKE_LOG")" == 14 ]]
[[ "$(/usr/bin/grep -c 'tflint' "$FAKE_LOG")" == 1 ]]
: > "$FAKE_LOG"
expect 0 doctor --repo "$TMP/other repo" \
  --profile python --profile go --profile javascript \
  --profile opentofu --profile terraform --profile security
contains "$TMP/output" "OK opentofu: OpenTofu v1.9.0 ($FAKE_HOME/opt/opentofu/bin/tofu)"
contains "$TMP/output" "OK tflint: TFLint version 0.55.1 ($FAKE_HOME/bin/tflint)"
no_installs

# Verify opt/tflint/bin/tflint resolution when installed as an opt link.
rm -rf "$FAKE_HOME/Caskroom/tflint" "$FAKE_HOME/bin/tflint"
unset FAKE_TFLINT_MODE
expect 0 bootstrap --repo "$TMP/other repo" --profile opentofu --profile terraform
contains "$TMP/output" "OK tflint: TFLint version 0.55.1 ($FAKE_HOME/opt/tflint/bin/tflint)"
: > "$FAKE_LOG"

# Verify run includes all expanded profile tools on the scoped PATH.
expect 0 run --repo "$REPO" \
  --profile python --profile go --profile javascript \
  --profile opentofu --profile terraform --profile security
contains "$FAKE_RUN" "tofu=$FAKE_HOME/opt/opentofu/bin/tofu"
contains "$FAKE_RUN" "terraform=$FAKE_HOME/opt/terraform/bin/terraform"
contains "$FAKE_RUN" "tflint=$FAKE_HOME/opt/tflint/bin/tflint"
for formula in ruff mypy bandit pip-audit go golangci-lint node semgrep osv-scanner syft grype; do
  contains "$FAKE_RUN" "$formula=$FAKE_HOME/opt/$formula/bin/$formula"
done
no_installs

# Minimum version floors reject outdated versions while accepting upgraded higher versions.
for spec in \
  "prek|prek|prek 0.3.9|prek >=0.4.0 required" \
  "hadolint|container|Haskell Dockerfile Linter 2.10.0|hadolint >=2.12.0 required" \
  "ruff|python|ruff 0.3.0|ruff >=0.4.0 required" \
  "mypy|python|mypy 1.7.1|mypy >=1.8.0 required" \
  "bandit|python|bandit 1.7.4|bandit >=1.7.5 required" \
  "pip-audit|python|pip-audit 2.6.3|pip-audit >=2.7.0 required" \
  "go|go|go version go1.21.0 darwin/arm64|go >=1.22.0 required" \
  "golangci-lint|go|golangci-lint has version 1.58.2|golangci-lint >=1.59.0 required" \
  "node|javascript|v18.19.0|node >=20.0.0 required" \
  "tofu|opentofu|OpenTofu v1.5.2|opentofu >=1.6.0 required" \
  "terraform|terraform|Terraform v1.4.6|terraform >=1.5.0 required" \
  "tflint|terraform|TFLint version 0.49.0|tflint >=0.50.0 required" \
  "semgrep|security|1.49.0|semgrep >=1.50.0 required" \
  "osv-scanner|security|osv-scanner version: 1.6.2|osv-scanner >=1.7.0 required" \
  "syft|security|syft 0.105.0|syft >=1.0.0 required" \
  "grype|security|grype 0.73.0|grype >=0.74.0 required"; do
  IFS='|' read -r vtool vprofile vout verr <<< "$spec"
  [[ "$vprofile" != prek ]] || vprofile=baseline
  export FAKE_VERSION_TOOL="$vtool" FAKE_VERSION_OUTPUT="$vout"
  expect 1 doctor --repo "$TMP/other repo" --profile "$vprofile"
  contains "$TMP/output" "$verr"
done
for spec in \
  "golangci-lint|go|golangci-lint has version 2.15.0" \
  "node|javascript|v26.13.0" \
  "go|go|go version go1.27.3 darwin/arm64" \
  "hadolint|container|Haskell Dockerfile Linter 2.15.1"; do
  IFS='|' read -r vtool vprofile vout <<< "$spec"
  export FAKE_VERSION_TOOL="$vtool" FAKE_VERSION_OUTPUT="$vout"
  expect 0 doctor --repo "$TMP/other repo" --profile "$vprofile"
done
unset FAKE_VERSION_TOOL FAKE_VERSION_OUTPUT
no_installs

# Only the launcher and profile-reader utilities are on the incoming PATH.
# Every managed CLI must still resolve through its Homebrew prefix.
ln -s /bin/bash "$TMP/bin/bash"
ln -s /usr/bin/wc "$TMP/bin/wc"
ln -s /usr/bin/dirname "$TMP/bin/dirname"
ln -s /usr/bin/git "$TMP/bin/git"
for utility in mktemp sleep cat rm env; do
  ln -s "$(command -v "$utility")" "$TMP/bin/$utility"
done
export PATH="$FAKE_HOME/bin:$TMP/bin"
expect 0 run --repo "$REPO"
contains "$FAKE_RUN" "bash=$FAKE_HOME/opt/bash/bin/bash"
contains "$FAKE_RUN" "git=$TMP/bin/git"
export CAULKING_GIT=/bad/inherited/git
expect 0 run --repo "$REPO"
contains "$FAKE_RUN" "git=$TMP/bin/git"
unset CAULKING_GIT
export PATH="$FAKE_HOME/bin:$TMP/bin:/usr/bin:/bin"

# Nonconventional discovery invokes bare --prefix only, with a bounded probe.
mkdir -p "$TMP/nonstandard"
cp "$FAKE_HOME/bin/brew" "$TMP/nonstandard/brew"
export PATH="$TMP/nonstandard:$FAKE_HOME/bin:$TMP/bin:/usr/bin:/bin"
expect 0 doctor --repo "$REPO"
contains "$FAKE_LOG" '--prefix'
expect 0 bootstrap --repo "$REPO" --dry-run
mkdir -p "$TMP/probe scratch"
export TMPDIR="$TMP/probe scratch"
export FAKE_STALL_PREFIX=1
started=$SECONDS
expect 1 doctor --repo "$REPO"
[[ $((SECONDS - started)) -lt 12 ]]
contains "$TMP/output" 'probe timed out after 5s'
if kill -0 "$(< "$FAKE_HOME/stalled.pid")" 2> /dev/null; then exit 1; fi
unset FAKE_STALL_PREFIX
export PATH="$FAKE_HOME/bin:$TMP/bin:/usr/bin:/bin"
export FAKE_STALL_VERSION=gitleaks
rm "$FAKE_RUN"
started=$SECONDS
expect 1 run --repo "$REPO"
[[ $((SECONDS - started)) -lt 12 ]]
contains "$TMP/output" 'probe timed out after 5s'
[[ ! -e "$FAKE_RUN" ]]
if kill -0 "$(< "$FAKE_HOME/stalled.pid")" 2> /dev/null; then exit 1; fi
unset FAKE_STALL_VERSION
for leftover in "$TMP/probe scratch"/*; do
  [[ ! -e "$leftover" ]] || {
    printf 'FAIL: probe scratch not cleaned: %s\n' "$leftover" >&2
    exit 1
  }
done
if /usr/bin/grep -E '^(list|--prefix .)' "$FAKE_LOG" > /dev/null; then
  printf 'FAIL: named Homebrew query executed\n' >&2
  exit 1
fi
no_installs

# Omitted --repo selects the current directory; no profiles file is required.
(
  cd "$TMP/other repo"
  expect 0 doctor --profile shell
)
checks=$((checks + 1))

# Test missing Homebrew and missing profile Brewfile in an isolated copy.
mkdir -p "$TMP/no brew/scripts"
cp "$ROOT/caulking.sh" "$TMP/no brew/caulking.sh"
cp -R "$ROOT/brewfiles" "$TMP/no brew/brewfiles"
/usr/bin/sed 's@/opt/homebrew/bin/brew /usr/local/bin/brew@/nonexistent/caulking-test-brew@' \
  "$ROOT/scripts/toolchain.sh" > "$TMP/no brew/scripts/toolchain.sh"
actual=0
PATH=/usr/bin:/bin "$TMP/no brew/caulking.sh" doctor --repo "$REPO" > "$TMP/output" 2>&1 || actual=$?
[[ "$actual" == 1 ]]
contains "$TMP/output" 'Homebrew is missing'
checks=$((checks + 1))

rm "$TMP/no brew/brewfiles/python.Brewfile"
actual=0
"$TMP/no brew/caulking.sh" doctor --repo "$TMP/other repo" --profile python > "$TMP/output" 2>&1 || actual=$?
[[ "$actual" == 1 ]]
contains "$TMP/output" 'missing profile Brewfile:'
checks=$((checks + 1))
actual=0
"$TMP/no brew/caulking.sh" bootstrap --repo "$TMP/other repo" --profile python --dry-run > "$TMP/output" 2>&1 || actual=$?
[[ "$actual" == 1 ]]
contains "$TMP/output" 'missing profile Brewfile:'
checks=$((checks + 1))

# Internal hook arguments fail before Homebrew discovery.
: > "$FAKE_LOG"
expect 2 hook-run --repo "$REPO" --stage post-commit
expect 2 hook-run --repo . --stage pre-commit
expect 2 hook-run --repo "$REPO"
expect 2 hook-run --repo "$REPO" --stage pre-commit --profile baseline
expect 2 hook-run --repo "$TMP/other repo" --stage pre-commit
[[ ! -s "$FAKE_LOG" ]]

# Exercise generated installed launchers, the actual global wrapper, and parser.
# Setup changes only this temporary HOME and isolated Git configuration.
SETUP_BASH=/bin/bash
for candidate in /opt/homebrew/opt/bash/bin/bash /usr/local/opt/bash/bin/bash; do
  if [[ -x "$candidate" ]] && "$candidate" -c '((BASH_VERSINFO[0] >= 4))'; then
    SETUP_BASH="$candidate"
    break
  fi
done
if "$SETUP_BASH" -c '((BASH_VERSINFO[0] >= 4))'; then
  export HOME="$TMP/isolated home" XDG_CONFIG_HOME="$TMP/isolated xdg"
  export GIT_CONFIG_GLOBAL="$HOME/.gitconfig" GIT_CONFIG_NOSYSTEM=1
  unset GIT_CONFIG_COUNT GIT_CONFIG_PARAMETERS GIT_DIR GIT_WORK_TREE GIT_COMMON_DIR BASH_ENV ENV
  mkdir -p "$HOME" "$TMP/app/scripts" "$TMP/app/hooks" "$TMP/stable" "$TMP/global/bin"
  cp "$ROOT/caulking.sh" "$ROOT/install.sh" "$TMP/app/"
  cp -R "$ROOT/brewfiles" "$TMP/app/brewfiles"
  cp "$ROOT/scripts/lib.sh" "$ROOT/scripts/toolchain.sh" "$TMP/app/scripts/"
  cp "$ROOT/hooks/hook-wrapper.sh" "$TMP/app/hooks/"
  ln -s "$TMP/app" "$TMP/stable/app"
  export FAKE_ORDER="$TMP/order.log"
  cat > "$TMP/global/bin/gitleaks" << 'FAKE'
#!/bin/bash
set -euo pipefail
if [[ "$1" == version ]]; then printf '8.21.0\n'; exit 0; fi
printf 'global-gitleaks %s\n' "$*" >> "$FAKE_ORDER"
exit "${FAKE_GLOBAL_FAILURE:-0}"
FAKE
  chmod +x "$TMP/global/bin/gitleaks"
  {
    printf 'RUNTIME_BASH=%q\n' "$SETUP_BASH"
    printf 'RUNTIME_GIT=/usr/bin/git\n'
    printf 'RUNTIME_GITLEAKS=%q\n' "$TMP/global/bin/gitleaks"
    printf 'RUNTIME_RUNNER=%q\n' "$FAKE_HOME/opt/prek/bin/prek"
    printf 'RUNTIME_CLI=%q\n' "$TMP/stable/app/caulking.sh"
    printf 'RUNTIME_PATH=%q\n' "$FAKE_HOME/bin:/usr/bin:/bin"
  } > "$TMP/app/scripts/package-runtime.sh"
  PATH="$TMP/global/bin:$FAKE_HOME/opt/prek/bin:$FAKE_HOME/bin:/usr/bin:/bin" \
    "$SETUP_BASH" "$TMP/stable/app/caulking.sh" setup --no-install > "$TMP/setup.output" 2>&1 || {
    cat "$TMP/setup.output" >&2
    exit 1
  }
  contains "$XDG_CONFIG_HOME/git/hooks/pre-commit" "$TMP/stable/app/caulking.sh"
  /usr/bin/git -C "$REPO" init -q
  printf 'safe\n' > "$REPO/safe.txt"
  /usr/bin/git -C "$REPO" add safe.txt
  run_hook() {
    local stage="$1" expected="$2" actual=0
    shift 2
    (
      cd "$REPO"
      PATH=/usr/bin:/bin CAULKING_TOOLCHAIN_CLI=/bad/inherited CAULKING_BASH=/bad/bash \
        "$XDG_CONFIG_HOME/git/hooks/$stage" "$@"
    ) > "$TMP/hook.output" 2>&1 || actual=$?
    if [[ "$actual" != "$expected" ]]; then
      cat "$TMP/hook.output" >&2
      printf 'FAIL: installed %s expected %s, got %s\n' "$stage" "$expected" "$actual" >&2
      exit 1
    fi
    checks=$((checks + 1))
  }
  : > "$FAKE_ORDER"
  run_hook pre-commit 0
  contains "$FAKE_RUN" "args=run --hook-stage pre-commit --show-diff-on-failure --config $REPO/.pre-commit-config.yaml"
  for formula in gitleaks prek bash shellcheck shfmt hadolint; do
    contains "$FAKE_RUN" "$formula=$FAKE_HOME/opt/$formula/bin/$formula"
  done
  [[ "$(/usr/bin/sed -n '1p' "$FAKE_ORDER")" == global-gitleaks* ]]
  [[ "$(/usr/bin/sed -n '2p' "$FAKE_ORDER")" == suite ]]
  contains "$FAKE_ORDER" '--staged'
  export FAKE_RUN_STATUS=7
  run_hook pre-commit 7
  unset FAKE_RUN_STATUS
  : > "$FAKE_ORDER"
  printf 'refs/heads/main %040d refs/heads/main %040d\n' 1 2 | run_hook pre-push 0 origin example
  contains "$FAKE_ORDER" '--log-opts=0000000000000000000000000000000000000002..0000000000000000000000000000000000000001'
  contains "$FAKE_RUN" 'args=run --hook-stage pre-push --show-diff-on-failure'
  checks=$((checks + 1)) # Pipeline's run_hook count lives in its subshell.
  if /usr/bin/grep -F -- '--all-files' "$FAKE_RUN" > /dev/null; then exit 1; fi
  : > "$FAKE_ORDER"
  export FAKE_GLOBAL_FAILURE=1
  run_hook pre-commit 1
  unset FAKE_GLOBAL_FAILURE
  [[ "$(/usr/bin/wc -l < "$FAKE_ORDER")" -eq 1 ]]
  printf 'private\n' > "$REPO/blocked.key"
  /usr/bin/git -C "$REPO" add blocked.key
  : > "$FAKE_ORDER"
  run_hook pre-commit 1
  [[ ! -s "$FAKE_ORDER" ]]
  /usr/bin/git -C "$REPO" rm --cached -q blocked.key
  mv "$TMP/stable/app" "$TMP/stable/app.link"
  run_hook pre-commit 2
  contains "$TMP/hook.output" 'profile-aware hook helper is missing'
  mv "$TMP/stable/app.link" "$TMP/stable/app"
  # An application upgrade retargets opt without regenerating global hooks.
  cp -R "$TMP/app" "$TMP/app-next"
  rm "$TMP/stable/app"
  ln -s "$TMP/app-next" "$TMP/stable/app"
  rm -rf "$TMP/app"
  run_hook pre-commit 0
  mv "$REPO/.pre-commit-config.yaml" "$TMP/direct.config"
  : > "$FAKE_LOG"
  run_hook pre-commit 2
  contains "$TMP/hook.output" 'readable direct config'
  [[ ! -s "$FAKE_LOG" ]]
  mv "$TMP/direct.config" "$REPO/.pre-commit-config.yaml"
  printf 'shell\n' > "$REPO/.caulking-profiles"
  run_hook pre-commit 2
  contains "$TMP/hook.output" 'explicit baseline profile'
  printf 'baseline\nshell\ncontainer\n' > "$REPO/.caulking-profiles"
  mv "$FAKE_HOME/opt/shfmt" "$TMP/shfmt.opt"
  run_hook pre-commit 1
  contains "$TMP/hook.output" 'missing executable:'
  mv "$TMP/shfmt.opt" "$FAKE_HOME/opt/shfmt"
  # No profile file retains the established pinned-runner path.
  mv "$REPO/.caulking-profiles" "$TMP/profiles.saved"
  run_hook pre-commit 0
  contains "$FAKE_RUN" "args=run --config $REPO/.pre-commit-config.yaml --hook-stage pre-commit"
  no_installs
else
  printf 'SKIP: installed setup integration requires Bash >=4\n'
fi

export PATH="$ORIGINAL_PATH"
printf 'PASS: %s isolated toolchain CLI checks\n' "$checks"
