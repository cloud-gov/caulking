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

@test "creating precommit w/o gitleakss in a repo" {
    run createPrecommitNoGitleaks
    [ ${status} -eq 1 ]
}