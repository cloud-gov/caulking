GIT_SUPPORT_PATH=  ${HOME}/.git-support
RAW_GITLEAKS= https://raw.githubusercontent.com/zricethezav/gitleaks
GITLEAKS_VERSION=v4.1.0
NOW=$(shell date)
ME=$(shell whoami)

INSTALL_TARGETS= hook global_hooks patterns

.PHONY: $(INSTALL_TARGETS) clean install audit

install: /usr/local/bin/gitleaks $(INSTALL_TARGETS)

clean: 
	/bin/rm -f ${GIT_SUPPORT_PATH}/hooks/pre-commit

clean_seekrets:
	/bin/rm -rf ${GIT_SUPPORT_PATH}/seekret-rules
	-git config --global --unset gitseekret.rulesenabled
	-git config --global --unset gitseekret.rulespath
	-git config --global --unset gitseekret.exceptionsfile
	-git config --global --unset gitseekret.version

audit: /usr/local/bin/bats /usr/local/bin/pcregrep 
	@echo "${ME} / ${NOW}"
	bats -t caulked.bats

hook: ${GIT_SUPPORT_PATH}/hooks/pre-commit

global_hooks: 
	git config --global hooks.gitleaks true
	git config --global core.hooksPath ${GIT_SUPPORT_PATH}/hooks

patterns: ${GIT_SUPPORT_PATH}/gitleaks.toml

${GIT_SUPPORT_PATH}/gitleaks.toml: leaky-repo.toml local.toml
	cat $^ > $@

leaky-repo.toml: FORCE
	curl --silent ${RAW_GITLEAKS}/${GITLEAKS_VERSION}/examples/$@ -o $@

${GIT_SUPPORT_PATH}/hooks/pre-commit: pre-commit.sh
	mkdir -p ${GIT_SUPPORT_PATH}/hooks
	install -m 0755 -cv $< $@
	cp $< $@

/usr/local/bin/bats:
	brew install bats-core

/usr/local/bin/pcregrep:
	brew install pcre

/usr/local/bin/%:
	brew install $(@F)

FORCE:
