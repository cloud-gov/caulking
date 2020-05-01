#!/bin/sh 

git_dir=$(git rev-parse --git-dir)
if [ -f "$git_dir/hooks/pre-commit" ]; then
    "$git_dir/hooks/pre-commit" "$@"
fi

gitleaksEnabled=$(git config --bool hooks.gitleaks)
# Running _without_ `--redact` is safer.  Here's wny:
# Suppose you think you're committing `example.yml`:
#   database-pass: example-password
# but you're actually trying to commit:
#   database-pass: a-real-damn-password
# then, you need to see the full output to realize your mistake
cmd="/usr/local/bin/gitleaks --verbose --pretty --config=$HOME/.git-support/gitleaks.toml"
if [ $gitleaksEnabled == "true" ]; then
    $cmd
    status=$?
    if [ $status -eq 1 ]; then
        cat <<\EOF
Error: gitleaks has detected sensitive information in your changes.
If you know what you are doing you can disable this check using:
    git config --local hooks.gitleaks false; 
    git commit ....; 
    git config --local hooks.gitleaks true; 
EOF
        exit 1
    else 
        exit $status
    fi
fi
