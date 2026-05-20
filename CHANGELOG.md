# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/).

## [3.3.0](https://github.com/cloud-gov/caulking/compare/v3.2.1...v3.3.0) (2026-04-29)

### Features

* Add Linux CI coverage with ubuntu-latest matrix build
* Add Docker-based local testing infrastructure (Dockerfile, docker-compose.yml)
* Add comprehensive pre-push hook tests for stdin ref parsing
* Add automated changelog generation via release-please

### Bug Fixes

* Fix `find` argument order in check_repos.sh (-maxdepth before -name)
* Improve error handling for Homebrew gitleaks installation failures

### Code Refactoring

* DRY refactor: Centralize XDG path definitions in lib.sh
* Remove unused color variables (MAGENTA, BLUE) from pretty.sh

### Tests

* Add test_prepush_ref_parsing.sh for pre-push stdin handling
* Add test_skip_gitleaks.sh for SKIP=gitleaks behavior
* Add test_gitleaks_missing.sh for missing binary error handling
* Add test_local_hook_chain.sh for repo-local hook chaining

### CI/CD

* Add `make test` to CI workflow
* Update to actions/checkout@v4
* Add release-please workflow for automated releases

### Documentation

* Add inline documentation for pre-push scanning flow

### Build System

* Update gitleaks minimum version to 8.21.0
* Update pre-commit-shfmt to v3.13.1-1
* Update actionlint to v1.7.12
* Update Docker base image to Ubuntu 24.04 LTS

## [3.2.1](https://github.com/cloud-gov/caulking/releases/tag/v3.2.1) (2026-02-13)

* Initial XDG layout implementation
* Global gitleaks config with useDefault = true
* Forbidden file denylist (47 patterns)
* Hook chaining for repo-local hooks
