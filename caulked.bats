#!/usr/bin/env bats
#
# bats test file for testing that caulking
# prevents leaking secrets.
#
# Bug bounty and HackerOne folks - do not report this
# file. These are all fake/obsolete keys.
#
# Prerequisites:
#     * gitleaks and rules are installed with `
#              make clean_gitleaks install`
# Running Tests:
#   make audit
# 
# Development note: These tests all assume that your root
# ~/.git-support/gitleaks.toml are up to date. If you're testing
# `local.toml` then use `development.bats` (or use `make patterns` 
# before `make audit`)

load test_helper

@test "leak prevention allows plain text, check 'git config --global -l' on failure" {
    run addFileWithNoSecrets
    [ ${status} -eq 0 ]
    echo ${lines[0]} | grep -q "No leaks detected in staged changes"
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

@test "leak prevention catches normal email addresses in test repo" {
    run addFileWithSecretEmail
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

@test "repos have hooks.gitleaks set to true" {
    ./check_repos.sh $HOME check_hooks_gitleaks >&3
}

@test "repos are using precommit hooks with gitleaks" {
    ./check_repos.sh $HOME check_precommit_hook >&3
}

@test "audit fails if AWS keys are in ~/.aws" {
    run grep -rq 'AKIA' $HOME/.aws
    [ ${status} -eq 1 ]
}

@test "it catches yaml with deploy password" {
    run yamlTest "deploy-password: ohSh.aiNgai%noh4us%ie5nee.nah1ee"
    [ ${status} -eq 1 ]
}

@test "it catches yaml with Slack webhook" {
    run yamlTest "slack-webhook-url: https://hooks.slack.com/services/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"
    [ ${status} -eq 1 ]
}

@test "it catches yaml with encryption key" {
    run yamlTest "development-enc-key: aich3thei2ieCai0choyohg9Iephoh8I"
    [ ${status} -eq 1 ]
}

@test "it catches yaml with auth pass" {
    run yamlTest "development-auth-pass: woothothae5IezaiD8gu0eiweKui4sah"
    [ ${status} -eq 1 ]
}

