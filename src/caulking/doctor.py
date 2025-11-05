# src/caulking/doctor.py
from __future__ import annotations

import shutil
import subprocess  # nosec B404
from pathlib import Path
from typing import Any

import typer
import yaml

app = typer.Typer(help="Run diagnostics on Caulking installation and hooks.")

SAFE_BINS = {"git", "uv", "pre-commit", "gitleaks", "ruff", "bandit", "mypy", "pytest"}
PRECOMMIT_FILE = Path(".pre-commit-config.yaml")
EXPECTED_GITLEAKS_ENTRY = "gitleaks git --pre-commit"
EXPECTED_GITLEAKS_REV = "v8.29.0"


# ------------------------------- helpers -------------------------------------
def _resolve_cmd(cmd: list[str]) -> list[str]:
    if not cmd:
        raise ValueError("Empty command")
    binary = cmd[0]
    if binary not in SAFE_BINS:
        raise ValueError(f"Unsafe binary requested: {binary}")
    resolved = shutil.which(binary)
    if not resolved:
        raise FileNotFoundError(binary)
    abs_bin = str(Path(resolved).resolve(strict=False))
    return [abs_bin, *cmd[1:]]


def _run(cmd: list[str], cwd: Path | None = None) -> subprocess.CompletedProcess[str]:
    """Execute a validated command with shell disabled and absolute binary path."""
    try:
        safe = _resolve_cmd(cmd)
        # validated absolute binary; shell disabled; no user input in args
        return subprocess.run(  # nosec
            safe,
            cwd=str(cwd) if cwd else None,
            check=False,
            text=True,
            capture_output=True,
        )
    except FileNotFoundError as err:
        typer.secho(f"✗ Missing binary: {cmd[0]}", fg=typer.colors.RED)
        raise typer.Exit(code=1) from err
    except subprocess.SubprocessError as err:
        typer.secho(f"✗ Subprocess error while running {cmd[0]}: {err}", fg=typer.colors.RED)
        raise typer.Exit(code=1) from err


def _check_binary(binary: str) -> str:
    result = _run([binary, "--version"])
    if result.returncode != 0:
        typer.secho(f"✗ {binary} not available or failed to run", fg=typer.colors.RED)
        raise typer.Exit(code=1)
    version_line = result.stdout.strip().splitlines()[0] if result.stdout else binary
    typer.secho(f"✓ {version_line}", fg=typer.colors.GREEN)
    return version_line


def _check_toolchain() -> None:
    for bin_name in sorted(SAFE_BINS):
        _check_binary(bin_name)


def _load_precommit() -> dict[str, Any]:
    if not PRECOMMIT_FILE.exists():
        typer.secho("✗ Missing .pre-commit-config.yaml", fg=typer.colors.RED)
        raise typer.Exit(code=1)
    try:
        data: dict[str, Any] = yaml.safe_load(PRECOMMIT_FILE.read_text())
        if not isinstance(data, dict):
            raise TypeError("pre-commit config must be a mapping")
        return data
    except Exception as err:
        typer.secho(f"✗ Failed to parse {PRECOMMIT_FILE}: {err}", fg=typer.colors.RED)
        raise typer.Exit(code=1) from err


def _find_gitleaks_repo(cfg: dict[str, Any]) -> dict[str, Any]:
    repos = cfg.get("repos", []) or []
    matches = [
        r for r in repos if isinstance(r, dict) and str(r.get("repo", "")).endswith("/gitleaks")
    ]
    if not matches:
        typer.secho("✗ Gitleaks hook not found in pre-commit config", fg=typer.colors.RED)
        raise typer.Exit(code=1)
    repo_block = matches[0]
    if not isinstance(repo_block, dict):
        typer.secho("✗ Invalid gitleaks repo block type", fg=typer.colors.RED)
        raise typer.Exit(code=1)
    return repo_block


def _verify_gitleaks_hook(gl_repo: dict[str, Any]) -> None:
    rev = str(gl_repo.get("rev", ""))
    hooks = gl_repo.get("hooks", []) or []
    if not hooks or not isinstance(hooks, list) or not isinstance(hooks[0], dict):
        typer.secho("✗ Gitleaks hooks array is empty or invalid", fg=typer.colors.RED)
        raise typer.Exit(code=1)

    hook: dict[str, Any] = hooks[0]
    entry = str(hook.get("entry", ""))
    args = hook.get("args", []) or []
    pass_filenames = hook.get("pass_filenames")

    if entry != EXPECTED_GITLEAKS_ENTRY:
        typer.secho(f"✗ Unexpected gitleaks entry: {entry}", fg=typer.colors.RED)
        typer.secho(f"  → Expected: {EXPECTED_GITLEAKS_ENTRY}", fg=typer.colors.YELLOW)
        raise typer.Exit(code=1)

    if rev != EXPECTED_GITLEAKS_REV:
        typer.secho(
            f"⚠ gitleaks version mismatch (found {rev}, expected {EXPECTED_GITLEAKS_REV})",
            fg=typer.colors.YELLOW,
        )

    if any("--source" in str(a) for a in args):
        typer.secho("✗ Detected legacy --source flag in gitleaks args", fg=typer.colors.RED)
        raise typer.Exit(code=1)

    if pass_filenames is not False:
        typer.secho("✗ gitleaks hook must have pass_filenames: false", fg=typer.colors.RED)
        raise typer.Exit(code=1)

    typer.secho("✓ pre-commit gitleaks hook looks valid", fg=typer.colors.GREEN)


def _verify_git_hooks_present() -> None:
    hook_dir = Path(".git/hooks")
    missing: list[str] = []
    for hook_name in ("pre-commit", "pre-push"):
        path = hook_dir / hook_name
        if not path.exists():
            missing.append(hook_name)
        else:
            typer.secho(f"✓ Found Git hook: {hook_name}", fg=typer.colors.GREEN)
    if missing:
        typer.secho(f"✗ Missing Git hook(s): {', '.join(missing)}", fg=typer.colors.RED)
        raise typer.Exit(code=1)


def _dry_run_gitleaks() -> None:
    result = _run(
        [
            "gitleaks",
            "git",
            "--pre-commit",
            "--no-banner",
            "--no-color",
            "--log-level=error",
            "--redact",
            "--config=rules/gitleaks.toml",
        ]
    )
    if result.returncode != 0:
        typer.secho("✗ gitleaks run failed", fg=typer.colors.RED)
        if result.stderr:
            typer.echo(result.stderr.strip())
        if result.stdout:
            typer.echo(result.stdout.strip())
        raise typer.Exit(code=1)
    typer.secho("✓ gitleaks dry run executed cleanly", fg=typer.colors.GREEN)


# --------------------------------- CLI ---------------------------------------
@app.command()
def main() -> None:
    """Validate toolchain, hooks, and Caulking environment integrity."""
    typer.secho("🔍 Running Caulking Doctor\n", fg=typer.colors.CYAN, bold=True)
    _check_toolchain()
    cfg = _load_precommit()
    gl_repo = _find_gitleaks_repo(cfg)
    _verify_gitleaks_hook(gl_repo)
    _verify_git_hooks_present()
    _dry_run_gitleaks()
    typer.secho("\n✅ Caulking environment is healthy.", fg=typer.colors.BRIGHT_GREEN, bold=True)


if __name__ == "__main__":
    app()
