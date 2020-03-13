#!/bin/sh 

gitleaksEnabled=$(git config --bool hooks.gitleaks)
cmd="/usr/local/bin/gitleaks --verbose --redact --pretty"
if [ $gitleaksEnabled == "true" ]; then
    $cmd
    status=$?
    if [ $status -eq 1 ]; then
        cat <<\EOF
Error: gitleaks has detected sensitive information in your changes.
If you know what you are doing you can disable this check using:
    git config hooks.gitleaks false
EOF
        exit 1
    else 
        exit $status
    fi
fi