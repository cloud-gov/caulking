#!/bin/sh

# Only try to run local hooks if we're not in a test environment
if [ -z "$BATS_TEST_FILENAME" ] && [ -z "$SKIP" ]; then
    git_dir=$(git rev-parse --git-dir)
    if [ -f "$git_dir/hooks/pre-commit" ]; then
        set -e
        "$git_dir/hooks/pre-commit" "$@"
        set +e
    fi
fi

# Prompt the user for a yes/no response.
# Exit codes:
#   0: user entered yes
#   10: user entered no
#
prompt_yn() {
  prompt ans
  if [ $# -ge 1 ]; then
    prompt="$1"
  else
    prompt="Continue?"
  fi

  while true; do
    # Allows us to read user input below, assigns stdin to keyboard (from Stackoverflow)
    exec < /dev/tty
    read -r -p "$prompt [y/n] " ans
    exec <&-
    case "$ans" in
      Y|y|yes|YES|Yes)
        return 0
        ;;
      N|n|no|NO|No)
        return 10
        ;;
    esac
  done
}

run_gitleaks() {
    echo "Debug: Starting gitleaks check" >&2
    echo "Debug: Using config at $HOME/.git-support/gitleaks.toml" >&2
    echo "Debug: gitleaks location: $(which gitleaks)" >&2
    
    # Save current git trace settings
    old_git_trace="$GIT_TRACE"
    old_git_trace_setup="$GIT_TRACE_SETUP"
    unset GIT_TRACE
    unset GIT_TRACE_SETUP
    
    # Running _without_ `--redact` is safer in a local development
    cmd="gitleaks protect --staged --config=$HOME/.git-support/gitleaks.toml --verbose"
    echo "Debug: Running command: $cmd" >&2
    
    output=$($cmd 2>&1)
    status=$?
    echo "Debug: gitleaks exit status: $status" >&2
    echo "$output" >&2
    
    # Restore git trace settings
    if [ -n "$old_git_trace" ]; then
        export GIT_TRACE="$old_git_trace"
    fi
    if [ -n "$old_git_trace_setup" ]; then
        export GIT_TRACE_SETUP="$old_git_trace_setup"
    fi
    
    # Check for "no leaks found" in output regardless of exit status
    if echo "$output" | grep -q "no leaks found"; then
        echo "no leaks found"
        exit 0
    elif [ $status -eq 1 ]; then
        cat <<-\EOF
        Error: gitleaks has detected sensitive information in your changes.
        For examples use: CHANGEME|changeme|feedabee|EXAMPLE|23.22.13.113|1234567890
        If you know what you are doing you can disable this check using:
            SKIP=gitleaks git commit ...
        or using shell history:
            SKIP=gitleaks !!
EOF
        exit 1
    else
        exit $status
    fi
}

skip_gitleaks() {
    if prompt_yn "Do you want to SKIP gitleaks?"; then
      echo "Skipping..."
      exit 0
    else
      echo "Cancelled."
      exit 10
    fi
}

gitleaksEnabled=$(git config --bool hooks.gitleaks)
if [ "$gitleaksEnabled" = "false" ]; then
    echo "You're skipping gitleaks since hooks.gitleaks is 'false'"
    skip_gitleaks
elif [ "$SKIP" = "gitleaks" ]; then
    echo "You're skipping gitleaks since SKIP=gitleaks"
    skip_gitleaks
else
    run_gitleaks
fi
