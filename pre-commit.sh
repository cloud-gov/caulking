#!/bin/sh

git_dir=$(git rev-parse --git-dir)

if [ -f "$git_dir/hooks/pre-commit" ]; then
    set -e
    "$git_dir/hooks/pre-commit" "$@"
    set +e
fi

run_gitleaks() {
    # Running _without_ `--redact` is safer in a local development
    # env, as you need unobfuscated feedback on whether you're 
    # committing a real password, or an example one.
    cmd="$HOME/bin/gitleaks protect --staged --config=$HOME/.git-support/gitleaks.toml --verbose"
    $cmd
    status=$?
    if [ $status -eq 1 ]; then
        cat <<\EOF
Error: gitleaks has detected sensitive information in your changes.
For examples use: CHANGEME|changeme|feedabee|EXAMPLE|23.22.13.113|1234567890
If you know what you are doing you can disable this check using:
    SKIP=gitleaks $*
EOF
        exit 1
    else
        exit $status
    fi
}

skip_gitleaks() {
    echo "Sleeping for 5 seconds while you ponder your choices"
    for i in 1 2 3 4 5; do
      echo -n ". "
      sleep 1
    done
    read -p "Are you sure about skipping gitleaks? " yn
    case $in in
        [Yy]*) exit 0;;
        *)     exit 1;;
    esac
}

gitleaksEnabled=$(git config --bool hooks.gitleaks)
if [ "$gitleaksEnabled" = "false" ]; then
    echo "You're skipping gitleaks hooks.gitleaks if false"
    skip_gitleaks
elif [ "$SKIP" = "gitleaks" ]; then
    echo "You're skipping gitleaks check since SKIP=gitleaks"
    skip_gitleaks
else
    run_gitleaks
fi