#!/usr/bin/env bash
set -euo pipefail

# shellcheck source=scripts/detect.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/detect.sh"

toolchain_usage() {
  printf '%s\n' \
    'Usage: caulking.sh {bootstrap|doctor|run|detect|init} [--repo PATH] ...' \
    'Profiles: baseline (gitleaks >=8.21.0, prek >=0.4.0, bash >=4),' \
    '          shell (shellcheck >=0.9.0, shfmt >=3.6.0),' \
    '          container (hadolint >=2.12.0),' \
    '          python (ruff >=0.4.0, mypy >=1.8.0, pyright >=1.1.350, bandit >=1.7.5, pip-audit >=2.7.0),' \
    '          go (go >=1.22.0, golangci-lint >=1.59.0, gosec >=2.18.0, govulncheck >=1.0.0),' \
    '          javascript (node >=20.0.0),' \
    '          ruby (ruby >=3.2.0, rubocop >=1.60.0),' \
    '          opentofu (opentofu >=1.6.0, tflint >=0.50.0),' \
    '          terraform (terraform >=1.5.0, tflint >=0.50.0),' \
    '          docs (yamllint >=1.35.0, yamlfmt >=0.13.0, actionlint >=1.7.0, zizmor >=1.0.0, markdownlint-cli >=0.39.0),' \
    '          security (semgrep >=1.50.0, osv-scanner >=1.7.0, syft >=1.0.0, grype >=0.74.0, checkov >=3.2.0).' \
    '          No default or implied profiles. Bundles live in brewfiles/<profile>.Brewfile.' \
    'Formulae are derived from hook IDs in REPO/.pre-commit-config.yaml or --profile.' \
    'bootstrap: macOS only; install missing formulae. --dry-run prints the plan.' \
    'doctor: check-only; exit 0 healthy, 1 missing/broken tools, 2 invalid input.' \
    'run: requires baseline and a direct REPO/.pre-commit-config.yaml; pins --config.' \
    'detect [-i|--interactive]: inspect repository files and audit .pre-commit-config.yaml coverage.' \
    'init [-i|--interactive] [-y|--yes] [--stack NAME] [--no-stack NAME] [--write] [--force]:' \
    '      generate recommended .pre-commit-config.yaml (stdout by default).' \
    'Internal: hook-run --repo ABS --stage pre-commit|pre-push reads .pre-commit-config.yaml,' \
    'checks dependencies and runs the pinned suite with stage-specific file selection.' \
    'Global setup: caulking setup --no-install (explicit; never performed by hooks).' \
    'Prefix/version probes have a fixed 5s timeout; only direct children are killed.' \
    'prek may provision project hook environments; success only describes that runner.' \
    'Toolchain-aware global hooks require explicit setup; global gitleaks stays separate.'
}

toolchain_error() {
  printf 'caulking: %s\n' "$*" >&2
}

toolchain_profile() {
  local profile="$1" existing
  case "$profile" in
    baseline | shell | container | python | go | javascript | ruby | opentofu | terraform | docs | security) ;;
    *)
      toolchain_error "unknown profile: $profile"
      return 2
      ;;
  esac
  for existing in ${profiles[@]+"${profiles[@]}"}; do
    [[ "$existing" != "$profile" ]] || return 0
  done
  profiles+=("$profile")
  profile_count=$((profile_count + 1))
}

toolchain_add_formula() {
  local item existing
  for item in "$@"; do
    for existing in ${formulae[@]+"${formulae[@]}"}; do
      [[ "$existing" != "$item" ]] || continue 2
    done
    formulae+=("$item")
  done
}

toolchain_add_dir() {
  local dir="$1" existing
  for existing in ${tool_dirs[@]+"${tool_dirs[@]}"}; do
    [[ "$existing" != "$dir" ]] || return 0
  done
  tool_dirs+=("$dir")
}

toolchain_hook_formula() {
  case "$1" in
    shellcheck) toolchain_add_formula shellcheck ;;
    shfmt | shfmt-check | shfmt-src) toolchain_add_formula shfmt ;;
    bash-syntax) toolchain_add_formula bash ;;
    hadolint) toolchain_add_formula hadolint ;;
    ruff | ruff-check | ruff-format | ruff-format-check) toolchain_add_formula ruff ;;
    mypy) toolchain_add_formula mypy ;;
    pyright) toolchain_add_formula pyright ;;
    bandit) toolchain_add_formula bandit ;;
    pip-audit) toolchain_add_formula pip-audit ;;
    go-fmt | go-vet | go-build | go-test | go-mod-tidy) toolchain_add_formula go ;;
    golangci-lint | golangci-lint-full) toolchain_add_formula golangci-lint ;;
    gosec) toolchain_add_formula gosec ;;
    govulncheck) toolchain_add_formula govulncheck ;;
    eslint | eslint-check | prettier | prettier-check | tsc | biome-check | biome-ci | npm-audit | yarn-audit | pnpm-audit | retire-js)
      toolchain_add_formula node
      ;;
    ruby-check | bundle-audit) toolchain_add_formula ruby ;;
    rubocop | rubocop-check) toolchain_add_formula ruby rubocop ;;
    tofu-fmt | tofu-validate) toolchain_add_formula opentofu ;;
    terraform-fmt | terraform-validate | terraform_fmt | terraform_validate)
      toolchain_add_formula terraform
      ;;
    tflint | terraform_tflint) toolchain_add_formula tflint ;;
    checkov | terraform_checkov) toolchain_add_formula checkov ;;
    yamllint) toolchain_add_formula yamllint ;;
    yamlfmt | yamlfmt-check) toolchain_add_formula yamlfmt ;;
    actionlint) toolchain_add_formula actionlint ;;
    zizmor) toolchain_add_formula zizmor ;;
    markdownlint | markdownlint-check) toolchain_add_formula markdownlint-cli ;;
    semgrep | semgrep-ci) toolchain_add_formula semgrep ;;
    osv-scanner | osv-scanner-lockfile) toolchain_add_formula osv-scanner ;;
    syft) toolchain_add_formula syft ;;
    grype | grype-sbom) toolchain_add_formula grype ;;
    *) return 0 ;;
  esac
}

toolchain_validate_hook_id() {
  local raw="$1"
  raw="${raw#"${raw%%[![:space:]]*}"}"
  raw="${raw%"${raw##*[![:space:]]}"}"
  if [[ "$raw" == \"*\" && "$raw" == *\" && "${#raw}" -ge 2 ]]; then
    raw="${raw#\"}"
    raw="${raw%\"}"
  elif [[ "$raw" == \'*\' && "$raw" == *\' && "${#raw}" -ge 2 ]]; then
    raw="${raw#\'}"
    raw="${raw%\'}"
  fi
  if [[ ! "$raw" =~ ^[A-Za-z0-9][A-Za-z0-9_.-]*$ ]]; then
    toolchain_error "invalid hook id in config: $raw"
    return 2
  fi
  config_hooks+=("$raw")
}

toolchain_config_file() {
  local file="$1" bytes line rest raw_repo count=0
  [[ -e "$file" || -L "$file" ]] || return 0
  if [[ ! -f "$file" || ! -r "$file" ]]; then
    toolchain_error "readable direct config required: $file"
    return 2
  fi
  bytes="$(LC_ALL=C wc -c < "$file")" || return 2
  if ((bytes > 65536)); then
    toolchain_error 'config file exceeds 64 KiB'
    return 2
  fi
  if IFS= read -r -d '' line < "$file"; then
    toolchain_error 'config file contains a NUL byte'
    return 2
  fi
  while IFS= read -r line || [[ -n "$line" ]]; do
    count=$((count + 1))
    if ((count > 1024)); then
      toolchain_error 'config file exceeds 1024 lines'
      return 2
    fi
    line="${line%%#*}"
    if [[ "$line" =~ ^[[:space:]]*(-[[:space:]]*)?repo:[[:space:]]*([^[:space:]]+)[[:space:]]*$ ]]; then
      raw_repo="${BASH_REMATCH[2]}"
      if [[ "$raw_repo" == \"*\" && "$raw_repo" == *\" && "${#raw_repo}" -ge 2 ]]; then
        raw_repo="${raw_repo#\"}"
        raw_repo="${raw_repo%\"}"
      elif [[ "$raw_repo" == \'*\' && "$raw_repo" == *\' && "${#raw_repo}" -ge 2 ]]; then
        raw_repo="${raw_repo#\'}"
        raw_repo="${raw_repo%\'}"
      fi
      config_repos+=("$raw_repo")
      continue
    fi
    if [[ "$line" =~ ^[[:space:]]*(-[[:space:]]*)?id:([[:space:]]+(.*))?$ ]]; then
      toolchain_validate_hook_id "${BASH_REMATCH[3]:-}" || return 2
      continue
    fi
    rest="$line"
    while [[ "$rest" =~ [{,][[:space:]]*id:[[:space:]]*([^,}]*) ]]; do
      toolchain_validate_hook_id "${BASH_REMATCH[1]}" || return 2
      rest="${rest#*"${BASH_REMATCH[0]}"}"
    done
  done < "$file"
  config_seen=1
  toolchain_profile baseline || return 2
}

toolchain_brew() {
  local candidate
  candidate="$(command -v brew || true)"
  if [[ "$candidate" == /* && -x "$candidate" && ! -d "$candidate" ]]; then
    brew_bin="$candidate"
    return 0
  fi
  for candidate in /opt/homebrew/bin/brew /usr/local/bin/brew; do
    if [[ -x "$candidate" && ! -d "$candidate" ]]; then
      brew_bin="$candidate"
      return 0
    fi
  done
  toolchain_error 'Homebrew is missing; install Homebrew manually, then retry.'
  return 1
}

toolchain_brew_call() {
  HOMEBREW_NO_AUTO_UPDATE=1 HOMEBREW_NO_INSTALL_UPGRADE=1 \
    HOMEBREW_NO_INSTALL_CLEANUP=1 "$brew_bin" "$@"
}

toolchain_probe() {
  (
    # Subshell-owned variables remain visible to Bash 3.2 EXIT traps after the
    # function scope unwinds; function-local variables would not.
    child=''
    watchdog=''
    status=0
    # Subshell-local traps never replace the caller's traps. The watchdog bounds
    # the direct child only; a CLI that spawns descendants may leave them running.
    scratch="$(mktemp -d "${TMPDIR:-/tmp}/caulking-probe.XXXXXX")" || exit 1
    trap '[[ -z "$child" ]] || kill -KILL "$child" 2> /dev/null || true
    [[ -z "$watchdog" ]] || kill "$watchdog" 2> /dev/null || true
    [[ -z "$child" ]] || wait "$child" 2> /dev/null || true
    [[ -z "$watchdog" ]] || wait "$watchdog" 2> /dev/null || true
    rm -rf "$scratch"' EXIT
    trap 'exit 1' HUP INT TERM
    SEMGREP_SEND_METRICS=off SEMGREP_ENABLE_VERSION_CHECK=0 \
      SYFT_CHECK_FOR_APP_UPDATE=false GRYPE_CHECK_FOR_APP_UPDATE=false \
      CHECKPOINT_DISABLE=1 "$@" > "$scratch/output" 2>&1 &
    child=$!
    (
      sleep 5 &
      timer=$!
      trap 'kill "$timer" 2> /dev/null || true; wait "$timer" 2> /dev/null || true' EXIT
      trap 'exit 0' HUP INT TERM
      wait "$timer"
      : > "$scratch/timeout"
      kill -KILL "$child" 2> /dev/null || true
    ) &
    watchdog=$!
    wait "$child" 2> /dev/null || status=$?
    child=''
    kill "$watchdog" 2> /dev/null || true
    wait "$watchdog" 2> /dev/null || true
    watchdog=''
    if [[ -e "$scratch/timeout" ]]; then
      toolchain_error "probe timed out after 5s: $*"
      exit 1
    fi
    cat "$scratch/output"
    exit "$status"
  )
}

toolchain_prefix() {
  # Conventional bin/brew installations need no brew invocation at all.
  # For other layouts, bare --prefix is Homebrew's shell-only fast path:
  # See Homebrew's Library/Homebrew/brew.sh and formula_path.sh on main;
  # bare --prefix exits before Ruby setup (no formula argument).
  if [[ "$brew_bin" == */bin/brew ]]; then
    brew_prefix="${brew_bin%/bin/brew}"
  else
    brew_prefix="$(toolchain_probe env HOMEBREW_NO_AUTO_UPDATE=1 \
      HOMEBREW_NO_INSTALL_UPGRADE=1 HOMEBREW_NO_INSTALL_CLEANUP=1 \
      "$brew_bin" --prefix)" || return 1
  fi
  if [[ "$brew_prefix" != /* || "$brew_prefix" == *$'\n'* || "$brew_prefix" == *:* ]]; then
    toolchain_error 'invalid Homebrew prefix'
    return 1
  fi
}

toolchain_present() {
  local opt="$brew_prefix/opt/$1" cellar="$brew_prefix/Cellar/$1" caskroom="$brew_prefix/Caskroom/$1"
  # A broken opt link or Cellar/Caskroom entry still counts as installed: never reinstall.
  if [[ "$1" == tflint ]]; then
    [[ -e "$opt" || -L "$opt" || -e "$cellar" || -L "$cellar" || -e "$caskroom" || -L "$caskroom" ]]
    return
  fi
  [[ -e "$opt" || -L "$opt" || -e "$cellar" || -L "$cellar" ]]
}

toolchain_check() {
  local formula="$1" prefix bin_dir binary_name executable probe_arg output
  local major minor patch suffix min_version='' min_major=0 min_minor=0 min_patch=0
  if ! toolchain_present "$formula"; then
    toolchain_error "missing Homebrew formula: $formula"
    return 1
  fi
  prefix="$brew_prefix/opt/$formula"
  binary_name="$formula"
  [[ "$formula" != opentofu ]] || binary_name=tofu
  [[ "$formula" != markdownlint-cli ]] || binary_name=markdownlint
  if [[ "$formula" == tflint && ! -x "$prefix/bin/tflint" ]] &&
    [[ -e "$brew_prefix/Caskroom/tflint" || -L "$brew_prefix/Caskroom/tflint" ]]; then
    bin_dir="$brew_prefix/bin"
  else
    bin_dir="$prefix/bin"
  fi
  executable="$bin_dir/$binary_name"
  if [[ ! -x "$executable" || -d "$executable" ]]; then
    toolchain_error "missing executable: $executable"
    return 1
  fi
  if [[ "$formula" == gitleaks || "$formula" == go ]]; then
    probe_arg=version
  else
    probe_arg=--version
  fi
  output="$(toolchain_probe "$executable" "$probe_arg")" || {
    toolchain_error "version check failed: $executable"
    return 1
  }
  if [[ ! "$output" =~ ([0-9]{1,6})\.([0-9]{1,6})(\.([0-9]{1,6}))?([-+][^[:space:]]*)? ]]; then
    toolchain_error "unrecognized version from $executable: $output"
    return 1
  fi
  major="${BASH_REMATCH[1]}"
  minor="${BASH_REMATCH[2]}"
  patch="${BASH_REMATCH[4]:-0}"
  suffix="${BASH_REMATCH[5]:-}"
  if [[ "$formula" == govulncheck && "$output" =~ govulncheck@v?([0-9]{1,6})\.([0-9]{1,6})(\.([0-9]{1,6}))?([-+][^[:space:]]*)? ]]; then
    major="${BASH_REMATCH[1]}"
    minor="${BASH_REMATCH[2]}"
    patch="${BASH_REMATCH[4]:-0}"
    suffix="${BASH_REMATCH[5]:-}"
  fi
  if [[ "$formula" == gitleaks ]]; then
    if [[ ! "$output" =~ (^|[[:space:]])v?([0-9]{1,6})\.([0-9]{1,6})\.([0-9]{1,6})([-+][^[:space:]]*)?($|[[:space:]]) ]]; then
      toolchain_error "unrecognized gitleaks semantic version: $output"
      return 1
    fi
    major="${BASH_REMATCH[2]}"
    minor="${BASH_REMATCH[3]}"
    patch="${BASH_REMATCH[4]}"
    suffix="${BASH_REMATCH[5]:-}"
    if ((10#$major < 8 || (10#$major == 8 && 10#$minor < 21))) ||
      { ((10#$major == 8 && 10#$minor == 21 && 10#$patch == 0)) && [[ "$suffix" == -* ]]; }; then
      toolchain_error "gitleaks >=8.21.0 required: $output"
      return 1
    fi
  elif [[ "$formula" == bash ]]; then
    if ((10#$major < 4)); then
      toolchain_error "Homebrew bash >=4 required: $output"
      return 1
    fi
  else
    case "$formula" in
      prek)
        min_version=0.4.0
        [[ -z "${RUNTIME_RUNNER:-}" ]] || min_version=0.3.0
        ;;
      shellcheck) min_version=0.9.0 ;;
      shfmt) min_version=3.6.0 ;;
      hadolint) min_version=2.12.0 ;;
      ruff) min_version=0.4.0 ;;
      mypy) min_version=1.8.0 ;;
      pyright) min_version=1.1.350 ;;
      bandit) min_version=1.7.5 ;;
      pip-audit) min_version=2.7.0 ;;
      go) min_version=1.22.0 ;;
      golangci-lint) min_version=1.59.0 ;;
      gosec) min_version=2.18.0 ;;
      govulncheck) min_version=1.0.0 ;;
      node) min_version=20.0.0 ;;
      ruby) min_version=3.2.0 ;;
      rubocop) min_version=1.60.0 ;;
      opentofu) min_version=1.6.0 ;;
      terraform) min_version=1.5.0 ;;
      tflint) min_version=0.50.0 ;;
      yamllint) min_version=1.35.0 ;;
      yamlfmt) min_version=0.13.0 ;;
      actionlint) min_version=1.7.0 ;;
      zizmor) min_version=1.0.0 ;;
      markdownlint-cli) min_version=0.39.0 ;;
      semgrep) min_version=1.50.0 ;;
      osv-scanner) min_version=1.7.0 ;;
      syft) min_version=1.0.0 ;;
      grype) min_version=0.74.0 ;;
      checkov) min_version=3.2.0 ;;
    esac
    if [[ -n "$min_version" ]]; then
      min_major="${min_version%%.*}"
      min_minor="${min_version#*.}"
      min_patch="${min_minor#*.}"
      min_minor="${min_minor%%.*}"
      if ((10#$major < 10#$min_major)) ||
        ((10#$major == 10#$min_major && 10#$minor < 10#$min_minor)) ||
        ((10#$major == 10#$min_major && 10#$minor == 10#$min_minor && 10#$patch < 10#$min_patch)) ||
        { ((10#$major == 10#$min_major && 10#$minor == 10#$min_minor && 10#$patch == 10#$min_patch)) && [[ "$suffix" == -* ]]; }; then
        toolchain_error "$formula >=${min_version} required: $output"
        return 1
      fi
    fi
  fi
  printf 'OK %s: %s (%s)\n' "$formula" "$output" "$executable"
  toolchain_add_dir "$bin_dir"
  [[ "$formula" != prek ]] || runner="$executable"
}

toolchain_install() {
  local formula="$1" spec="$1"
  case "$formula" in
    terraform) spec=hashicorp/tap/terraform ;;
    tflint) spec='--cask terraform-linters/tap/tflint' ;;
  esac
  if ((dry_run)); then
    printf 'Would install Homebrew formula: %s\n' "$spec"
    return 0
  fi
  printf 'Installing Homebrew formula: %s\n' "$spec"
  if [[ "$formula" == tflint ]]; then
    toolchain_brew_call install --cask terraform-linters/tap/tflint
  else
    toolchain_brew_call install "$spec"
  fi
}

toolchain_main() {
  local action="${1:-}" repo=. repo_seen=0 dry_run=0 write_config=0 force_write=0 interactive=0 assume_yes=0
  local profile formula dir hook_stage='' hook_id=''
  local brew_bin='' brew_prefix='' runner='' scoped_path='' failed=0 has_baseline=0 profile_count=0 config_seen=0
  local git_bin='' runtime_file='' caulking_root='' brewfile='' RUNTIME_GIT='' RUNTIME_RUNNER=''
  # These arrays are dynamically scoped to the helpers; Bash 3 can launch bootstrap.
  local -a profiles=() formulae=() tool_dirs=() config_hooks=() config_repos=() stack_overrides=()
  case "$action" in
    -h | --help)
      toolchain_usage
      return 0
      ;;
    bootstrap | doctor | run | hook-run | detect | init) shift ;;
    *)
      toolchain_usage >&2
      return 2
      ;;
  esac
  while (($#)); do
    case "$1" in
      --repo)
        if (($# < 2)) || [[ -z "$2" || "$2" == --* ]] || ((repo_seen)); then
          toolchain_error '--repo requires one path and cannot be repeated'
          return 2
        fi
        repo="$2"
        repo_seen=1
        shift 2
        ;;
      --profile)
        if [[ "$action" == hook-run ]]; then
          toolchain_error 'hook-run reads hooks only from .pre-commit-config.yaml'
          return 2
        fi
        if [[ "$action" == detect || "$action" == init ]]; then
          toolchain_error "--profile is not supported for $action"
          return 2
        fi
        if (($# < 2)); then
          toolchain_error '--profile requires a name'
          return 2
        fi
        toolchain_profile "$2" || return 2
        shift 2
        ;;
      --stage)
        if [[ "$action" != hook-run || -n "$hook_stage" ]] || (($# < 2)); then
          toolchain_error '--stage is required once for hook-run only'
          return 2
        fi
        case "$2" in
          pre-commit | pre-push) hook_stage="$2" ;;
          *)
            toolchain_error "unsupported hook stage: $2"
            return 2
            ;;
        esac
        shift 2
        ;;
      --dry-run)
        if [[ "$action" != bootstrap ]] || ((dry_run)); then
          toolchain_error '--dry-run is valid once, for bootstrap only'
          return 2
        fi
        dry_run=1
        shift
        ;;
      --write)
        if [[ "$action" != init && "$action" != detect ]] || ((write_config)); then
          toolchain_error '--write is valid once, for init only'
          return 2
        fi
        write_config=1
        shift
        ;;
      --force)
        if [[ "$action" != init && "$action" != detect ]] || ((force_write)); then
          toolchain_error '--force is valid once, for init only'
          return 2
        fi
        force_write=1
        shift
        ;;
      -i | --interactive)
        if [[ "$action" != init && "$action" != detect ]] || ((interactive)); then
          toolchain_error '--interactive is valid once, for init or detect only'
          return 2
        fi
        interactive=1
        shift
        ;;
      -y | --yes)
        if [[ "$action" != init && "$action" != detect ]] || ((assume_yes)); then
          toolchain_error '--yes is valid once, for init or detect only'
          return 2
        fi
        assume_yes=1
        shift
        ;;
      --stack)
        if [[ "$action" != init && "$action" != detect ]] || (($# < 2)); then
          toolchain_error '--stack requires a stack name and is valid for init or detect only'
          return 2
        fi
        detect_validate_stack_name "$2" || return 2
        stack_overrides+=("add:$2")
        shift 2
        ;;
      --no-stack)
        if [[ "$action" != init && "$action" != detect ]] || (($# < 2)); then
          toolchain_error '--no-stack requires a stack name and is valid for init or detect only'
          return 2
        fi
        detect_validate_stack_name "$2" || return 2
        stack_overrides+=("del:$2")
        shift 2
        ;;
      *)
        toolchain_error "unsupported argument: $1"
        return 2
        ;;
    esac
  done
  if [[ "$action" == detect ]] && ((interactive == 0 && (write_config || force_write))); then
    toolchain_error '--write and --force are valid for init (or detect --interactive) only'
    return 2
  fi
  if ((force_write)) && ((write_config == 0)); then
    toolchain_error '--force requires --write'
    return 2
  fi
  if [[ "$action" == hook-run ]] && [[ "$repo" != /* || "$repo_seen" != 1 || -z "$hook_stage" ]]; then
    toolchain_error 'hook-run requires --repo ABS and --stage pre-commit|pre-push'
    return 2
  fi
  repo="$(cd -- "$repo" && pwd -P)" || {
    toolchain_error 'repository path must be an accessible directory'
    return 2
  }
  if [[ "$action" == detect || "$action" == init ]]; then
    toolchain_detect_or_init "$action" "$repo" "$write_config" "$force_write" "$interactive" "$assume_yes" ${stack_overrides[@]+"${stack_overrides[@]}"}
    return $?
  fi
  if [[ "$action" == hook-run ]] && [[ ! -f "$repo/.pre-commit-config.yaml" || ! -r "$repo/.pre-commit-config.yaml" ]]; then
    toolchain_error "hook-run requires a readable direct config: $repo/.pre-commit-config.yaml"
    return 2
  fi
  toolchain_config_file "$repo/.pre-commit-config.yaml" || return 2
  if ((profile_count == 0 && config_seen == 0)); then
    toolchain_error 'provide .pre-commit-config.yaml in --repo or select at least one --profile'
    return 2
  fi
  for profile in ${profiles[@]+"${profiles[@]}"}; do
    case "$profile" in
      baseline)
        toolchain_add_formula gitleaks prek bash
        has_baseline=1
        ;;
      shell) toolchain_add_formula shellcheck shfmt ;;
      container) toolchain_add_formula hadolint ;;
      python) toolchain_add_formula ruff mypy pyright bandit pip-audit ;;
      go) toolchain_add_formula go golangci-lint gosec govulncheck ;;
      javascript) toolchain_add_formula node ;;
      ruby) toolchain_add_formula ruby rubocop ;;
      opentofu) toolchain_add_formula opentofu tflint ;;
      terraform) toolchain_add_formula terraform tflint ;;
      docs) toolchain_add_formula yamllint yamlfmt actionlint zizmor markdownlint-cli ;;
      security) toolchain_add_formula semgrep osv-scanner syft grype checkov ;;
    esac
  done
  for hook_id in ${config_hooks[@]+"${config_hooks[@]}"}; do
    toolchain_hook_formula "$hook_id"
  done
  if [[ "$action" == run || "$action" == hook-run ]] && ((has_baseline == 0)); then
    toolchain_error "$action requires the explicit baseline profile (prek runner)"
    return 2
  fi
  if [[ "$action" == run || "$action" == hook-run ]] && [[ ! -f "$repo/.pre-commit-config.yaml" || ! -r "$repo/.pre-commit-config.yaml" ]]; then
    toolchain_error "$action requires a readable direct config: $repo/.pre-commit-config.yaml"
    return 2
  fi
  caulking_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
  if [[ "$action" == run ]]; then
    runtime_file="$caulking_root/scripts/package-runtime.sh"
    if [[ -f "$runtime_file" ]]; then
      # Only the trusted installed application supplies this fixed binding.
      # shellcheck source=/dev/null
      source "$runtime_file"
      git_bin="$RUNTIME_GIT"
    else
      # Source execution resolves normal PATH, never inherited CAULKING_GIT.
      git_bin="$(type -P git || true)"
    fi
  elif [[ "$action" == hook-run ]]; then
    git_bin="${CAULKING_GIT:-}"
  fi
  if [[ "$action" == run || "$action" == hook-run ]] &&
    [[ "$git_bin" != /* || ! -x "$git_bin" || -d "$git_bin" || "$git_bin" == *:* ]]; then
    toolchain_error "$action requires an absolute Git executable"
    return 2
  fi
  if [[ "$action" == bootstrap && "$(uname -s)" != Darwin ]]; then
    toolchain_error 'bootstrap is supported only on macOS'
    return 1
  fi
  toolchain_brew || return 1
  toolchain_prefix || return 1
  if [[ "$action" == bootstrap || "$action" == doctor || ! -f "$caulking_root/scripts/package-runtime.sh" || -d "$caulking_root/brewfiles" ]]; then
    for profile in baseline shell container python go javascript ruby opentofu terraform docs security; do
      brewfile="$caulking_root/brewfiles/${profile}.Brewfile"
      if [[ ! -f "$brewfile" || ! -r "$brewfile" ]]; then
        toolchain_error "missing profile Brewfile: $brewfile"
        return 1
      fi
    done
  fi
  for formula in "${formulae[@]}"; do
    if [[ "$action" == bootstrap ]]; then
      if ! toolchain_present "$formula"; then
        if ((dry_run)); then
          toolchain_install "$formula"
          continue
        fi
        if ! toolchain_install "$formula"; then
          toolchain_error "install failed: $formula; stopping"
          return 1
        fi
      fi
    fi
    toolchain_check "$formula" || failed=1
    # A broken installed formula is not implicitly upgraded or reinstalled.
    if [[ "$action" == bootstrap ]] && ((failed)); then
      return 1
    fi
  done
  ((failed == 0)) || return 1
  [[ "$action" == run || "$action" == hook-run ]] || return 0
  for dir in "${tool_dirs[@]}"; do
    scoped_path="${scoped_path:+$scoped_path:}$dir"
  done
  # System utilities remain available; ambient package/tool paths do not.
  scoped_path="$scoped_path:${git_bin%/*}:/usr/bin:/bin:/usr/sbin:/sbin"
  if [[ "$action" == hook-run ]]; then
    (
      cd -- "$repo"
      PATH="$scoped_path" "$runner" run --hook-stage "$hook_stage" --show-diff-on-failure --config "$repo/.pre-commit-config.yaml"
    )
    return $?
  fi
  (
    cd -- "$repo"
    PATH="$scoped_path" "$runner" run --all-files --config "$repo/.pre-commit-config.yaml"
  )
}
