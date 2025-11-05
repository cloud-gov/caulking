SHELL := /bin/bash

.PHONY: help
help:
	@echo "Targets:"
	@echo "  setup       - install dev deps via uv"
	@echo "  fmt         - format with ruff"
	@echo "  lint        - ruff lint"
	@echo "  type        - mypy"
	@echo "  sec         - bandit"
	@echo "  test        - pytest"
	@echo "  scan        - caulking scan (local gitleaks + detect-secrets)"
	@echo "  precommit   - run pre-commit on all files"
	@echo "  all         - fmt, lint, type, sec, test"

.PHONY: setup
setup:
	uv sync --all-extras --dev

.PHONY: fmt
fmt:
	uv run ruff format

.PHONY: lint
lint:
	uv run ruff check

.PHONY: type
type:
	uv run mypy src/caulking


.PHONY: sec
sec:
	uv run bandit -q -c pyproject.toml -r src

.PHONY: test
test:
	uv run pytest

.PHONY: scan
scan:
	uv run caulking scan

.PHONY: precommit
precommit:
	uv run pre-commit run --all-files

.PHONY: all
all: fmt lint type sec test
