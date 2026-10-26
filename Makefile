SHELL := /bin/bash
ROOT := $(realpath $(dir $(lastword $(MAKEFILE_LIST))))
TEST_JOBS ?= 4
.DEFAULT_GOAL := help
.PHONY: help doctor test test-luna test-swift app build dmg run

help:
	@printf '%s\n' 'Try Luna — macOS ISO preview' '' 'make doctor   Check QEMU and UEFI dependencies' 'make test     Launcher tests and inherited Swift/shell regression suites' 'make app      Build Try Luna.app locally' 'make dmg      Build an unsigned development DMG' 'make run      Build and open the launcher (does not start a VM)' '' './try-luna run --iso /absolute/path/lunaos.iso' './try-luna run    Boot the existing virtual disk'

doctor:
	@bash "$(ROOT)/try-luna" doctor

test: test-luna
	@$(MAKE) --no-print-directory -f "$(ROOT)/Makefile.upstream" -j$(TEST_JOBS) test-swift test-shell

test-luna:
	@bash "$(ROOT)/tests/try-luna.test.sh"
	@bash "$(ROOT)/tests/luna-factory-policy.test.sh"
	@bash "$(ROOT)/tests/luna-build-path.test.sh"

test-swift:
	@$(MAKE) --no-print-directory -f "$(ROOT)/Makefile.upstream" test-swift

app:
	@bash "$(ROOT)/macos/build-luna-app.sh"

build: app

dmg:
	@bash "$(ROOT)/macos/build-luna-app.sh" --dmg

run: app
	@open "$(ROOT)/dist/app.noindex/Try Luna.app"
