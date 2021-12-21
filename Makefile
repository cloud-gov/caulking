CAULKING_VERSION=1.3.0 2021-12-21
GITLEAKS_VERSION=7.6.1
GITLEAKS_CHECKSUM=5e51a33beb6f358970815ecbbc40c6c28fb785ef6342da9a689713f99fece54f
NOW=$(shell date)
ME=$(shell whoami)

GIT_SUPPORT_PATH=  ${HOME}/.git-support
HOOKS=${GIT_SUPPORT_PATH}/hooks
PRECOMMIT=${GIT_SUPPORT_PATH}/hooks/pre-commit
PATTERNS=${GIT_SUPPORT_PATH}/gitleaks.toml
GITLEAKS= /usr/local/bin/gitleaks

INSTALL_TARGETS= ${PATTERNS} ${PRECOMMIT} ${GITLEAKS}

.PHONY: clean audit global_hooks

install: $(INSTALL_TARGETS) global_hooks

audit: /usr/local/bin/bats /usr/local/bin/pcregrep /usr/local/bin/wget ${GITLEAKS} $(INSTALL_TARGETS)
	@test $$(gitleaks --version) = ${GITLEAKS_VERSION} || make upgrade
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

/usr/local/bin/wget:
	brew install wget

/usr/local/bin/gitleaks:
	wget https://github.com/zricethezav/gitleaks/releases/download/v${GITLEAKS_VERSION}/gitleaks-darwin-amd64
	mkdir -p ${HOME}/bin
	mv gitleaks-darwin-amd64 ${HOME}/bin/gitleaks
	chmod 755 ${HOME}/bin/gitleaks
	ln -s ${HOME}/bin/gitleaks ${GITLEAKS}

upgrade:
	brew uninstall gitleaks || rm -f ${GITLEAKS} && rm -f ${HOME}/bin/gitleaks
	make ${GITLEAKS}

FORCE:
