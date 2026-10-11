# proxystack development tasks. On Windows, run these from Git Bash or CI.
SHELLCHECK ?= shellcheck
SHFMT ?= shfmt
BATS ?= bats
SHFMT_FLAGS := -i 2 -ci

SH_SRC := proxystack.sh $(wildcard lib/*.sh) $(wildcard locales/*.sh) $(wildcard scripts/*.sh)

.PHONY: test test-unit test-integration lint fmt fmt-check check release-assets

test: test-unit

test-unit:
	$(BATS) tests/unit

test-integration:
	$(BATS) tests/integration

lint:
	$(SHELLCHECK) $(SH_SRC)

fmt:
	$(SHFMT) -w $(SHFMT_FLAGS) $(SH_SRC) $(wildcard tests/helpers/*.bash)

fmt-check:
	$(SHFMT) -d $(SHFMT_FLAGS) $(SH_SRC) $(wildcard tests/helpers/*.bash)

check: lint fmt-check test-unit

release-assets:
	bash scripts/package-release.sh
