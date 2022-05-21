#!/bin/sh

git_dir=$(git rev-parse --git-dir)
if [ -f "$git_dir/hooks/pre-commit" ]; then
    set -e
    "$git_dir/hooks/pre-commit" "$@"
    set +e
fi

gitleaksEnabled=$(git config --bool hooks.gitleaks)
# Running _without_ `--redact` is safer.  Here's wny:
# Suppose you think you're committing `example.yml`:
#   database-pass: example-password
# but you're actually trying to commit:
#   database-pass: a-real-damn-password
# then, you need to see the full output to realize your mistake
cmd="$HOME/bin/gitleaks protect --staged --config=$HOME/.git-support/gitleaks.toml --verbose"
if [ $gitleaksEnabled == "true" ]; then
    $cmd
    status=$?
    if [ $status -eq 1 ]; then
        cat <<\EOF
Error: gitleaks has detected sensitive information in your changes.
For examples use: CHANGEME|changeme|feedabee|EXAMPLE|23.22.13.113|1234567890
If you know what you are doing you can disable this check using:
    git config --local hooks.gitleaks false;
    !-2  # command -2 in your history
    git config --local hooks.gitleaks true;
EOF
        exit 1
    else
        exit $status
    fi
fi
