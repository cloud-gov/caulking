# Caulking stops leaks

![caulking gun with grey caulk oozing out](https://upload.wikimedia.org/wikipedia/commons/thumb/3/37/Caulking.jpg/757px-Caulking.jpg)

Goals:

* Simplify installation of git leak prevention and rules with `make install`
* Simplify auditing local systems for leak prevention with `make audit`
* Support adding and testing rules

## Installation notes

This assumes you are on MacOS with HomeBrew installed. `make install` will brew install `gitleaks`

Invoking `make audit` the first time will install `pcregrep` and `bats-core`.

To get rid of `git-seekrets` configuration, run `make clean_seekrets`

## Auditing notes

The `make audit` target installs prerequisites then runs `bats caulked.bats`. 

The tests check for:

* common patterns of secrets causing a commit to fail
* that `hooks.gitleaks` is set to true underneath $HOME to $MAXDEPTH setting
* that any custom `/.git/hooks/pre-commit` scripts also still call gitleaks

These assume a compliant engineer who wants to abide by use of `gitleaks`, and 
doesn't deliberately subvert that intent.

## What now?

You have installed gitleaks and our patterns, and you've verified that all of your
repositories are not inadvertently sidestepping the caulking. Continue on with your day. We may periodically ask you to run `make patterns` and `make audit` to update your rules and test that you are still protected from committing known secret patterns.

If you get a `git commit` error message like this:

```
{
	"line": "Juana M. is at juana@example.com",
	"offender": "javier@example.com",
	"commit": "0000000000000000000000000000000000000000",
	"repo": "gittest.ffqOwg",
	"rule": "Email",
	"commitMessage": "***STAGED CHANGES***",
	"author": "",
	"email": "",
	"file": "secretsfile.md",
	"date": "1970-01-01T00:00:00Z",
	"tags": "email"
}
```

Then, remove or fix the offending line.

### But what if the "offending line" isn't a secret?

You have a couple of choices:

* Submit a PR to improve our patterns (guidance forthcoming)
* Submit an issue to this repo, and then ignore `gitleaks` _temporarily_ with:

        git config --local hooks.gitleaks false
        git commit -am "message" 
        git config --local hooks.gitleaks true

You may want to have `.bashrc` function like:

```
gitforce() {
    git config --local hooks.gitleaks false
    git commit -am "$@" 
    git config --local hooks.gitleaks true
}
```

# Development tips

Here are some shortcuts:

- `make hook`: update `~/.git-support/hooks/pre-commit` from local `pre-commit.sh`
- `make patterns`: update the `gitleaks` configuration in `~/.git-support/gitleaks.toml` from local `local.toml` plus upstream rules from the GitLeaks project

# Public domain

This project is in the worldwide public domain. As stated in CONTRIBUTING:

> This project is in the public domain within the United States, and copyright and related rights in the work worldwide are waived through the CC0 1.0 Universal public domain dedication.

> All contributions to this project will be released under the CC0 dedication. By submitting a pull request, you are agreeing to comply with this waiver of copyright interest.
