#! ./test/bats/bin/bats
#
# To keep `make audit` runs short with `caulked.bats`, this file
# includes the rules for `allow`.  Also includes tests
# that only make sense during development on the
# developers system.

# Bug bounty folks: Any apparent keys or passwords are just test strings

# Running Tests:
#
#              bats development.bats

load test_helper

# override testCommit to use local.toml in development
# For testing we don't `git add` the file, so we exclude
# the --staged flag we use in the pre-commit hook.
testCommit() {
    gitleaks detect --config=./local.toml --source=${REPO_PATH} --verbose --no-git
}

@test "check_repo fails when turning off hooks.gitleaks" {
    run turnOffHooksGitleaks
    assert_failure
}

@test "check_repo fails when core.hooksPath is overridden" {
    run changeGitHooksPath
    assert_failure
}

@test "check_repo fails when you have a personal email" {
    git config --file $REPO_PATH/.git/config user.email foo@bar.com
    run ./check_repos.sh $REPO_PATH check_user_email >&3
    assert_failure
}

@test "check_repo succeeds when you have a biz email" {
    git config --file $REPO_PATH/.git/config user.email foo@gsa.gov
    run ./check_repos.sh $REPO_PATH check_user_email >&3
    assert_success
}

@test "it allows support and inquiries emails" {
    run addFileWithCGEmails
    assert_success
}

@test "it allows github emails" {
    run addFileWithGithubEmails
    assert_success
}

@test "it allows yaml interpolated values in (()) or {{}}" {
    run addFileWithInterpolatedYamlPassword
    assert_success
}

@test "it ingores ipv4-ish in svg" {
    cat > $REPO_PATH/ok.svg <<END
"\u003csvg xmlns=\"http://www.w3.org/2000/svg\" d=\"M57.547 18.534a3.71 3.71 0 0 10.20.30.40 0-1.679-1.276 5.563 5.563 0 0 0-2.02...",
END
    run testCommit $REPO_PATH
    assert_success
}

@test "it ignores author copyright with email" {
    cat > $REPO_PATH/email.md <<END
Author: pburkholder@example.com
END
    run testCommit $REPO_PATH
    assert_success
}

@test "it passes a 40 character base64 string and doesn't flag it as an AWS secret key" {
    cat > $REPO_PATH/random.txt <<END
foo=+awsSecretAccessKeyisBase64=40characters
END
    run testCommit $REPO_PATH
    assert_success
}

@test "it passes on 41 character long base64 string" {
    cat > $REPO_PATH/random.txt <<END
Can't login with this secret: +1awsSecretAccessKeyisBase64=40characters
END
    run testCommit $REPO_PATH
    assert_success
}

@test "Pass that Ubuntu version is not ipv4" {
    cat > $REPO_PATH/foo.yml <<END
=3.1.2-11ubuntu0.16.04.8
END
    run testCommit $REPO_PATH
    assert_success
}

# We pass/allow username in terraform.
# THIS IS PROBABLY A BAD IDEA. ALLOWING ONLY TO ENSURE
# consistency in upgrade to gitleaks 8.x.
@test "it passes a terraform IAM username reference" {
    cat > $REPO_PATH/foo.tf <<END
module "iam_cert_provision_user" {
  username      = "cg-iam-cert-provision"
END
    run testCommit $REPO_PATH
    assert_success
}

@test "it fails a username reference in non terraform" {
    cat > $REPO_PATH/foo.yaml <<END
module "iam_cert_provision_user" {
  username      = "chthulu"
END
    run testCommit $REPO_PATH
    assert_failure
    assert_output --partial 'generic-username'
}

# Testing for 40 base64 results in too many false positives,
# e.g. all git commit references...
# This may be duplicative of tests elsewhere in this file.
@test "it no longer catches base64 40char potential AWS secret key" {
    cat > $REPO_PATH/random.txt <<END
Login with this secret: +awsSecretAccessKeyisBase64=40characters
END
    run testCommit $REPO_PATH
    assert_success
}

# ToDo: allowable IP addresses should be pulled into a config file
@test "it allows 23.22.13.113 as an ip address" {
    cat > $REPO_PATH/ip.txt <<END
GSA IP address is 23.22.13.113
END
    run testCommit $REPO_PATH
    assert_success
}

# ToDo: allowable example hex values should be pulled into a config file
@test "it allows feed-a-bee as an example secret hex value" {
    cat > $REPO_PATH/sample.yml <<END
enc_key: feedabee
END
    run testCommit $REPO_PATH
    assert_success
}

@test "it allows 1234567890 as an example secret digital value" {
    cat > $REPO_PATH/sample.yml <<END
enc_key: 1234567890
END
    run testCommit $REPO_PATH
    assert_success
}

@test "it allows CHANGEME or EXAMPLE as example secrets" {
    cat > $REPO_PATH/sample.sh <<END
password = "CHANGEME"
AWS_ACCESS_KEY_ID = "AKIAEXAMPLEXXXXXXXXXXXX"
END
    run testCommit $REPO_PATH
    assert_success
}

@test "it allows version starting with 0 and not flag it as an IPv4 address" {
    cat > $REPO_PATH/sample.text <<END
apt-get -y upgrade python3-software-properties=0.96.20.10
END
    run testCommit $REPO_PATH
    assert_success
}

@test "it fails a suspect filename extension" {
    date > $REPO_PATH/foo.pem
    run testCommit $REPO_PATH
    assert_failure
}

@test "it fails a suspect filename" {
    date > $REPO_PATH/shadow
    run testCommit $REPO_PATH
    assert_failure
}

@test "it fails a Sauce access key" {
  cat > $REPO_PATH/travis.yml <<END
    - SAUCE_ACCESS_KEY='39a45464-cb1d-4b8d-aa1f-83c7c04fa673'
END
    run testCommit $REPO_PATH
    assert_failure
}

# tests that our regexes aren't just ascii-sensitive
@test "it fails a user with funny characters" {
  cat > $REPO_PATH/sqlhosts <<END
    user = '39a454/64\-cb@1d-4b.8d-aa1f-83c7c04fa673'
END
    run testCommit $REPO_PATH
    assert_failure
}

# tests that our regexes aren't just ascii-sensitive
@test "it fails a key with funny characters" {
  cat > $REPO_PATH/webapp.py <<END
    app.secret_key = '''39a454/64\-cb1d-4b8d-aa1f-83c7c04fa673'''
END
    run testCommit $REPO_PATH
    assert_failure
}

@test "it fails a flask secret key" {
  cat > $REPO_PATH/webapp.py <<END
    app.secret_key = (
        '39a45464-cb1d-4b8d-aa1f-83c7c04fa673'
    )
END
    run testCommit $REPO_PATH
    assert_failure
}

@test "it allows inspec statement that counts users" {
  cat > $REPO_PATH/inspec.rb <<END
    user_count = input('admins').length + input('non-admins').length
END
    run testCommit $REPO_PATH
    assert_success
}

@test "it passes allowed lockfiles from Generic Credential checks" {
  cat > $REPO_PATH/yarn.lock <<END
    "@hapi/boom@9.x.x", "@hapi/boom@^9.1.0":
END
    run testCommit $REPO_PATH
    assert_success
}

@test "it passes by excluding nested lockfiles from Generic Credential checks" {
  mkdir -p $REPO_PATH/apps/foo
  cat > $REPO_PATH/apps/foo/yarn.lock <<END
    "@hapi/boom@9.x.x", "@hapi/boom@^9.1.0":
END
    run testCommit $REPO_PATH
    assert_success
}

@test "it catches yaml with deploy password" {
    run yamlTest "deploy-password: ohSh.aiNgai%noh4us%ie5nee.nah1ee"
    [ ${status} -eq 1 ]
}

@test "it catches yaml with Slack webhook" {
    run yamlTest "slack-webhook-url: https://hooks.slack.com/services/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"
    [ ${status} -eq 1 ]
}

@test "it allows a username as a templated ERB field" {
  cat > $REPO_PATH/username.erb <<END
    username': '<%= p('cloudfoundry.user'
END
    run testCommit $REPO_PATH
    assert_success
}

@test "it allows a password as a templated ERB field" {
  cat > $REPO_PATH/username.erb <<END
    password': '<%= p('password
END
    run testCommit $REPO_PATH
    assert_success
}

@test "it fails a generic password" {
  cat > $REPO_PATH/password.yaml <<END
    "password": "password"
END
    run testCommit $REPO_PATH
    assert_failure
    assert_output --partial 'generic-credential'
}

@test "it allows hostname as a JSON property value" {
  cat > $REPO_PATH/foo.json <<END
    {
        "name": "rtr.hostname"
    }
END
    run testCommit $REPO_PATH
    assert_success
}

@test "it fails a generic hostname" {
  cat > $REPO_PATH/config.yml <<END
    hostname: "host-1"
END
    run testCommit $REPO_PATH
    assert_failure
    assert_output --partial 'generic-credential'
}

@test "it allows keyword as a JSON property value" {
  cat > $REPO_PATH/test.json <<END
    { "type": "keyword" }
END
    run testCommit $REPO_PATH
    assert_success
}

@test "it fails JSON with keyword as property value but including another generic credential" {
  cat > $REPO_PATH/test.json <<END
    { "type": "keyword", "password": "password" }
END
    run testCommit $REPO_PATH
    assert_failure
    assert_output --partial 'generic-credential'
}
