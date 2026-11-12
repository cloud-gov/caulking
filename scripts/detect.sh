#!/usr/bin/env bash
set -euo pipefail

detect_add_stack() {
  local item existing
  for item in "$@"; do
    for existing in ${detected_stacks[@]+"${detected_stacks[@]}"}; do
      [[ "$existing" != "$item" ]] || continue 2
    done
    detected_stacks+=("$item")
  done
}

detect_add_profile() {
  local item existing
  for item in "$@"; do
    for existing in ${recommended_profiles[@]+"${recommended_profiles[@]}"}; do
      [[ "$existing" != "$item" ]] || continue 2
    done
    recommended_profiles+=("$item")
  done
}

detect_add_hook() {
  local item existing
  for item in "$@"; do
    for existing in ${recommended_hooks[@]+"${recommended_hooks[@]}"}; do
      [[ "$existing" != "$item" ]] || continue 2
    done
    recommended_hooks+=("$item")
  done
}

detect_validate_stack_name() {
  case "$1" in
    shell | container | python | go | javascript | ruby | opentofu | terraform | docs) return 0 ;;
    *)
      toolchain_error "unknown stack: $1 (expected shell, container, python, go, javascript, ruby, opentofu, terraform, or docs)"
      return 2
      ;;
  esac
}

detect_has_configured_hook() {
  local needle="$1" existing
  for existing in ${config_hooks[@]+"${config_hooks[@]}"}; do
    [[ "$existing" != "$needle" ]] || return 0
  done
  return 1
}

detect_hook_satisfied() {
  local hook="$1"
  if detect_has_configured_hook "$hook"; then
    return 0
  fi
  case "$hook" in
    shfmt-check) detect_has_configured_hook shfmt && return 0 ;;
    markdownlint-check) detect_has_configured_hook markdownlint && return 0 ;;
    gosec) detect_has_configured_hook gosec-selfcontained && return 0 ;;
    govulncheck) detect_has_configured_hook govulncheck-selfcontained && return 0 ;;
  esac
  return 1
}

detect_scan_file() {
  local repo="$1" rel="$2" base first_line=''
  rel="${rel#./}"
  [[ -n "$rel" ]] || return 0
  if [[ "$rel" =~ (^|/)(node_modules|\.venv|venv|vendor|\.git|fixtures|testdata|examples)/ ]]; then
    return 0
  fi
  base="${rel##*/}"

  case "$rel" in
    .github/workflows/*.yml | .github/workflows/*.yaml)
      has_gha=1
      has_yaml=1
      ;;
  esac

  case "$base" in
    *.sh | *.bash)
      has_shell=1
      ;;
    Dockerfile | Containerfile | Dockerfile.* | *.dockerfile)
      has_container=1
      ;;
    pyproject.toml | requirements*.txt | setup.py | Pipfile | *.py)
      has_python=1
      ;;
    go.mod | *.go)
      has_go=1
      ;;
    package.json | *.js | *.jsx)
      has_js=1
      ;;
    tsconfig.json | *.ts | *.tsx)
      has_js=1
      has_ts=1
      ;;
    biome.json | biome.jsonc)
      has_biome=1
      ;;
    pnpm-lock.yaml)
      has_pnpm_lock=1
      ;;
    yarn.lock)
      has_yarn_lock=1
      ;;
    Gemfile | *.gemspec | Rakefile | inspec.yml | *.rb)
      has_ruby=1
      ;;
    Gemfile.lock)
      has_gemfile_lock=1
      ;;
    *.tf)
      has_tf=1
      ;;
    *.yml | *.yaml)
      has_yaml=1
      ;;
    *.md)
      has_md=1
      ;;
  esac

  if ((has_shell == 0)) && [[ -f "$repo/$rel" && ! -L "$repo/$rel" ]] &&
    [[ "$base" != *.* || -x "$repo/$rel" ]]; then
    first_line="$(LC_ALL=C head -n 1 "$repo/$rel" 2> /dev/null || true)"
    if [[ "$first_line" =~ ^#!.*(/|[[:space:]])(ba)?sh([[:space:]]|$) ]]; then
      has_shell=1
    fi
  fi
}

detect_scan_files() {
  local repo="$1" rel='' file_count=0 git_count=0

  has_shell=0
  has_container=0
  has_python=0
  has_go=0
  has_js=0
  has_ts=0
  has_biome=0
  has_pnpm_lock=0
  has_yarn_lock=0
  has_ruby=0
  has_gemfile_lock=0
  has_tf=0
  has_yaml=0
  has_gha=0
  has_md=0

  if command -v git > /dev/null 2>&1 &&
    git -C "$repo" rev-parse --is-inside-work-tree > /dev/null 2>&1; then
    while IFS= read -r -d '' rel; do
      git_count=$((git_count + 1))
      detect_scan_file "$repo" "$rel"
      if ((git_count >= 10000)); then
        break
      fi
    done < <(git -C "$repo" ls-files -z 2> /dev/null)
  fi

  if ((git_count == 0)); then
    while IFS= read -r -d '' rel; do
      file_count=$((file_count + 1))
      detect_scan_file "$repo" "$rel"
      if ((file_count >= 10000)); then
        break
      fi
    done < <(cd "$repo" && find . -maxdepth 3 \( -type f -o -type l \) -print0 2> /dev/null)
  fi

  auto_shell="$has_shell"
  auto_container="$has_container"
  auto_python="$has_python"
  auto_go="$has_go"
  auto_javascript="$has_js"
  auto_ruby="$has_ruby"
  auto_opentofu=0
  auto_terraform=0
  if ((has_tf)); then
    if [[ -f "$repo/.pre-commit-config.yaml" && ! -L "$repo/.pre-commit-config.yaml" && -r "$repo/.pre-commit-config.yaml" ]] &&
      /usr/bin/grep -Eq 'terraform[-_]fmt' "$repo/.pre-commit-config.yaml"; then
      auto_terraform=1
    else
      auto_opentofu=1
    fi
  fi
  auto_docs=0
  if ((has_yaml || has_gha || has_md)); then
    auto_docs=1
  fi

  sel_shell="$auto_shell"
  sel_container="$auto_container"
  sel_python="$auto_python"
  sel_go="$auto_go"
  sel_javascript="$auto_javascript"
  sel_ruby="$auto_ruby"
  sel_opentofu="$auto_opentofu"
  sel_terraform="$auto_terraform"
  sel_docs="$auto_docs"
}

detect_set_stack_state() {
  local stack="$1" val="$2"
  case "$stack" in
    shell) sel_shell="$val" ;;
    container) sel_container="$val" ;;
    python) sel_python="$val" ;;
    go) sel_go="$val" ;;
    javascript) sel_javascript="$val" ;;
    ruby) sel_ruby="$val" ;;
    opentofu) sel_opentofu="$val" ;;
    terraform) sel_terraform="$val" ;;
    docs) sel_docs="$val" ;;
  esac
}

detect_get_stack_state() {
  case "$1" in
    shell) printf '%s' "$sel_shell" ;;
    container) printf '%s' "$sel_container" ;;
    python) printf '%s' "$sel_python" ;;
    go) printf '%s' "$sel_go" ;;
    javascript) printf '%s' "$sel_javascript" ;;
    ruby) printf '%s' "$sel_ruby" ;;
    opentofu) printf '%s' "$sel_opentofu" ;;
    terraform) printf '%s' "$sel_terraform" ;;
    docs) printf '%s' "$sel_docs" ;;
  esac
}

detect_get_auto_state() {
  case "$1" in
    shell) printf '%s' "$auto_shell" ;;
    container) printf '%s' "$auto_container" ;;
    python) printf '%s' "$auto_python" ;;
    go) printf '%s' "$auto_go" ;;
    javascript) printf '%s' "$auto_javascript" ;;
    ruby) printf '%s' "$auto_ruby" ;;
    opentofu) printf '%s' "$auto_opentofu" ;;
    terraform) printf '%s' "$auto_terraform" ;;
    docs) printf '%s' "$auto_docs" ;;
  esac
}

detect_apply_stack_overrides() {
  local mod action_type stack_name
  for mod in "$@"; do
    action_type="${mod%%:*}"
    stack_name="${mod#*:}"
    if [[ "$action_type" == add ]]; then
      detect_set_stack_state "$stack_name" 1
    else
      detect_set_stack_state "$stack_name" 0
    fi
  done
}

detect_build_recommendations() {
  detected_stacks=()
  recommended_profiles=()
  recommended_hooks=()

  detect_add_stack hygiene
  detect_add_profile baseline
  detect_add_hook \
    check-merge-conflict \
    check-added-large-files \
    trailing-whitespace \
    end-of-file-fixer \
    check-yaml-selfcontained \
    check-json-selfcontained \
    check-gsa-email

  if ((sel_shell)); then
    detect_add_stack shell
    detect_add_profile shell
    detect_add_hook shellcheck shfmt-check
  fi

  if ((sel_container)); then
    detect_add_stack container
    detect_add_profile container security
    detect_add_hook hadolint grype
  fi

  if ((sel_python)); then
    detect_add_stack python
    detect_add_profile python
    detect_add_hook ruff-check ruff-format mypy bandit pip-audit
  fi

  if ((sel_go)); then
    detect_add_stack go
    detect_add_profile go
    detect_add_hook go-fmt go-vet golangci-lint gosec govulncheck
  fi

  if ((sel_javascript)); then
    detect_add_stack javascript
    detect_add_profile javascript security
    if ((has_biome)); then
      detect_add_hook biome-check
    else
      detect_add_hook eslint prettier
    fi
    if ((has_ts)); then
      detect_add_hook tsc
    fi
    detect_add_hook semgrep
    if ((has_pnpm_lock)); then
      detect_add_hook pnpm-audit
    elif ((has_yarn_lock)); then
      detect_add_hook yarn-audit
    else
      detect_add_hook npm-audit
    fi
  fi

  if ((sel_ruby)); then
    detect_add_stack ruby
    detect_add_profile ruby security
    detect_add_hook ruby-check rubocop semgrep
    if ((has_gemfile_lock)); then
      detect_add_hook osv-scanner-lockfile
    fi
  fi

  if ((sel_opentofu)); then
    detect_add_stack opentofu
    detect_add_profile opentofu security
    detect_add_hook tofu-fmt tofu-validate tflint semgrep osv-scanner
  fi

  if ((sel_terraform)); then
    detect_add_stack terraform
    detect_add_profile terraform security
    detect_add_hook terraform-fmt terraform-validate tflint semgrep osv-scanner
  fi

  if ((sel_docs)); then
    detect_add_stack docs
    detect_add_profile docs
    if ((has_yaml || (has_yaml == 0 && has_gha == 0 && has_md == 0))); then
      detect_add_hook yamllint
    fi
    if ((has_gha)); then
      detect_add_hook actionlint zizmor
    fi
    if ((has_md || (has_yaml == 0 && has_gha == 0 && has_md == 0))); then
      detect_add_hook markdownlint-check
    fi
  fi
}

toolchain_tui_render() {
  local cursor="$1" idx=0 stack desc state auto_state mark pointer badge
  local -a tui_stacks=(shell container python go javascript ruby opentofu terraform docs)
  local -a tui_descs=(
    'shellcheck, shfmt-check'
    'hadolint, grype'
    'ruff-check, ruff-format, mypy, bandit, pip-audit'
    'go-fmt, go-vet, golangci-lint, gosec, govulncheck'
    'eslint/prettier or biome-check, tsc, semgrep, npm/yarn/pnpm-audit'
    'ruby-check, rubocop, semgrep, osv-scanner-lockfile'
    'tofu-fmt, tofu-validate, tflint, semgrep, osv-scanner'
    'terraform-fmt, terraform-validate, tflint, semgrep, osv-scanner'
    'yamllint, actionlint, zizmor, markdownlint-check'
  )

  printf 'Caulking Interactive Stack Selector (baseline hygiene is always included)\n' >&2
  printf 'Use Up/Down or j/k to move, Space or 1-9 to toggle, a=all, n=none, Enter=confirm, q=quit:\n' >&2
  for idx in 0 1 2 3 4 5 6 7 8; do
    stack="${tui_stacks[$idx]}"
    desc="${tui_descs[$idx]}"
    state="$(detect_get_stack_state "$stack")"
    auto_state="$(detect_get_auto_state "$stack")"
    mark=' '
    [[ "$state" != 1 ]] || mark='x'
    pointer=' '
    ((idx != cursor)) || pointer='>'
    badge=''
    [[ "$auto_state" != 1 ]] || badge=' [detected]'
    printf ' %s %d. [%s] %-10s (%s)%s\n' "$pointer" "$((idx + 1))" "$mark" "$stack" "$desc" "$badge" >&2
  done
}

toolchain_tui_select_stacks() {
  local cursor=0 key='' rest='' target_stack='' cur_val=0
  local -a tui_stacks=(shell container python go javascript ruby opentofu terraform docs)

  toolchain_tui_render "$cursor"
  while true; do
    if [[ -t 0 ]]; then
      IFS= read -r -s -n 1 key || break
    else
      IFS= read -r -n 1 key || break
    fi

    if [[ -z "$key" || "$key" == $'\r' || "$key" == $'\n' ]]; then
      break
    fi

    case "$key" in
      q | Q)
        toolchain_error 'cancelled by user'
        return 1
        ;;
      k)
        cursor=$(((cursor + 8) % 9))
        ;;
      j)
        cursor=$(((cursor + 1) % 9))
        ;;
      ' ')
        target_stack="${tui_stacks[$cursor]}"
        cur_val="$(detect_get_stack_state "$target_stack")"
        detect_set_stack_state "$target_stack" "$((1 - cur_val))"
        ;;
      [1-9])
        cursor=$((key - 1))
        target_stack="${tui_stacks[$cursor]}"
        cur_val="$(detect_get_stack_state "$target_stack")"
        detect_set_stack_state "$target_stack" "$((1 - cur_val))"
        ;;
      a | A)
        sel_shell=1
        sel_container=1
        sel_python=1
        sel_go=1
        sel_javascript=1
        sel_ruby=1
        if ((sel_terraform == 0)); then
          sel_opentofu=1
        fi
        sel_docs=1
        ;;
      n | N)
        sel_shell=0
        sel_container=0
        sel_python=0
        sel_go=0
        sel_javascript=0
        sel_ruby=0
        sel_opentofu=0
        sel_terraform=0
        sel_docs=0
        ;;
      $'\x1b')
        if [[ -t 0 ]]; then
          IFS= read -r -s -n 2 -t 1 rest || true
        else
          IFS= read -r -n 2 rest || true
        fi
        case "$rest" in
          '[A') cursor=$(((cursor + 8) % 9)) ;;
          '[B') cursor=$(((cursor + 1) % 9)) ;;
        esac
        ;;
    esac
    if [[ -t 2 ]]; then
      printf '\033[11A' >&2
    fi
    toolchain_tui_render "$cursor"
  done
  return 0
}

detect_scan_repo() {
  local repo="$1"
  shift
  detect_scan_files "$repo"
  detect_apply_stack_overrides "$@"
  detect_build_recommendations
}

toolchain_detect() {
  local repo="$1" interactive="${2:-0}" write_config="${3:-0}" force_write="${4:-0}" assume_yes="${5:-0}" hook
  shift 5 || shift "$#"
  local has_shell=0 has_container=0 has_python=0 has_go=0
  local has_js=0 has_ts=0 has_biome=0 has_pnpm_lock=0 has_yarn_lock=0
  local has_ruby=0 has_gemfile_lock=0 has_tf=0 has_yaml=0 has_gha=0 has_md=0
  local auto_shell=0 auto_container=0 auto_python=0 auto_go=0
  local auto_javascript=0 auto_ruby=0 auto_opentofu=0 auto_terraform=0 auto_docs=0
  local sel_shell=0 sel_container=0 sel_python=0 sel_go=0
  local sel_javascript=0 sel_ruby=0 sel_opentofu=0 sel_terraform=0 sel_docs=0
  local -a detected_stacks=() recommended_profiles=() recommended_hooks=() missing_hooks=() config_hooks=()

  detect_scan_repo "$repo" "$@"

  printf 'Detected stacks: %s\n' "${detected_stacks[*]}"
  printf 'Recommended profiles: %s\n' "${recommended_profiles[*]}"
  printf 'Recommended hooks: %s\n' "${recommended_hooks[*]}"

  if [[ -e "$repo/.pre-commit-config.yaml" || -L "$repo/.pre-commit-config.yaml" ]]; then
    toolchain_config_file "$repo/.pre-commit-config.yaml" || return 2
    printf 'Configured hooks: %s\n' "${config_hooks[*]:-none}"
    if /usr/bin/grep -Fq 'cloud-gov/pre-commit-templates' "$repo/.pre-commit-config.yaml"; then
      printf 'Recommendation: migrate repo URL from cloud-gov/pre-commit-templates to https://github.com/cloud-gov/caulking (rev: v3.4.0)\n'
    fi
    if detect_has_configured_hook check-yaml || detect_has_configured_hook check-json; then
      printf 'Recommendation: upgrade ambient check-yaml/check-json to check-yaml-selfcontained/check-json-selfcontained\n'
    fi
    for hook in "${recommended_hooks[@]}"; do
      if ! detect_hook_satisfied "$hook"; then
        missing_hooks+=("$hook")
      fi
    done
    if ((${#missing_hooks[@]} > 0)); then
      printf 'Missing recommended hooks: %s\n' "${missing_hooks[*]}"
    else
      printf 'Missing recommended hooks: none\n'
    fi
  else
    printf "Config status: missing (.pre-commit-config.yaml not found; run 'caulking.sh init --repo %s --write' to generate)\n" "$repo"
  fi

  if ((interactive)); then
    toolchain_init "$repo" "$write_config" "$force_write" "$interactive" "$assume_yes" "$@"
    return $?
  fi
}

detect_render_config() {
  local hook
  printf '# Generated by caulking.sh init\n'
  printf '# Detected stacks: %s\n' "${detected_stacks[*]}"
  # shellcheck disable=SC2016
  printf '%s\n' '# Run `caulking.sh bootstrap --repo .` and `caulking.sh doctor --repo .`'
  printf 'repos:\n'
  printf '  - repo: https://github.com/cloud-gov/caulking\n'
  printf '    rev: v3.4.0\n'
  printf '    hooks:\n'
  for hook in "${recommended_hooks[@]}"; do
    printf '      - id: %s\n' "$hook"
    if [[ "$hook" == check-added-large-files ]]; then
      printf "        args: ['--maxkb=500']\n"
    fi
  done
}

toolchain_init() {
  local repo="$1" write_config="$2" force_write="$3" interactive="${4:-0}" assume_yes="${5:-0}"
  shift 5 || shift "$#"
  local target="$repo/.pre-commit-config.yaml" tmp_file=''
  local has_shell=0 has_container=0 has_python=0 has_go=0
  local has_js=0 has_ts=0 has_biome=0 has_pnpm_lock=0 has_yarn_lock=0
  local has_ruby=0 has_gemfile_lock=0 has_tf=0 has_yaml=0 has_gha=0 has_md=0
  local auto_shell=0 auto_container=0 auto_python=0 auto_go=0
  local auto_javascript=0 auto_ruby=0 auto_opentofu=0 auto_terraform=0 auto_docs=0
  local sel_shell=0 sel_container=0 sel_python=0 sel_go=0
  local sel_javascript=0 sel_ruby=0 sel_opentofu=0 sel_terraform=0 sel_docs=0
  local -a detected_stacks=() recommended_profiles=() recommended_hooks=()

  if ((write_config)); then
    if [[ -L "$target" ]]; then
      toolchain_error "refusing to write through symlink: $target"
      return 2
    fi
    if [[ -e "$target" ]] && ((force_write == 0)); then
      toolchain_error "config already exists: $target (use --force to overwrite)"
      return 1
    fi
  fi

  detect_scan_files "$repo"
  detect_apply_stack_overrides "$@"
  if ((interactive && assume_yes == 0)); then
    toolchain_tui_select_stacks || return $?
  fi
  detect_build_recommendations

  if ((write_config == 0)); then
    detect_render_config
    return 0
  fi

  tmp_file="$(mktemp "$target.XXXXXX")" || {
    toolchain_error "failed to create temporary config in $repo"
    return 1
  }
  if ! detect_render_config > "$tmp_file"; then
    rm -f "$tmp_file"
    toolchain_error "failed to write config: $target"
    return 1
  fi
  chmod 0644 "$tmp_file" || {
    rm -f "$tmp_file"
    toolchain_error "failed to set permissions on config: $target"
    return 1
  }
  mv -f "$tmp_file" "$target" || {
    rm -f "$tmp_file"
    toolchain_error "failed to install config: $target"
    return 1
  }
  printf 'Wrote %s\n' "$target"
}
