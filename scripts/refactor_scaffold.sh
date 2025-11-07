#!/usr/bin/env bash
# scripts/refactor_scaffold.sh
# Refactor cloud-gov/caulking to new layout (backup first; macOS/Linux-safe).

set -euo pipefail

DRY_RUN=1
[[ "${1:-}" == "--apply" ]] && DRY_RUN=0

say()  { printf "%s\n" "$*"; }
doit() { [[ $DRY_RUN -eq 1 ]] && say "DRY: $*" || eval "$*"; }

ts="$(date +"%Y%m%d-%H%M%S")"
backup_dir=".refactor-backup/$ts"
mkdir -p "$backup_dir"

# --- helpers -----------------------------------------------------------------
backup_if_exists() {
  local p="$1"
  if [[ -e "$p" || -L "$p" ]]; then
    doit "mkdir -p \"$backup_dir/$(dirname "$p")\""
    doit "git mv -f \"$p\" \"$backup_dir/$p\" 2>/dev/null || mv -f \"$p\" \"$backup_dir/$p\""
    say "Backed up: $p -> $backup_dir/$p"
  fi
}

# --- files/dirs to remove or relocate ----------------------------------------
TO_REMOVE=(
  ".github"              # no GH Actions
  "org-scan"
  "test"                 # old bats vendored dir
  "caulked.bats"
  "development.bats"
  "test_helper.bash"
  "pre-commit.sh"
  "check_repos.sh"
)

# local.toml becomes rules/gitleaks.toml
RELOCATE_LOCAL_TOML="local.toml"

# --- perform removals ---------------------------------------------------------
for p in "${TO_REMOVE[@]}"; do
  backup_if_exists "$p"
done

# --- move local.toml into new rules path if present ---------------------------
if [[ -f "$RELOCATE_LOCAL_TOML" ]]; then
  doit "mkdir -p rules"
  doit "git mv \"$RELOCATE_LOCAL_TOML\" rules/gitleaks.toml 2>/dev/null || mv \"$RELOCATE_LOCAL_TOML\" rules/gitleaks.toml"
  say "Moved: $RELOCATE_LOCAL_TOML -> rules/gitleaks.toml"
fi

# --- create new structure -----------------------------------------------------
NEW_DIRS=(
  "src/caulking"
  "rules"
  "templates"
  "tests/corpus/positive"
  "tests/corpus/false-positives"
  "ci/concourse"
  "docs"
  "scripts"
)

for d in "${NEW_DIRS[@]}"; do
  doit "mkdir -p \"$d\""
done

# --- drop .gitkeep files so empty dirs commit cleanly -------------------------
for d in "${NEW_DIRS[@]}"; do
  doit "touch \"$d/.gitkeep\""
done

# --- seed minimal scaffolding files (empty/safe) ------------------------------
seed() {
  # content is intentionally unused here (placeholder for future expansion)
  # shellcheck disable=SC2034
  local path="$1" content="$2"
    if [[ ! -e "$path" ]]; then
    doit "printf \"%s\" > \"$path\""
    say "Created: $path"
  fi
}

seed "pyproject.toml" "\
[project]
name = \"caulking\"
version = \"0.0.0\"
requires-python = \">=3.12\"
description = \"Cloud.gov secret scanning + hygiene tooling\"
readme = \"README.md\"
authors = [{name=\"Cloud.gov\"}]
dependencies = []
[project.scripts]
caulking = \"caulking.cli:main\"
[build-system]
requires = [\"setuptools>=68\", \"wheel\"]
build-backend = \"setuptools.build_meta\"
"

seed "src/caulking/__init__.py" ".__version__ = \"0.0.0\"\n"
seed "src/caulking/cli.py" "\
def main():
    print(\"caulking CLI placeholder\")\n"
seed "templates/.pre-commit-config.caulking.yaml" "# filled by 'caulking install'\n"
seed "rules/.gitleaksignore.example" "# fingerprint-based ignores here\n"
seed "tests/test_scanners.py" "# pytest placeholder\n"
seed "ci/concourse/task.yml" "# Concourse task placeholder; fill in pipeline\n"

# --- gentle Makefile targets (add or append) ----------------------------------
if [[ -f "Makefile" ]]; then
  backup_if_exists "Makefile"
fi
seed "Makefile" "\
.PHONY: caulking/install caulking/scan
caulking/install:
\tpython -m pip install -e . pre-commit
\t# caulking install  # add when CLI is implemented
\t@echo \"Install complete.\"

caulking/scan:
\t@echo \"Run scanners locally (stub)\"
"

say ""
if [[ $DRY_RUN -eq 1 ]]; then
  say "Dry-run complete. Re-run with:  bash scripts/refactor_scaffold.sh --apply"
else
  say "Applied. Review changes, then commit:"
  say "  git add -A && git commit -m \"chore(refactor): scaffold new caulking layout; archive legacy files to $backup_dir\""
fi
