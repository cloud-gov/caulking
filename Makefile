CAULKING_VERSION=1.3.1 2022-01-16
GITLEAKS_VERSION=8.8.4
GITLEAKS_ARTIFACT="gitleaks_${GITLEAKS_VERSION}_darwin_x64.tar.gz"
GITLEAKS_CHECKSUM=509430dada69ee4314068847a8a424d4102defc23fd5714330d36366796feef7
NOW=$(shell date)
ME=$(shell whoami)

GIT_SUPPORT_PATH=  ${HOME}/.git-support
HOOKS=${GIT_SUPPORT_PATH}/hooks
PRECOMMIT=${GIT_SUPPORT_PATH}/hooks/pre-commit
PATTERNS=${GIT_SUPPORT_PATH}/gitleaks.toml
GITLEAKS= ${HOME}/bin/gitleaks

INSTALL_TARGETS= ${PATTERNS} ${PRECOMMIT} ${GITLEAKS}

.PHONY: clean audit global_hooks

install: $(INSTALL_TARGETS) global_hooks

audit: /usr/local/bin/bats /usr/local/bin/pcregrep ${GITLEAKS} $(INSTALL_TARGETS)
	@test $$(${GITLEAKS} version) = "${GITLEAKS_VERSION}" || ( echo "ERROR -- RUN: 'make install'" && false )
	@echo ${CAULKING_VERSION}
	@echo "${ME} / ${NOW}"
	bats -p caulked.bats

clean:
	/bin/rm -rf ${GIT_SUPPORT_PATH}
	git config --global --unset hooks.gitleaks
	git config --global --unset core.hooksPath

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

/usr/local/bin/bats:
	brew install bats-core

/usr/local/bin/pcregrep:
	brew install pcre

${HOME}/bin/gitleaks:
	mkdir -p ${HOME}/bin
	curl -o ${HOME}/bin/${GITLEAKS_ARTIFACT} -L https://github.com/zricethezav/gitleaks/releases/download/v${GITLEAKS_VERSION}/${GITLEAKS_ARTIFACT}
	tar -xvzf ${HOME}/bin/${GITLEAKS_ARTIFACT} --directory ${HOME}/bin
	chmod 755 $@

upgrade:
	brew uninstall gitleaks || rm -f ${GITLEAKS} && rm -f ${HOME}/bin/gitleaks
	make ${GITLEAKS}

FORCE:
