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

@test "leak prevention catches Slack api token in test repo" {
    run addFileWithSlackAPIToken
    [ ${status} -eq 1 ]
}

@test "leak prevention catches IPv4 address in test repo" {
    run addFileWithIPv4
    [ ${status} -eq 1 ]
}

@test "all repos have hooks.gitleaks set to true" {
    ./check_repos.sh $HOME check_hooks_gitleaks >&3
}

@test "creating precommit w/o gitleakss in a repo" {
    run createPrecommitNoGitleaks
    [ ${status} -eq 1 ]
}