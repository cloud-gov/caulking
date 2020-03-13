#!/usr/bin/env bats
#
# bats test file for testing that caulking
# prevents leaking secrets.
#
# Prerequisites:
#     * gitleaks and rules are installed with `
#              make clean_gitleaks install`
#              brew install bats-core
# Running Tests:
#
#              bats leakproof.bats

load test_helper

@test "leak prevention allows plain text" {
    run addFileWithNoSecrets
    [ ${status} -eq 0 ]
}

@test "leak prevention catches aws secrets in test repo" {
    run addFileWithAwsSecrets
    [ ${status} -eq 1 ]
}

@test "leak prevention catches aws accesskey in test repo" {
    run addFileWithAwsAccessKey
    [ ${status} -eq 1 ]
}

@test "leak prevention catches aws accounts in test repo" {
    skip # not implemented
    run addFileWithAwsAccounts
    [ ${status} -eq 1 ]
}

@test "leak prevention catches api token in test repo" {
    run addFileWithSlackAPIToken
    [ $(echo "$output" | grep -c 'Found Secrets: 1') -eq 1 ]
}



