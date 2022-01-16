#!/usr/bin/env bats

# Bug Bounty and Hackerone Folks: No need to report this file. The
# apparent keys below are all test data used to
# ensure our leak prevention tools are working. 

BATS_TMPDIR=${BATS_TMPDIR:-/tmp}     # set default if sourcing from cli
REPO_PATH=$(mktemp -d "${BATS_TMPDIR}/gittest.XXXXXX")

setupGitRepo() {
    mkdir -p ${REPO_PATH}
    (cd $REPO_PATH && git init .)
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



addFileWithSecretEmail() {
    local secrets_file="${REPO_PATH}/emailfile.md"
    cat >${secrets_file} <<END
SHHHH... Secrets in this file
Email address like test@example.com
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
Host: 10.20.30.40
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
##########################
# for development purposes
##########################
turnOffHooksGitleaks() {
    (cd $REPO_PATH && git config --local hooks.gitleaks false)
    ./check_repos.sh $REPO_PATH check_hooks_gitleaks
}

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
$HOME/bin/gitleaks
END
}
addFileWithCGEmails() {
    local secrets_file="${REPO_PATH}/cgemailfile.md"
    cat >${secrets_file} <<END
No secrets in this file
Email addresses like support@cloud.gov and inquiries@cloud.gov
END
    testCommit $secrets_file
}

addFileWithGithubEmails() {
    local secrets_file="${REPO_PATH}/ghemailfile.md"
    cat >${secrets_file} <<END
No secrets in this file
Email address like noreply@github.com or support@github.com
END
    testCommit $secrets_file
}

addFileWithInterpolatedYamlPassword() {
    local secrets_file="${REPO_PATH}/ok_secret.yml"
    cat >${secrets_file} <<END
No secrets in this file
database_password: ((database_password))
another_password:   {{foo_pass}}
END
    testCommit $secrets_file
}