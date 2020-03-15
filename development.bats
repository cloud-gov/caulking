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

@test "turning off hooks.gitleaks on a repo" {
    run turnOffHooksGitleaks
    [ ${status} -eq 1 ]
}

@test "creating precommit w/o gitleaks in a repo" {
    createPrecommitNoGitleaks
    run ./check_repos.sh $REPO_PATH check_precommit_hook >&3
    [ ${status} -eq 1 ]
}

@test "creating precommit w commented gitleaks in a repo" {
    createPrecommitCommentedGitleaks
    run ./check_repos.sh $REPO_PATH check_precommit_hook >&3
    [ ${status} -eq 1 ]
}

@test "creating precommit w OK gitleaks in a repo" {
    run createPrecommitOKGitleaks
    run ./check_repos.sh $REPO_PATH check_precommit_hook >&3
    [ ${status} -eq 0 ]
}
