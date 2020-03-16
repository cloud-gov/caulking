#!/usr/bin/env bats

BATS_TMPDIR=${BATS_TMPDIR:-/tmp}     # set default if sourcing from cli
REPO_PATH=$(mktemp -d "${BATS_TMPDIR}/gittest.XXXXXX")
BUNDLE=caulking_test_repo.bundle

setupGitRepo() {
    git clone $BUNDLE $REPO_PATH >/dev/null 2>/dev/null
}

cleanGitRepo() {
    rm -fr "${REPO_PATH}"
}

testCommit() {
    filename=$1
    (cd "${REPO_PATH}" && git add "${filename}")
    (cd ${REPO_PATH} && git commit -m 'test commit')
}

setup() {
    setupGitRepo
}

teardown() {
    cleanGitRepo
}

addFileWithNoSecrets() {
    local filename="${REPO_PATH}/plainfile.md"

    touch "${filename}"
    echo "Just a plain old file" >> "${filename}"
    testCommit $filename
}

addFileWithAwsSecrets() {
    local secrets_file="${REPO_PATH}/secretsfile.md"

    cat >${secrets_file} <<END
SHHHH... Secrets in this file
aws_secret_access_key = WT8ftNba7siVx5UOoGzJSyd82uNCZAC8LCllzcWp
END
    testCommit $secrets_file
}

addFileWithAwsAccessKey() {
    local secrets_file="${REPO_PATH}/accessfile.md"
    cat >${secrets_file} <<END
SHHHH... Secrets in this file
AWS_ACCESS_KEY_ID: AKIAJLLCKKYFEWP5MWXA 
END
    testCommit $secrets_file
}

addFileWithSlackAPIToken() {
    local secrets_file="${REPO_PATH}/slacktokenfile.md"

    cat >${secrets_file} <<END
SHHHH... Secrets in this file
slack_api_token=xoxb-333649436676-799261852869-clFJVVIaoJahpORboa3Ba2al
END
    testCommit $secrets_file
}

addFileWithIPv4() {
    local secrets_file="${REPO_PATH}/ipv4file.md"

    cat >${secrets_file} <<END
SHHHH... Secrets in this file
Host: 127.0.0.1
END
    testCommit $secrets_file
}

yamlTest() {
    local secrets_file="${REPO_PATH}/cloudgov.yml"
    cat >${secrets_file} <<END
# Credentials
$1
END
    testCommit $secrets_file
}

# for development purposes
turnOffHooksGitleaks() {
    (cd $REPO_PATH && git config --local hooks.gitleaks false)
    ./check_repos.sh $HOME check_hooks_gitleaks
}

## remaining are for development purposes
createPrecommitNoGitleaks() {
    (cd $REPO_PATH && mv .git/hooks/pre-commit.sample .git/hooks/pre-commit)
}

createPrecommitCommentedGitleaks() {
    cat >$REPO_PATH/.git/hooks/pre-commit <<END
# lets not run gitleaks
END
}

createPrecommitOKGitLeaks() {
    cat >$REPO_PATH/.git/hooks/pre-commit <<END
#!/bin/sh
echo special stuff
/usr/local/bin/gitleaks
END
}