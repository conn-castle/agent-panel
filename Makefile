.PHONY: help build build-dev test coverage clean regen hooks preflight test-coverage-gate

help:
	@echo "AgentPanel development commands:"
	@echo ""
	@echo "  make build               Build app + CLI (Debug, no code signing)"
	@echo "  make build-dev           Build dev app identity (Debug, no code signing)"
	@echo "  make test                Run tests without coverage (fast local iteration)"
	@echo "  make coverage            Run tests with coverage gate + per-file summary"
	@echo "  make clean               Remove build artifacts"
	@echo "  make regen               Regenerate Xcode project from project.yml"
	@echo "  make hooks               Install git pre-commit hook"
	@echo "  make preflight           Validate release configuration"
	@echo "  make test-coverage-gate  Run coverage_gate.swift integration tests"

build:
	scripts/build.sh

build-dev:
	scripts/build_dev.sh

test:
	scripts/test.sh --no-coverage

coverage:
	scripts/test.sh

clean:
	scripts/clean.sh

regen:
	scripts/regenerate_xcodeproj.sh

hooks:
	scripts/install_git_hooks.sh

preflight:
	scripts/ci_preflight.sh

test-coverage-gate:
	scripts/test_coverage_gate.sh
