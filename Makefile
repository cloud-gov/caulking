CAULKING_VERSION=1.99.0 2022-05-24
GITLEAKS_VERSION=8.8.4
GITLEAKS_ARTIFACT="gitleaks_${GITLEAKS_VERSION}_darwin_x64.tar.gz"
GITLEAKS_CHECKSUM=509430dada69ee4314068847a8a424d4102defc23fd5714330d36366796feef7
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

clean_seekrets:
	/bin/rm -rf ${GIT_SUPPORT_PATH}/seekret-rules
	-git config --global --unset gitseekret.rulesenabled
	-git config --global --unset gitseekret.rulespath
	-git config --global --unset gitseekret.exceptionsfile
	-git config --global --unset gitseekret.version

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
	mkdir -p ${GITLEAKS_DOWNLOAD_DIR}
	curl -o ${GITLEAKS_DOWNLOAD_DIR}/${GITLEAKS_ARTIFACT} -L https://github.com/zricethezav/gitleaks/releases/download/v${GITLEAKS_VERSION}/${GITLEAKS_ARTIFACT}
	tar -xvzf ${GITLEAKS_DOWNLOAD_DIR}/${GITLEAKS_ARTIFACT} --directory ${GITLEAKS_DOWNLOAD_DIR}
	cp ${GITLEAKS_DOWNLOAD_DIR}/gitleaks ${GITLEAKS}
	rm -rf ${GITLEAKS_DOWNLOAD_DIR}
	chmod 755 $@

upgrade:
	brew uninstall gitleaks || rm -f ${GITLEAKS} && rm -f ${HOME}/bin/gitleaks
	make ${GITLEAKS}

FORCE:
