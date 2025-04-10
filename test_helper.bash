#!/usr/bin/env bash

# Bug Bounty and Hackerone Folks: No need to report this file. The
# apparent keys below are all test data used to
# ensure our leak prevention tools are working.

BATS_TMPDIR=${BATS_TMPDIR:-/tmp}     # set default if sourcing from cli
REPO_PATH=$(mktemp -d "${BATS_TMPDIR}/gittest.XXXXXX")

setupGitRepo() {
    mkdir -p "${REPO_PATH}"
    (cd "$REPO_PATH" && git init .)
}

cleanGitRepo() {
    rm -fr "${REPO_PATH}"
}

testCommit() {
    filename=$1
    echo "=== Git Status Before Add ===" >&2
    (cd "${REPO_PATH}" && git status) >&2
    
    echo "=== Git Add ===" >&2
    (cd "${REPO_PATH}" && git add "${filename}")
    
    echo "=== Git Status Before Commit ===" >&2
    (cd "${REPO_PATH}" && git status) >&2
    
    echo "=== Git Commit ===" >&2
    (cd "${REPO_PATH}" && GIT_TRACE=1 git commit -m 'test commit')
    local commit_status=$?
    
    echo "=== Git Status After Commit ===" >&2
    (cd "${REPO_PATH}" && git status) >&2
    
    return $commit_status
}

testUnstagedCommit() {
    filename=$1
    (cd "${REPO_PATH}" && git commit -m 'test commit')
}

setup() {
    load 'test/bats-support/load' # this is required by bats-assert!
    load 'test/bats-assert/load'
    setupGitRepo
}

teardown() {
    cleanGitRepo
}

addFileWithNoSecrets() {
    local filename="${REPO_PATH}/plainfile.md"
    
    # Set up git config for test repo
    (cd "${REPO_PATH}" && git config user.name "Test User")
    (cd "${REPO_PATH}" && git config user.email "test@example.com")
    (cd "${REPO_PATH}" && git config hooks.gitleaks true)
    
    # Create and add file
    touch "${filename}"
    echo "Just a plain old file" >> "${filename}"
    
    # Set test environment variables
    export BATS_TEST_FILENAME="caulked.bats"
    unset GIT_TRACE
    unset GIT_TRACE_SETUP
    
    # Try the commit
    testCommit "$filename"
    local commit_status=$?
    
    # Clean up environment
    unset BATS_TEST_FILENAME
    
    return $commit_status
}

unstagedFileWithAwsSecrets() {
    local secrets_file="${REPO_PATH}/unstaged-secretsfile.md"

    cat >"${secrets_file}" <<END
SHHHH... Secrets in this file
aws_secret_access_key = WT8ftNba7siVx5UOoGzJSyd82uNCZAC8LCllzcWp
END
    testUnstagedCommit "$secrets_file"
}

addFileWithAwsSecrets() {
    local secrets_file="${REPO_PATH}/secretsfile.md"

    cat >"${secrets_file}" <<END
SHHHH... Secrets in this file
aws_secret_access_key = WT8ftNba7siVx5UOoGzJSyd82uNCZAC8LCllzcWp
END
    testCommit "$secrets_file"
}

addFileWithAwsAccessKey() {
    local secrets_file="${REPO_PATH}/accessfile.md"
    cat >"${secrets_file}" <<END
SHHHH... Secrets in this file
AWS_ACCESS_KEY_ID: AKIAJLLCKKYFEWP5MWXA
END
    testCommit "$secrets_file"
}


addFileWithSecretEmail() {
    local secrets_file="${REPO_PATH}/emailfile.md"
    cat >"${secrets_file}" <<END
SHHHH... Secrets in this file
Email address like test@example.com
END
    testCommit "$secrets_file"
}

addFileWithSlackAPIToken() {
    local secrets_file="${REPO_PATH}/slacktokenfile.md"

    cat >"${secrets_file}" <<END
SHHHH... Secrets in this file
slack_api_token=xoxb-333649436676-799261852869-clFJVVIaoJahpORboa3Ba2al
END
    testCommit "$secrets_file"
}

addFileWithIPv4() {
    local secrets_file="${REPO_PATH}/ipv4file.md"

    cat >"${secrets_file}" <<END
SHHHH... Secrets in this file
Host: 10.20.30.40
END
    testCommit "$secrets_file"
}

yamlTest() {
    local secrets_file="${REPO_PATH}/cloudgov.yml"
    cat >"${secrets_file}" <<END
# Credentials
$1
END
    testCommit "$secrets_file"
}

testLocalGitHook() {
    # Create a test pre-commit hook that will run alongside gitleaks
    local hook_dir="$HOME/.git-support/hooks"
    local original_hook="$hook_dir/pre-commit"
    local backup_hook="$hook_dir/pre-commit.backup"

    # Backup existing hook if it exists
    if [ -f "$original_hook" ]; then
        cp "$original_hook" "$backup_hook"
    fi

    # Create new hook that includes both our test output and original functionality
    cat >"$original_hook" <<'END'
#!/bin/bash
echo "foobar"

# Run gitleaks check if it exists
if [ -f "$HOME/.git-support/gitleaks.toml" ]; then
    gitleaks protect --staged --config="$HOME/.git-support/gitleaks.toml" --verbose
fi
END
    chmod 755 "$original_hook"

    # Create and commit a test file
    local test_file="${REPO_PATH}/test.txt"
    echo "test content" > "$test_file"
    testCommit "$test_file"

    # Restore original hook
    if [ -f "$backup_hook" ]; then
        mv "$backup_hook" "$original_hook"
    fi
}

##########################
# for development purposes
##########################
turnOffHooksGitleaks() {
    (cd "$REPO_PATH" && git config --local hooks.gitleaks false)
    ./check_repos.sh "$REPO_PATH" check_hooks_gitleaks
}

changeGitHooksPath() {
    (cd "$REPO_PATH" && git config --local core.hooksPath "foobar")
    ./check_repos.sh "$REPO_PATH" check_hooks_path
}

createPrecommitNoGitleaks() {
    (cd "$REPO_PATH" && mv .git/hooks/pre-commit.sample .git/hooks/pre-commit)
}

createPrecommitCommentedGitleaks() {
    cat >"$REPO_PATH"/.git/hooks/pre-commit <<END
# lets not run gitleaks
END
}

createPrecommitOKGitLeaks() {
    cat >"$REPO_PATH"/.git/hooks/pre-commit <<END
#!/bin/sh
echo special stuff
$HOME/bin/gitleaks
END
}
addFileWithCGEmails() {
    local secrets_file="${REPO_PATH}/cgemailfile.md"
    cat >"${secrets_file}" <<END
No secrets in this file
Email addresses like support@cloud.gov and inquiries@cloud.gov
END
    testCommit "$secrets_file"
}

addFileWithGithubEmails() {
    local secrets_file="${REPO_PATH}/ghemailfile.md"
    cat >"${secrets_file}" <<END
No secrets in this file
Email address like noreply@github.com or support@github.com
END
    testCommit "$secrets_file"
}

addFileWithInterpolatedYamlPassword() {
    local secrets_file="${REPO_PATH}/ok_secret.yml"
    cat >"${secrets_file}" <<END
No secrets in this file
database_password: ((database_password))
another_password:   {{foo_pass}}
END
    testCommit "$secrets_file"
}
