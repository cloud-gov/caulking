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

# Adding files that trigger `gitleaks`

If the patterns we're using are too aggressive, consider an edit to `local.toml` and making a pull request.

If you get a `gitleaks` error, you can ignore it _temporarily_ with:

```
git config --local hooks.gitleaks false
git commit -am "message" 
git config --local hooks.gitleaks true
```

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
