#!/usr/bin/env bats

BATS_TMPDIR=${BATS_TMPDIR:-/tmp}     # set default if sourcing from cli
REPO_PATH=$(mktemp -d "${BATS_TMPDIR}/gittest.XXXXXX")
BUNDLE=caulking_test_repo.bundle

setupGitRepo() {
    git clone $BUNDLE $REPO_PATH
}

cleanGitRepo() {
    rm -fr "${REPO_PATH}"
}

testCommit() {
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
    testCommit
}

addFileWithAwsSecrets() {
    local secrets_file="${REPO_PATH}/secretsfile.md"

    cat >${secrets_file} <<END
SHHHH... Secrets in this file
AWS_SECRET_ACCESS_KEY: WT8ftNba7siVx5UOoGzJSyd82uNCZAC8LCllzcWp
END
    testCommit
}

addFileWithAwsAccessKey() {
    local secrets_file="${REPO_PATH}/accessfile.md"
    cat >${secrets_file} <<END
SHHHH... Secrets in this file
AWS_ACCESS_KEY_ID: AKIAJLLCKKYFEWP5MWXA 
END
    testCommit
}

addFileWithSlackAPIToken() {
    local secrets_file="${REPO_PATH}/slacktokenfile.md"

    cat >${secrets_file} <<END
SHHHH... Secrets in this file
slack_api_token=xoxb-333649436676-799261852869-clFJVVIaoJahpORboa3Ba2al
END
    testCommit
}

addFileWithSSN() {
    local secrets_file="${REPO_PATH}/ssnfile.md"

    cat >${secrets_file} <<END
SHHHH... Secrets in this file
SSN: 322-99-4321
END
    testCommit
}

