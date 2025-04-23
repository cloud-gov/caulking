CAULKING_VERSION=2.0.0 2023-12-01
GITLEAKS_VERSION=8.18.1
GITLEAKS_ARTIFACT="gitleaks_${GITLEAKS_VERSION}_darwin_x64.tar.gz"
GITLEAKS_CHECKSUM=8eaae2aec79175a2b9f1879994c47107752200408ef3bc100ce8f9e56ee0e199
GITLEAKS_DOWNLOAD_DIR="${HOME}/bin/gitleaks-files"
NOW=$(shell date)
ME=$(shell whoami)
BATS=./test/bats/bin/bats

GIT_SUPPORT_PATH=  ${HOME}/.git-support
HOOKS=${GIT_SUPPORT_PATH}/hooks
PRECOMMIT=${GIT_SUPPORT_PATH}/hooks/pre-commit
PATTERNS=${GIT_SUPPORT_PATH}/gitleaks.toml
GITLEAKS= ${HOME}/bin/gitleaks

INSTALL_TARGETS= ${PATTERNS} ${PRECOMMIT} ${GITLEAKS}

HOMEBREW_PREFIX=$(shell brew config | grep HOMEBREW_PREFIX | awk '{print $$2}')

.PHONY: clean audit global_hooks

install: $(INSTALL_TARGETS) global_hooks

audit: ${HOMEBREW_PREFIX}/bin/pcregrep ${GITLEAKS} $(INSTALL_TARGETS)
	@test "$$(${GITLEAKS} version)" = "${GITLEAKS_VERSION}" || ( echo "ERROR -- RUN: 'make clean install'" && false )
	@echo ${CAULKING_VERSION}
	@echo "${ME} / ${NOW}"
	${BATS} -p caulked.bats

clean:
	/bin/rm -rf ${GIT_SUPPORT_PATH}
	git config --global --unset hooks.gitleaks
	git config --global --unset core.hooksPath
	/bin/rm -rf ${GITLEAKS}

hook pre-commit: ${GIT_SUPPORT_PATH}/hooks/pre-commit

global_hooks:
	git config --global hooks.gitleaks true
	git config --global core.hooksPath ${GIT_SUPPORT_PATH}/hooks

config patterns rules: ${GIT_SUPPORT_PATH}/gitleaks.toml

${PATTERNS}: local.toml ${GIT_SUPPORT_PATH}
	cat $< > $@

${PRECOMMIT}: pre-commit.sh ${HOOKS}
	install -m 0755 -cv $< $@

${GIT_SUPPORT_PATH} ${HOOKS}:
	mkdir -p $@

${HOMEBREW_PREFIX}/bin/pcregrep:
	brew install pcre

${GITLEAKS}:
	brew install gitleaks || brew reinstall gitleaks

upgrade:
	brew uninstall gitleaks || rm -f ${GITLEAKS} && rm -f ${HOME}/bin/gitleaks
	make ${GITLEAKS}

FORCE:
