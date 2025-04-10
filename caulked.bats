#! ./test/bats/bin/bats
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
    assert_output --partial "no leaks found"
}

@test "leak prevention catches unstaged aws secrets in test repo" {
    run unstagedFileWithAwsSecrets
    [ ${status} -eq 1 ]
}

@test "leak prevention catches aws secrets in test repo" {
    run addFileWithAwsSecrets
    [ ${status} -eq 1 ]
}

@test "leak prevention catches aws accesskey in test repo" {
    run addFileWithAwsAccessKey
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

@test "repo runs gitleaks and local githooks" {
    run testLocalGitHook
    assert_output --partial "foobar"
    assert_output --partial "no leaks found"
}

@test "repos have hooks.gitleaks set to true" {
    ./check_repos.sh $HOME check_hooks_gitleaks >&3
}

@test "repos are not overriding the core hooks path" {
    ./check_repos.sh $HOME check_hooks_path >&3
}

@test "the ~/.aws directory is free of AWS keys" {
  if [ -d ~/.aws ]; then
    run grep -rq 'AKIA' $HOME/.aws
    [ ${status} -eq 1 ]
  else
    true
  fi
}

@test "git configuration uses a @gsa.gov email" {
    if [ $CI = 'true' ]; then
        skip "Skipping test in CI"
    fi
    ./check_repos.sh $HOME check_user_email >&3
}

@test "it catches yaml with encryption key" {
    run yamlTest "development-enc-key: aich3thei2ieCai0choyohg9Iephoh8I"
    [ ${status} -eq 1 ]
}

@test "it catches yaml with auth pass" {
    run yamlTest "development-auth-pass: woothothae5IezaiD8gu0eiweKui4sah"
    [ ${status} -eq 1 ]
}

@test "it is on the latest commit, on failure run: git pull; git checkout main" {
    if [ "${GITHUB_ACTIONS}" = "true" ] ; then
      skip "Attention: GITHUB_ACTIONS is true"
    fi
    URL=https://github.com/cloud-gov/caulking.git
    git_head=$(git ls-remote $URL HEAD | cut -f1)
    local_head=$(git rev-parse HEAD)
    run test "$git_head" = "$local_head"
    assert_success
}
