# Troubleshooting

Common issues and solutions for Caulking and reusable pre-commit hooks. If you encounter and solve an issue not listed here, please add it!

## Table of Contents

- [Hook Failures](#hook-failures)
- [Installation & Toolchain Bootstrap Issues](#installation--toolchain-bootstrap-issues)
- [Caulking Global Hook Integration](#caulking-global-hook-integration)
- [Tool-Specific Issues](#tool-specific-issues)
- [Emergency Bypass](#emergency-bypass)

---

## Hook Failures

### "How do I know which hook failed?"

Pre-commit output shows the hook name in the failure message:

```
check-yaml...............................................................Passed
trailing-whitespace......................................................Passed
shellcheck...............................................................Failed
- hook id: shellcheck
- exit code: 1
- files were modified by this hook
```

The **hook id** (`shellcheck` in this example) tells you which tool failed.

### "The error message doesn't make sense"

Run the tool directly for more verbose output:

```bash
# For shellcheck
shellcheck -x path/to/script.sh

# For ruff
ruff check path/to/file.py --show-source

# For eslint
npx eslint path/to/file.js

# For hadolint
hadolint Dockerfile
```

### "Hook modified my files but I don't see changes"

Some hooks auto-fix issues (e.g., `trailing-whitespace`, `end-of-file-fixer`, `ruff-format`). Check `git diff` to see what changed:

```bash
git diff
```

If the changes look correct, stage and commit again:

```bash
git add -u
git commit -m "your message"
```

### "Hook fails on files I didn't change"

By default, pre-commit only runs on staged files. If you're seeing failures on unstaged files, you may have run:

```bash
pre-commit run --all-files  # Runs on ALL files, not just staged
```

To run only on staged files:

```bash
pre-commit run  # Default: staged files only
```

---

## Installation & Toolchain Bootstrap Issues

### "Executable not found" or missing linter when committing

Run `caulking doctor` in your repository to inspect which profiles and tools are required, and `caulking bootstrap` to install missing Homebrew bundles:

```bash
# Diagnose missing tools or version floor mismatches
./bin/caulking doctor --repo /path/to/repo

# Install the repository's declared .caulking-profiles bundles (or specify --profile)
./bin/caulking bootstrap --repo /path/to/repo
```

You can also install selective Brewfile bundles directly:

```bash
brew bundle --file=brewfiles/baseline.Brewfile --no-upgrade
brew bundle --file=brewfiles/shell.Brewfile --no-upgrade
brew bundle --file=brewfiles/python.Brewfile --no-upgrade
brew bundle --file=brewfiles/go.Brewfile --no-upgrade
brew bundle --file=brewfiles/container.Brewfile --no-upgrade
```

### "brew bundle fails with 'formula not found'"

Some tools (such as `hashicorp/tap/terraform` or `terraform-linters/tap/tflint` in `brewfiles/terraform.Brewfile`) use Homebrew taps. If you see formula errors:

```bash
# Refresh Homebrew
brew update

# Re-run the selective bundle
brew bundle --file=brewfiles/<profile>.Brewfile --no-upgrade
```

### "Tool not found" after Brewfile install or in GUI Git clients

Ensure your shell `PATH` includes Homebrew, or run hooks via `./bin/caulking run` which normalizes `/opt/homebrew/bin` and `/usr/local/bin` automatically:

```bash
# For Apple Silicon Macs
eval "$(/opt/homebrew/bin/brew shellenv)"

# For Intel Macs
eval "$(/usr/local/bin/brew shellenv)"
```

Add this to your `~/.zshrc` or `~/.bashrc` for persistence.

### "Go tools (gosec, govulncheck) not found"

Install the Go bundle via `brewfiles/go.Brewfile` (or `caulking bootstrap --profile go`), or install with `go install`:

```bash
brew bundle --file=brewfiles/go.Brewfile --no-upgrade
# Or via Go toolchain:
go install golang.org/x/vuln/cmd/govulncheck@latest
go install github.com/securego/gosec/v2/cmd/gosec@latest
```

If using `go install`, ensure `$GOPATH/bin` is in your `PATH`:

```bash
export PATH="$PATH:$(go env GOPATH)/bin"
```

For Linux/CI environments without pre-installed Go tools, use the `-selfcontained` hook variants (`gofmt-selfcontained`, `go-vet-selfcontained`, `gosec-selfcontained`, `govulncheck-selfcontained`) documented in [ADR-0008](docs/adr/ADR-0008-selfcontained-hook-variants.md).

### "PyYAML not found" when `check-yaml` runs

Install the baseline bundle (`brew bundle --file=brewfiles/baseline.Brewfile --no-upgrade`, which includes `pyyaml`), or use `check-yaml-selfcontained` (see [ADR-0010](docs/adr/ADR-0010-selfcontained-python-syntax-checks.md)) which runs in an isolated Python environment with `PyYAML==6.0.3` pinned.

### "Node tools (eslint, prettier) not found"

JavaScript tools run via `npx` and expect project-local installation in `node_modules/`:

```bash
# Install Node runtime via the javascript bundle if needed
brew bundle --file=brewfiles/javascript.Brewfile --no-upgrade

# In your project directory
npm install --save-dev eslint prettier
# or
yarn add --dev eslint prettier
```

---

## Caulking Global Hook Integration

### "Cowardly refusing to install hooks with core.hooksPath set"

**This is expected when Caulking is installed.** Caulking sets `core.hooksPath` globally (`~/.git-templates/hooks`) to enforce mandatory secrets detection (`gitleaks`) on every commit and push.

**Solution:** Do **not** run `pre-commit install`. Caulking's global hook wrapper automatically delegates to `prek` or `pre-commit` whenever your repository has a `.pre-commit-config.yaml`.

### "How do I verify caulking is working?"

```bash
# Check caulking status and health
make status
./bin/caulking doctor

# Check that global hooksPath is set
git config --global --get core.hooksPath
# Should show: /Users/<you>/.git-templates/hooks
```

### "Hooks aren't running at all"

1. Verify `.pre-commit-config.yaml` exists in your repo root
2. Run `./bin/caulking doctor --repo .` to verify `core.hooksPath`, `gitleaks`, and `prek`/`pre-commit`
3. Check global hooks path: `git config --global --get core.hooksPath`

If you are in a container or CI environment without Caulking's global hooks and want standalone `pre-commit`:

```bash
pre-commit run --all-files
```

---

## Tool-Specific Issues

### Shellcheck

**"SC2086: Double quote to prevent globbing"**

This is shellcheck warning about unquoted variables. Fix:

```bash
# Bad
echo $variable

# Good
echo "$variable"
```

To suppress if intentional:

```bash
# shellcheck disable=SC2086
echo $variable  # Globbing intentional here because...
```

### Ruff / Python

**"Line too long"**

Ruff enforces line length (default 88 chars). Options:

1. Break the line
2. Suppress inline: `# noqa: E501`
3. Configure in `pyproject.toml`:
   ```toml
   [tool.ruff]
   line-length = 120
   ```

**"Import sorting issues"**

Ruff can auto-fix imports:

```bash
ruff check --fix --select I path/to/file.py
```

### Hadolint / Dockerfile

**"DL3008: Pin versions in apt-get install"**

Hadolint wants pinned package versions for reproducibility:

```dockerfile
# Bad
RUN apt-get install -y curl

# Good (pin version)
RUN apt-get install -y curl=7.68.0-1ubuntu2.6

# Or suppress if pinning isn't practical
# hadolint ignore=DL3008
RUN apt-get install -y curl
```

### ESLint / JavaScript

**"Parsing error: Unexpected token"**

Usually means ESLint doesn't understand your syntax. Check:

1. Is TypeScript configured? Add `@typescript-eslint/parser`
2. Is JSX configured? Add appropriate parser options
3. Check `.eslintrc` / `eslint.config.js` for correct `parserOptions`

### Bandit / Python Security

**"B101: assert used"**

Bandit flags `assert` because it's removed in optimized bytecode.

For test files, suppress project-wide in `pyproject.toml`:

```toml
[tool.bandit]
exclude_dirs = ["tests"]
```

Or inline:

```python
assert condition  # nosec B101 - test assertion
```

---

## Emergency Bypass

### "I need to commit NOW and fix this later"

Skip specific `.pre-commit-config.yaml` hooks for a single commit:

```bash
SKIP=hook-id git commit -m "message"

# Skip multiple hooks
SKIP=shellcheck,hadolint git commit -m "message"
```

> **Warning:** Never export `SKIP=gitleaks` globally in your shell profile (`~/.zshrc`, `~/.bashrc`). Caulking's global hook wrapper honors `SKIP=gitleaks` as an emergency break-glass, so setting it globally disables workstation secret scanning across all repositories.

Skip ALL hooks (use sparingly in true emergencies):

```bash
git commit --no-verify -m "emergency: description

Bypassed hooks because: [explain why]
TODO: Fix [specific issue] in follow-up commit"
```

**Important:** Always document why you bypassed and create a follow-up task.

### "How do I find all bypasses in the repo?"

```bash
# Find commits that bypassed hooks
git log --grep="no-verify\|SKIP=" --oneline

# Find inline suppressions
grep -r "noqa\|nosec\|nosemgrep\|type: ignore\|shellcheck disable\|hadolint ignore\|eslint-disable\|nolint" \
  --include="*.py" --include="*.sh" --include="*.ts" --include="*.js" --include="*.go" .
```

---

## Still Stuck?

1. **Run diagnostics** — `./bin/caulking doctor` or `make verify`
2. **Check the tool's documentation** — Links in [ADR-0006](docs/adr/ADR-0006-language-security-tools.md)
3. **Run with verbose output** — Most tools have `-v` or `--verbose` flags
4. **Ask in Slack** — `#cloud-gov-atlas` or your team channel
5. **Add to this doc** — If you solve something tricky, add it here for others!
