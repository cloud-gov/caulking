#!/usr/bin/env bats
#
# To keep `make audit` runs short with `caulked.bats`, this file
# includes the rules for `allow`.  Also includes tests
# that only make sense during development on the 
# developers system

# Running Tests:
#
#              bats development.bats

load test_helper

# override testCommit to use local.toml in development
testCommit() {
    gitleaks --config=./local.toml --repo-path=${REPO_PATH} --uncommitted
}

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

@test "leak prevention allows support and inquiries emails" {
    run addFileWithCGEmails
    [ ${status} -eq 0 ]
}

@test "leak prevention allows github emails" {
    run addFileWithGithubEmails
    [ ${status} -eq 0 ]
}

@test "leak prevention allows yaml interpolated values in (()) or {{}}" {
    run addFileWithInterpolatedYamlPassword
    [ ${status} -eq 0 ]
}

@test "ingore ipv4-ish in svg" {
    cat > $REPO_PATH/ok.svg <<END
"\u003csvg xmlns=\"http://www.w3.org/2000/svg\" d=\"M57.547 18.534a3.71 3.71 0 0 10.20.30.40 0-1.679-1.276 5.563 5.563 0 0 0-2.02...",
END
    run testCommit $REPO_PATH
    [ ${status} -eq 0 ]
}

@test "ignore author copyright with email" {
    cat > $REPO_PATH/email.md <<END
Author: pburkholder@example.com
END
    run testCommit $REPO_PATH
    [ ${status} -eq 0 ]
}