#!/usr/bin/env bats
#
# To keep `make audit` runs short with `caulked.bats`, this file
# includes the rules for `allow`.  Also includes tests
# that only make sense during development on the 
# developers system

# Bug bounty folks: Any apparent keys or passwords are just test strings

# Running Tests:
#
#              bats development.bats

load test_helper

# override testCommit to use local.toml in development
testCommit() {
    gitleaks --leaks-exit-code=1 --config-path=./local.toml --path=${REPO_PATH} --unstaged
}

# Trying new `should` helper functions to aid
# in readability
function should_pass() {
    [ ${status} -eq 0 ]
}
function should_fail() {
    [ ${status} -eq 1 ]
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

@test "it fails when you have a personal email" {
    git config --file $REPO_PATH/.git/config user.email foo@bar.com
    run ./check_repos.sh $REPO_PATH check_user_email >&3
    should_fail
}

@test "it succeeds when you have a biz email" {
    git config --file $REPO_PATH/.git/config user.email foo@gsa.gov
    run ./check_repos.sh $REPO_PATH check_user_email >&3
    should_pass
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

@test "false negative OK on presumed AWS secret key" {
    cat > $REPO_PATH/random.txt <<END
foo=+awsSecretAccessKeyisBase64=40characters
END
    run testCommit $REPO_PATH
    [ ${status} -eq 0 ]
}

@test "Pass on 41 character long base64 string" {
    cat > $REPO_PATH/random.txt <<END
Can't login with this secret: +1awsSecretAccessKeyisBase64=40characters
END
    run testCommit $REPO_PATH
    [ ${status} -eq 0 ]
}

@test "Pass that Ubuntu version is not ipv4" {
    cat > $REPO_PATH/foo.yml <<END
=3.1.2-11ubuntu0.16.04.8
END
    run testCommit $REPO_PATH
    [ ${status} -eq 0 ]
}

@test "Pass a terraform IAM username reference" {
    cat > $REPO_PATH/foo.tf <<END
module "iam_cert_provision_user" {
  username      = "cg-iam-cert-provision"
END
    run testCommit $REPO_PATH
    should_pass
}

@test "Fail a username reference in non terraform" {
    cat > $REPO_PATH/foo.yaml <<END
module "iam_cert_provision_user" {
  username      = "chthulu"
END
    run testCommit $REPO_PATH
    should_fail
}

# Testing for 40 base64 results in too many false positives,
# e.g. all git commit references...
@test "it no longer catches base64 40char potential AWS secret key" {
    cat > $REPO_PATH/random.txt <<END
Login with this secret: +awsSecretAccessKeyisBase64=40characters
END
    run testCommit $REPO_PATH
    [ ${status} -eq 0 ]
}

@test "it allows 23.22.13.113 as an ip address" {
    cat > $REPO_PATH/ip.txt <<END
GSA IP address is 23.22.13.113
END
    run testCommit $REPO_PATH
    [ ${status} -eq 0 ]
}

@test "it allows feed-a-bee as an example secret hex value" {
    cat > $REPO_PATH/sample.yml <<END
enc_key: feedabee
END
    run testCommit $REPO_PATH
    [ ${status} -eq 0 ]
}

@test "it allows 1234567890 as an example secret digital value" {
    cat > $REPO_PATH/sample.yml <<END
enc_key: 1234567890
END
    run testCommit $REPO_PATH
    [ ${status} -eq 0 ]
}

@test "it allows CHANGEME or EXAMPLE as example secrets" {
    cat > $REPO_PATH/sample.sh <<END
password = "CHANGEME"
AWS_ACCESS_KEY_ID = "AKIAEXAMPLEXXXXXXXXXXXX"
END
    run testCommit $REPO_PATH
    [ ${status} -eq 0 ]
}

@test "it allows version starting with 0 as not an IPv4 address" {
    cat > $REPO_PATH/sample.text <<END
apt-get -y upgrade python3-software-properties=0.96.20.10
END
    run testCommit $REPO_PATH
    [ ${status} -eq 0 ]
}

@test "it fails a suspect filename extension" {
    touch $REPO_PATH/foo.pem 
    run testCommit $REPO_PATH
    should_fail
}

@test "it fails a suspect filename" {
    touch $REPO_PATH/shadow
    run testCommit $REPO_PATH
    should_fail
}

@test "it fails a Sauce access key" {
  cat > $REPO_PATH/travis.yml <<END
    - SAUCE_ACCESS_KEY='39a45464-cb1d-4b8d-aa1f-83c7c04fa673'
END
    run testCommit $REPO_PATH
    should_fail
}

@test "it fails a user with funny characters" {
  cat > $REPO_PATH/sqlhosts <<END
    user = '39a454/64\-cb@1d-4b.8d-aa1f-83c7c04fa673'
END
    run testCommit $REPO_PATH
    should_fail
}

@test "it fails a key with funny characters" {
  cat > $REPO_PATH/webapp.py <<END
    app.secret_key = '''39a454/64\-cb1d-4b8d-aa1f-83c7c04fa673'''
END
    run testCommit $REPO_PATH
    should_fail
}

@test "it fails a flask secret key" {
  cat > $REPO_PATH/webapp.py <<END
    app.secret_key = (
        '39a45464-cb1d-4b8d-aa1f-83c7c04fa673'
    )
END
    run testCommit $REPO_PATH
    should_fail
}

@test "it allows an inspec count of users" { 
  cat > $REPO_PATH/inspec.rb <<END
    user_count = input('admins').length + input('non-admins').length
END
    run testCommit $REPO_PATH
    should_pass
}

@test "it excludes lockfiles from Generic Credential checks" {
  cat > $REPO_PATH/yarn.lock <<END
    "@hapi/boom@9.x.x", "@hapi/boom@^9.1.0":
END
    run testCommit $REPO_PATH
    should_pass
}

@test "it excludes nested lockfiles from Generic Credential checks" {
  mkdir -p $REPO_PATH/apps/foo 
  cat > $REPO_PATH/apps/foo/yarn.lock <<END
    "@hapi/boom@9.x.x", "@hapi/boom@^9.1.0":
END
    run testCommit $REPO_PATH
    should_pass
}