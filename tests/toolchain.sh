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
      [[ "$pkg" != markdownlint-cli ]] || bin_name=markdownlint
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
  [[ "$formula" != markdownlint-cli ]] || bin_name=markdownlint
  cat > "$TMP/fixtures/$formula" << 'FAKE'
#!/bin/bash
set -euo pipefail
tool="${0##*/}"
if [[ "$tool" == prek && "${1:-}" == run ]]; then
  if [[ -n "${FAKE_ORDER:-}" ]]; then printf 'suite\n' >> "$FAKE_ORDER"; fi
  printf 'cwd=%s\nargs=%s\npath=%s\n' "$PWD" "$*" "$PATH" > "$FAKE_RUN"
  for name in gitleaks prek bash shellcheck shfmt hadolint ruff mypy pyright bandit pip-audit go golangci-lint gosec govulncheck node ruby rubocop tofu terraform tflint yamllint yamlfmt actionlint zizmor markdownlint semgrep osv-scanner syft grype checkov git; do
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
  pyright) [[ "$1" == --version ]]; printf 'pyright 1.1.400\n' ;;
  bandit) [[ "$1" == --version ]]; printf 'bandit 1.9.4\n' ;;
  pip-audit) [[ "$1" == --version ]]; printf 'pip-audit 2.10.1\n' ;;
  golangci-lint) [[ "$1" == --version ]]; printf 'golangci-lint has version 2.15.0\n' ;;
  gosec) [[ "$1" == --version ]]; printf 'Version: 2.21.0\n' ;;
  govulncheck) [[ "$1" == --version ]]; printf 'Go: go1.27.3\nScanner: govulncheck@v1.9.0\n' ;;
  node) [[ "$1" == --version ]]; printf 'v26.13.0\n' ;;
  ruby) [[ "$1" == --version ]]; printf 'ruby 3.4.2 (2025-02-15 revision 12345) [arm64-darwin24]\n' ;;
  rubocop) [[ "$1" == --version ]]; printf '1.75.0\n' ;;
  tofu) [[ "$1" == --version ]]; printf 'OpenTofu v1.9.0\n' ;;
  terraform) [[ "$1" == --version ]]; printf 'Terraform v1.11.0\n' ;;
  tflint) [[ "$1" == --version ]]; printf 'TFLint version 0.55.1\n' ;;
  yamllint) [[ "$1" == --version ]]; printf 'yamllint 1.38.0\n' ;;
  yamlfmt) [[ "$1" == --version ]]; printf '0.16.0\n' ;;
  actionlint) [[ "$1" == --version ]]; printf '1.7.12\ninstalled by building from source\n' ;;
  zizmor) [[ "$1" == --version ]]; printf 'zizmor 1.5.0\n' ;;
  markdownlint) [[ "$1" == --version ]]; printf '0.50.0\n' ;;
  semgrep) [[ "$1" == --version ]]; printf '1.110.0\n' ;;
  osv-scanner) [[ "$1" == --version ]]; printf 'osv-scanner version: 2.0.0\n' ;;
  syft) [[ "$1" == --version ]]; printf 'syft 1.20.0\n' ;;
  grype) [[ "$1" == --version ]]; printf 'grype 0.89.0\n' ;;
  checkov) [[ "$1" == --version ]]; printf '3.2.400\n' ;;
  *) [[ "$1" == --version ]]; printf '%s 1.2.3\n' "$tool" ;;
esac
FAKE
  chmod +x "$TMP/fixtures/$formula"
  if [[ -d "$FAKE_HOME/opt/$formula/bin" ]]; then
    cp "$TMP/fixtures/$formula" "$FAKE_HOME/opt/$formula/bin/$bin_name"
  fi
}

for formula in gitleaks prek bash shellcheck shfmt hadolint ruff mypy pyright bandit pip-audit go golangci-lint gosec govulncheck node ruby rubocop opentofu terraform tflint yamllint yamlfmt actionlint zizmor markdownlint-cli semgrep osv-scanner syft grype checkov; do
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

for profile in baseline shell container python go javascript ruby opentofu terraform docs security; do
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
ln -s "$TMP/missing.config" "$REPO/.pre-commit-config.yaml"
expect 2 bootstrap --repo "$REPO"
contains "$TMP/output" 'readable direct config required:'
rm "$REPO/.pre-commit-config.yaml"
printf 'repos:\n  - repo: local\n    hooks:\n      - id: shellcheck shfmt\n' > "$REPO/.pre-commit-config.yaml"
expect 2 bootstrap --repo "$REPO"
contains "$TMP/output" 'invalid hook id in config:'
# Literal shell syntax must remain data in .pre-commit-config.yaml.
# shellcheck disable=SC2016
printf 'repos:\n  - repo: local\n    hooks:\n      - id: $(touch %s/pwned)\n' "$TMP" > "$REPO/.pre-commit-config.yaml"
expect 2 bootstrap --repo "$REPO"
[[ ! -e "$TMP/pwned" ]]
# shellcheck disable=SC2016
printf 'repos:\n  - repo: local\n    hooks: [{id: $(touch %s/pwned)}]\n' "$TMP" > "$REPO/.pre-commit-config.yaml"
expect 2 bootstrap --repo "$REPO"
[[ ! -e "$TMP/pwned" ]]
printf 'repos: []\000\n' > "$REPO/.pre-commit-config.yaml"
expect 2 bootstrap --repo "$REPO"
for ((i = 0; i < 1025; i++)); do printf '# comment\n'; done > "$REPO/.pre-commit-config.yaml"
expect 2 bootstrap --repo "$REPO" --profile baseline
printf '%65537s' ' ' > "$REPO/.pre-commit-config.yaml"
expect 2 bootstrap --repo "$REPO" --profile baseline
[[ ! -e "$FAKE_LOG" ]]

cat > "$REPO/.pre-commit-config.yaml" << 'YAML'
# Direct config with block, quoted, flow, and self-contained hook IDs
repos:
  - repo: https://github.com/pre-commit/pre-commit-hooks
    rev: v5.0.0
    hooks:
      - id: check-merge-conflict # self-contained hook ignored by formula mapper
      - id: "shellcheck"
      - id: 'shfmt-check'
  - repo: local
    hooks:
      - {id: hadolint, name: hadolint}
      - { id: custom-hook }
YAML
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

# Exercise expanded profiles: python, go, javascript, ruby, opentofu, terraform, docs, security.
: > "$FAKE_LOG"
expect 0 bootstrap --repo "$TMP/other repo" \
  --profile python --profile go --profile javascript --profile ruby \
  --profile opentofu --profile terraform --profile docs --profile security --dry-run
contains "$TMP/output" 'Would install Homebrew formula: ruff'
contains "$TMP/output" 'Would install Homebrew formula: pyright'
contains "$TMP/output" 'Would install Homebrew formula: bandit'
contains "$TMP/output" 'Would install Homebrew formula: pip-audit'
contains "$TMP/output" 'Would install Homebrew formula: golangci-lint'
contains "$TMP/output" 'Would install Homebrew formula: gosec'
contains "$TMP/output" 'Would install Homebrew formula: govulncheck'
contains "$TMP/output" 'Would install Homebrew formula: node'
contains "$TMP/output" 'Would install Homebrew formula: ruby'
contains "$TMP/output" 'Would install Homebrew formula: rubocop'
contains "$TMP/output" 'Would install Homebrew formula: opentofu'
contains "$TMP/output" 'Would install Homebrew formula: hashicorp/tap/terraform'
contains "$TMP/output" 'Would install Homebrew formula: --cask terraform-linters/tap/tflint'
contains "$TMP/output" 'Would install Homebrew formula: yamllint'
contains "$TMP/output" 'Would install Homebrew formula: yamlfmt'
contains "$TMP/output" 'Would install Homebrew formula: actionlint'
contains "$TMP/output" 'Would install Homebrew formula: zizmor'
contains "$TMP/output" 'Would install Homebrew formula: markdownlint-cli'
contains "$TMP/output" 'Would install Homebrew formula: osv-scanner'
contains "$TMP/output" 'Would install Homebrew formula: checkov'
# Selecting both opentofu and terraform must deduplicate tflint in the plan.
[[ "$(/usr/bin/grep -c 'tflint' "$TMP/output")" == 1 ]]
no_installs

export FAKE_TFLINT_MODE=cask
: > "$FAKE_LOG"
expect 0 bootstrap --repo "$TMP/other repo" \
  --profile python --profile go --profile javascript --profile ruby \
  --profile opentofu --profile terraform --profile docs --profile security
[[ "$(/usr/bin/grep -c '^install ' "$FAKE_LOG")" == 25 ]]
[[ "$(/usr/bin/grep -c 'tflint' "$FAKE_LOG")" == 1 ]]
: > "$FAKE_LOG"
expect 0 doctor --repo "$TMP/other repo" \
  --profile python --profile go --profile javascript --profile ruby \
  --profile opentofu --profile terraform --profile docs --profile security
contains "$TMP/output" "OK opentofu: OpenTofu v1.9.0 ($FAKE_HOME/opt/opentofu/bin/tofu)"
contains "$TMP/output" "OK markdownlint-cli: 0.50.0 ($FAKE_HOME/opt/markdownlint-cli/bin/markdownlint)"
contains "$TMP/output" "OK tflint: TFLint version 0.55.1 ($FAKE_HOME/bin/tflint)"
no_installs

# Verify opt/tflint/bin/tflint resolution when installed as an opt link.
rm -rf "$FAKE_HOME/Caskroom/tflint" "$FAKE_HOME/bin/tflint"
unset FAKE_TFLINT_MODE
expect 0 bootstrap --repo "$TMP/other repo" --profile opentofu --profile terraform
contains "$TMP/output" "OK tflint: TFLint version 0.55.1 ($FAKE_HOME/opt/tflint/bin/tflint)"
: > "$FAKE_LOG"

# Verify run includes all expanded profile tools on the scoped PATH, and verify
# direct hook ID derivation from .pre-commit-config.yaml without --profile flags.
cat > "$TMP/other repo/.pre-commit-config.yaml" << 'YAML'
repos:
  - repo: local
    hooks:
      - id: bash-syntax
      - id: ruff-format-check
      - id: mypy
      - id: pyright
      - id: bandit
      - id: pip-audit
      - id: go-mod-tidy
      - id: golangci-lint-full
      - id: gosec
      - id: govulncheck
      - id: biome-ci
      - id: bundle-audit
      - id: rubocop-check
      - id: tofu-validate
      - id: terraform_validate
      - id: terraform_tflint
      - id: terraform_checkov
      - id: yamllint
      - id: yamlfmt-check
      - id: actionlint
      - id: zizmor
      - id: markdownlint-check
      - id: semgrep-ci
      - id: osv-scanner-lockfile
      - id: syft
      - id: grype-sbom
YAML
expect 0 run --repo "$TMP/other repo"
contains "$FAKE_RUN" "tofu=$FAKE_HOME/opt/opentofu/bin/tofu"
contains "$FAKE_RUN" "terraform=$FAKE_HOME/opt/terraform/bin/terraform"
contains "$FAKE_RUN" "tflint=$FAKE_HOME/opt/tflint/bin/tflint"
contains "$FAKE_RUN" "markdownlint=$FAKE_HOME/opt/markdownlint-cli/bin/markdownlint"
for formula in ruff mypy pyright bandit pip-audit go golangci-lint gosec govulncheck node ruby rubocop yamllint yamlfmt actionlint zizmor semgrep osv-scanner syft grype checkov; do
  contains "$FAKE_RUN" "$formula=$FAKE_HOME/opt/$formula/bin/$formula"
done
rm "$TMP/other repo/.pre-commit-config.yaml"
no_installs

# Minimum version floors reject outdated versions while accepting upgraded higher versions.
for spec in \
  "prek|prek|prek 0.3.9|prek >=0.4.0 required" \
  "hadolint|container|Haskell Dockerfile Linter 2.10.0|hadolint >=2.12.0 required" \
  "ruff|python|ruff 0.3.0|ruff >=0.4.0 required" \
  "mypy|python|mypy 1.7.1|mypy >=1.8.0 required" \
  "pyright|python|pyright 1.1.349|pyright >=1.1.350 required" \
  "bandit|python|bandit 1.7.4|bandit >=1.7.5 required" \
  "pip-audit|python|pip-audit 2.6.3|pip-audit >=2.7.0 required" \
  "go|go|go version go1.21.0 darwin/arm64|go >=1.22.0 required" \
  "golangci-lint|go|golangci-lint has version 1.58.2|golangci-lint >=1.59.0 required" \
  "gosec|go|Version: 2.17.0|gosec >=2.18.0 required" \
  "govulncheck|go|govulncheck@v0.9.0|govulncheck >=1.0.0 required" \
  "node|javascript|v18.19.0|node >=20.0.0 required" \
  "ruby|ruby|ruby 3.1.4 (2023-03-30 revision 957bb7cb81) [arm64-darwin22]|ruby >=3.2.0 required" \
  "rubocop|ruby|1.59.0|rubocop >=1.60.0 required" \
  "tofu|opentofu|OpenTofu v1.5.2|opentofu >=1.6.0 required" \
  "terraform|terraform|Terraform v1.4.6|terraform >=1.5.0 required" \
  "tflint|terraform|TFLint version 0.49.0|tflint >=0.50.0 required" \
  "yamllint|docs|yamllint 1.34.0|yamllint >=1.35.0 required" \
  "yamlfmt|docs|0.12.0|yamlfmt >=0.13.0 required" \
  "actionlint|docs|1.6.27|actionlint >=1.7.0 required" \
  "zizmor|docs|zizmor 0.9.0|zizmor >=1.0.0 required" \
  "markdownlint|docs|0.38.0|markdownlint-cli >=0.39.0 required" \
  "semgrep|security|1.49.0|semgrep >=1.50.0 required" \
  "osv-scanner|security|osv-scanner version: 1.6.2|osv-scanner >=1.7.0 required" \
  "syft|security|syft 0.105.0|syft >=1.0.0 required" \
  "grype|security|grype 0.73.0|grype >=0.74.0 required" \
  "checkov|security|3.1.9|checkov >=3.2.0 required"; do
  IFS='|' read -r vtool vprofile vout verr <<< "$spec"
  [[ "$vprofile" != prek ]] || vprofile=baseline
  export FAKE_VERSION_TOOL="$vtool" FAKE_VERSION_OUTPUT="$vout"
  expect 1 doctor --repo "$TMP/other repo" --profile "$vprofile"
  contains "$TMP/output" "$verr"
done
export FAKE_VERSION_TOOL=govulncheck
export FAKE_VERSION_OUTPUT
FAKE_VERSION_OUTPUT="$(printf 'Go: go1.27.3\nScanner: govulncheck@v0.9.0\n')"
expect 1 doctor --repo "$TMP/other repo" --profile go
contains "$TMP/output" 'govulncheck >=1.0.0 required'
FAKE_VERSION_OUTPUT="$(printf 'Go: go1.27.3\nScanner: govulncheck@v1.9.0\n')"
expect 0 doctor --repo "$TMP/other repo" --profile go
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
cp "$ROOT/scripts/detect.sh" "$TMP/no brew/scripts/detect.sh"
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

# Exercise detect and init CLI validation, multi-stack detection, vendor/fixture exclusion,
# gap audit on legacy pre-commit-templates config, and init --write / --force / doctor flow.
expect 2 detect --repo "$REPO" --profile shell
expect 2 detect --repo "$REPO" --dry-run
expect 2 detect --repo "$REPO" --write
expect 2 init --repo "$REPO" --profile shell
expect 2 init --repo "$REPO" --dry-run
expect 2 init --repo "$REPO" --force
expect 2 init --repo "$REPO" --write --write
expect 2 init --repo "$REPO" --write --force --force
expect 2 doctor --repo "$REPO" --write
expect 2 doctor --repo "$REPO" --force

DETECT_REPO="$TMP/detect repo"
mkdir -p "$DETECT_REPO/.github/workflows" "$DETECT_REPO/tests/fixtures" "$DETECT_REPO/node_modules/pkg"
printf 'FROM alpine:3.20\n' > "$DETECT_REPO/Dockerfile"
printf '#!/usr/bin/env bash\necho ok\n' > "$DETECT_REPO/script.sh"
printf 'name: ci\non: push\n' > "$DETECT_REPO/.github/workflows/ci.yml"
printf 'print("ok")\n' > "$DETECT_REPO/app.py"
printf 'terraform {}\n' > "$DETECT_REPO/main.tf"
printf 'package ignored\n' > "$DETECT_REPO/tests/fixtures/ignored.go"
printf 'console.log("ignored");\n' > "$DETECT_REPO/node_modules/pkg/index.js"

expect 0 detect --repo "$DETECT_REPO"
contains "$TMP/output" 'Detected stacks: hygiene shell container python opentofu docs'
contains "$TMP/output" 'Recommended profiles: baseline shell container security python opentofu docs'
contains "$TMP/output" 'Recommended hooks: check-merge-conflict check-added-large-files trailing-whitespace end-of-file-fixer check-yaml-selfcontained check-json-selfcontained check-gsa-email shellcheck shfmt-check hadolint grype ruff-check ruff-format mypy bandit pip-audit tofu-fmt tofu-validate tflint semgrep osv-scanner yamllint actionlint zizmor'
contains "$TMP/output" "Config status: missing (.pre-commit-config.yaml not found; run 'caulking.sh init --repo $DETECT_REPO --write' to generate)"
if /usr/bin/grep -Eq 'Detected stacks:.*\b(go|javascript)\b' "$TMP/output"; then
  printf 'FAIL: ignored fixture or node_modules triggered go or javascript stack\n' >&2
  exit 1
fi

# Gap audit on a general-task-style v0.5.3 pre-commit-templates config.
cat > "$DETECT_REPO/.pre-commit-config.yaml" << 'YAML'
repos:
  - repo: https://github.com/cloud-gov/pre-commit-templates
    rev: v0.5.3
    hooks:
      - id: check-yaml
      - id: shellcheck
      - id: shfmt-check
      - id: hadolint
YAML
expect 0 detect --repo "$DETECT_REPO"
contains "$TMP/output" 'Configured hooks: check-yaml shellcheck shfmt-check hadolint'
contains "$TMP/output" 'Recommendation: migrate repo URL from cloud-gov/pre-commit-templates to https://github.com/cloud-gov/caulking (rev: v3.4.0)'
contains "$TMP/output" 'Recommendation: upgrade ambient check-yaml/check-json to check-yaml-selfcontained/check-json-selfcontained'
contains "$TMP/output" 'Missing recommended hooks:'
contains "$TMP/output" 'end-of-file-fixer'
contains "$TMP/output" 'grype'
contains "$TMP/output" 'yamllint'

# Test init dry-run (stdout), refusal to overwrite without --force, symlink refusal,
# init --write creation, init --write --force overwrite, and doctor validation.
rm "$DETECT_REPO/.pre-commit-config.yaml"
expect 0 init --repo "$DETECT_REPO"
contains "$TMP/output" '# Generated by caulking.sh init'
contains "$TMP/output" '# Detected stacks: hygiene shell container python opentofu docs'
contains "$TMP/output" 'repo: https://github.com/cloud-gov/caulking'
contains "$TMP/output" 'rev: v3.4.0'
contains "$TMP/output" "args: ['--maxkb=500']"
[[ ! -e "$DETECT_REPO/.pre-commit-config.yaml" ]]

ln -s "$TMP/nonexistent-target" "$DETECT_REPO/.pre-commit-config.yaml"
expect 2 init --repo "$DETECT_REPO" --write --force
contains "$TMP/output" "refusing to write through symlink: $DETECT_REPO/.pre-commit-config.yaml"
rm "$DETECT_REPO/.pre-commit-config.yaml"

expect 0 init --repo "$DETECT_REPO" --write
contains "$TMP/output" "Wrote $DETECT_REPO/.pre-commit-config.yaml"
[[ -f "$DETECT_REPO/.pre-commit-config.yaml" ]]

expect 1 init --repo "$DETECT_REPO" --write
contains "$TMP/output" "config already exists: $DETECT_REPO/.pre-commit-config.yaml (use --force to overwrite)"

printf '# custom comment\n' >> "$DETECT_REPO/.pre-commit-config.yaml"
expect 0 init --repo "$DETECT_REPO" --write --force
if /usr/bin/grep -Fq '# custom comment' "$DETECT_REPO/.pre-commit-config.yaml"; then
  printf 'FAIL: init --write --force did not overwrite existing config\n' >&2
  exit 1
fi

expect 0 detect --repo "$DETECT_REPO"
contains "$TMP/output" 'Missing recommended hooks: none'

expect 0 doctor --repo "$DETECT_REPO"
no_installs

# Test --stack / --no-stack flags and interactive checkbox TUI on init and detect.
expect 2 init --repo "$DETECT_REPO" --stack unknown
expect 2 doctor --repo "$DETECT_REPO" --stack shell
expect 2 doctor --repo "$DETECT_REPO" --interactive

expect 0 init --repo "$DETECT_REPO" --stack ruby --no-stack python
contains "$TMP/output" '# Detected stacks: hygiene shell container ruby opentofu docs'
contains "$TMP/output" '- id: rubocop'
if /usr/bin/grep -Fq -- '- id: ruff-check' "$TMP/output"; then
  printf 'FAIL: --no-stack python did not remove ruff-check\n' >&2
  exit 1
fi

printf '3\n' | "$ROOT/caulking.sh" init --repo "$DETECT_REPO" --interactive > "$TMP/tui.stdout" 2> "$TMP/tui.stderr"
contains "$TMP/tui.stderr" '3. [x] python'
contains "$TMP/tui.stderr" '[detected]'
contains "$TMP/tui.stdout" '# Detected stacks: hygiene shell container opentofu docs'
if /usr/bin/grep -Fq -- '- id: ruff-check' "$TMP/tui.stdout"; then
  printf 'FAIL: TUI toggle 3 did not disable python stack\n' >&2
  exit 1
fi
checks=$((checks + 1))

printf 'j \n' | "$ROOT/caulking.sh" init --repo "$DETECT_REPO" --interactive > "$TMP/tui.stdout" 2> "$TMP/tui.stderr"
contains "$TMP/tui.stdout" '# Detected stacks: hygiene shell python opentofu docs'
if /usr/bin/grep -Fq -- '- id: hadolint' "$TMP/tui.stdout"; then
  printf 'FAIL: TUI j + Space did not disable container stack\n' >&2
  exit 1
fi
checks=$((checks + 1))

rm "$DETECT_REPO/.pre-commit-config.yaml"
actual=0
printf 'q' | "$ROOT/caulking.sh" init --repo "$DETECT_REPO" --interactive --write > "$TMP/tui.stdout" 2> "$TMP/tui.stderr" || actual=$?
[[ "$actual" == 1 ]]
contains "$TMP/tui.stderr" 'cancelled by user'
[[ ! -e "$DETECT_REPO/.pre-commit-config.yaml" ]]
checks=$((checks + 1))

printf '4\n' | "$ROOT/caulking.sh" detect --repo "$DETECT_REPO" --interactive --write > "$TMP/tui.stdout" 2> "$TMP/tui.stderr"
contains "$TMP/tui.stdout" 'Wrote '
contains "$DETECT_REPO/.pre-commit-config.yaml" '- id: golangci-lint'
checks=$((checks + 1))

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
  cp "$ROOT/scripts/lib.sh" "$ROOT/scripts/toolchain.sh" "$ROOT/scripts/detect.sh" "$TMP/app/scripts/"
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
  contains "$TMP/hook.output" 'hook helper is missing'
  mv "$TMP/stable/app.link" "$TMP/stable/app"
  # An application upgrade retargets opt without regenerating global hooks.
  cp -R "$TMP/app" "$TMP/app-next"
  rm "$TMP/stable/app"
  ln -s "$TMP/app-next" "$TMP/stable/app"
  rm -rf "$TMP/app"
  run_hook pre-commit 0
  mv "$REPO/.pre-commit-config.yaml" "$TMP/direct.config"
  ln -s "$TMP/missing.config" "$REPO/.pre-commit-config.yaml"
  : > "$FAKE_LOG"
  run_hook pre-commit 2
  contains "$TMP/hook.output" 'readable direct config'
  [[ ! -s "$FAKE_LOG" ]]
  mv "$TMP/direct.config" "$REPO/.pre-commit-config.yaml"
  mv "$FAKE_HOME/opt/shfmt" "$TMP/shfmt.opt"
  run_hook pre-commit 1
  contains "$TMP/hook.output" 'missing executable:'
  mv "$TMP/shfmt.opt" "$FAKE_HOME/opt/shfmt"
  # CAULKING_NO_TOOLCHAIN_PATH=1 retains the established pinned-runner path.
  CAULKING_NO_TOOLCHAIN_PATH=1 run_hook pre-commit 0
  contains "$FAKE_RUN" "args=run --config $REPO/.pre-commit-config.yaml --hook-stage pre-commit"
  no_installs
else
  printf 'SKIP: installed setup integration requires Bash >=4\n'
fi

export PATH="$ORIGINAL_PATH"
printf 'PASS: %s isolated toolchain CLI checks\n' "$checks"
