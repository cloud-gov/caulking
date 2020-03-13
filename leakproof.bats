#!/usr/bin/env bats
#
# bats test file for testing git seekrets and
# seekrets rulesets
#
# Prerequisites:
#     * git seekrets is installed (cf. seekrets-install)
#
# Installation:
#     * Use the laptop script via ~/.laptop.local
#
#              echo 'bats' >> ~/.laptop.local
#
#     * homebrew method
#
#              brew install bats-core
#
# Running Tests:
#
#              bats seekrets.bat

load test_helper

@test "leak prevention does not find secrets in test repo" {
    run addFileWithNoSecrets
    [ ${status} -eq 0 ]
}

@test "leak prevention does find aws secrets in test repo" {
    run addFileWithAwsSecrets
    [ ${status} -eq 1 ]
}

@test "leak prevention does find aws accounts in test repo" {
    run addFileWithAwsAccounts
    [ ${status} -eq 1 ]
}

@test "leak prevention does find newrelic secrets in test repo" {
    run addFileWithNewrelicSecrets
    [ $(echo "$output" | grep -c 'Found Secrets: 1') -eq 1 ]
}

@test "leak prevention does not find newrelic false positives in test repo" {
    run addFileWithFalseNewrelicSecrets
    [ ${status} -eq 1 ]
}

@test "leak prevention only matches newrelic secrets in test repo" {
    run addFileWithSomeNewrelicSecrets
    [ $(echo "$output" | grep -c 'Found Secrets: 1') -eq 1 ]
}

@test "leak prevention does find mandrill keys in test repo" {
    run addFileWithMandrillKey
    [ $(echo "$output" | grep -c 'Found Secrets: 1') -eq 1 ]
}

@test "leak prevention does not find mandrill key false positives in test repo" {
    run addFileWithFalseMandrillKey
    [ $(echo "$output" | grep -c 'Found Secrets: 0') -eq 1 ]
}

@test "leak prevention does find mandrill passwords in test repo" {
    run addFileWithMandrillPassword
    [ $(echo "$output" | grep -c 'Found Secrets: 2') -eq 1 ]
}

@test "leak prevention does not find mandrill password false positives in test repo" {
    run addFileWithFalseMandrillPassword
    [ $(echo "$output" | grep -c 'Found Secrets: 0') -eq 1 ]
}

@test "leak prevention does find mandrill usernames in test repo" {
    run addFileWithMandrillUsername
    [ $(echo "$output" | grep -c 'Found Secrets: 1') -eq 1 ]
}

@test "leak prevention does find slack api token in test repo" {
    run addFileWithSlackAPIToken
    [ $(echo "$output" | grep -c 'Found Secrets: 1') -eq 1 ]
}



