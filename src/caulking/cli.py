from __future__ import annotations

import os
import shutil

# subprocess is required; all uses are validated and shell=False
import subprocess  # nosec B404
from dataclasses import dataclass
from pathlib import Path
from typing import Annotated

import typer

from .config import CaulkingConfig

app = typer.Typer(add_completion=False, no_args_is_help=True)

# ---------------------------- helpers ---------------------------------

# Only allow these commands to be launched by this CLI
SAFE_BINS = {"git", "uv", "pre-commit", "gitleaks", "detect-secrets"}


def _resolve_cmd(cmd: list[str]) -> list[str]:
    """
    Validate and resolve the binary to an absolute path.
    Refuse to run anything outside SAFE_BINS.
    """
    if not cmd:
        raise typer.Exit(2)
    bin_name = cmd[0]
    if bin_name not in SAFE_BINS:
        typer.echo(f"error: refusing to execute unsafe binary: {bin_name}", err=True)
        raise typer.Exit(2)
    abs_path = shutil.which(bin_name)
    if not abs_path:
        typer.echo(f"error: required tool not found in PATH: {bin_name}", err=True)
        raise typer.Exit(127)
    cmd[0] = abs_path
    return cmd


def run(cmd: list[str], cwd: Path | None = None, check: bool = False) -> int:
    """
    Run a validated command (SAFE_BINS) with shell=False.
    Returns exit code; raises Exit if check=True and rc!=0.
    """
    safe = _resolve_cmd(cmd)
    # validated absolute binary; shell=False
    proc = subprocess.run(  # nosec B603
        safe, cwd=str(cwd) if cwd else None, check=False
    )

    if check and proc.returncode != 0:
        raise typer.Exit(proc.returncode)
    return proc.returncode


def ensure_file(path: Path, content: str, mode: int | None = None) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    if not path.exists():
        path.write_text(content, encoding="utf-8")
    if mode is not None:
        os.chmod(path, mode)


def copytree(src: Path, dst: Path) -> None:
    dst.parent.mkdir(parents=True, exist_ok=True)
    if dst.exists():
        shutil.rmtree(dst)
    shutil.copytree(src, dst)


def which(bin_name: str) -> str | None:
    return shutil.which(bin_name)


def uv_run_available() -> bool:
    return which("uv") is not None


def git_config_get(scope: str, key: str) -> str:
    git = which("git")
    if not git:
        return ""
    try:
        # absolute git path; shell=False; validated against SAFE_BINS
        out = subprocess.check_output(  # nosec B603
            [git, "config", f"--{scope}", key],
            text=True,
        ).strip()

    except subprocess.CalledProcessError:
        return ""
    return out


def git_config_set(scope: str, key: str, value: str) -> None:
    run(["git", "config", f"--{scope}", key, value], check=True)


# ------------------------ existing commands ---------------------------


@app.command(help="Install/merge repo-local pre-commit config and install hooks.")
def install(
    config_template: Annotated[
        Path,
        typer.Option(
            "--template",
            help="Template pre-commit config to seed when none exists.",
        ),
    ] = Path("templates/.pre-commit-config.caulking.yaml"),
    force: Annotated[
        bool,
        typer.Option("--force", help="Overwrite existing .pre-commit-config.yaml."),
    ] = False,
) -> None:
    dst = Path(".pre-commit-config.yaml")
    if dst.exists() and not force:
        typer.echo("Found existing .pre-commit-config.yaml; leaving as-is.")
    else:
        if not config_template.exists():
            typer.echo(f"Template not found: {config_template}", err=True)
            raise typer.Exit(2)
        dst.write_text(config_template.read_text(encoding="utf-8"), encoding="utf-8")
        typer.echo("Seeded .pre-commit-config.yaml from template.")
    if not uv_run_available():
        typer.echo("warning: uv not found; falling back to pre-commit if present.")
        rc = run(["pre-commit", "install", "-t", "pre-commit", "-t", "pre-push"])
    else:
        rc = run(["uv", "run", "pre-commit", "install", "-t", "pre-commit", "-t", "pre-push"])
    raise typer.Exit(rc)


@app.command(help="Run gitleaks + detect-secrets with repo rules.")
def scan(
    redact: Annotated[bool, typer.Option(help="Redact secrets in output.")] = True,
    sarif: Annotated[Path | None, typer.Option(help="Optional SARIF output path.")] = None,
) -> None:
    cfg = CaulkingConfig.load()
    overall_rc = 0

    # gitleaks
    if cfg.enable.gitleaks:
        args = [
            "gitleaks",
            "detect",
            "--no-banner",
            "--report-format",
            "json",
            "--config=rules/gitleaks.toml",
            "--source=.",
        ]
        if redact:
            args.append("--redact")
        rc = run(args)
        overall_rc = max(overall_rc, rc)

    # detect-secrets (baseline)
    if cfg.enable.detect_secrets and Path("rules/detect-secrets.baseline").exists():
        rc = run(["detect-secrets", "scan", "--baseline", "rules/detect-secrets.baseline", "."])
        overall_rc = max(overall_rc, rc)

    if sarif:
        ensure_file(sarif, '{"version":"2.1.0","runs":[]}\n')

    raise typer.Exit(overall_rc)


@app.command(help="Set CAULKING_BYPASS=1 in the environment for this process.")
def bypass(
    reason: Annotated[str | None, typer.Option("--reason", help="Short human reason.")] = None,
) -> None:
    os.environ["CAULKING_BYPASS"] = "1"
    if reason:
        os.environ["CAULKING_REASON"] = reason
    typer.echo(
        "Bypass enabled for this process. Use with: CAULKING_BYPASS=1 git commit -m '...'\n"
        "Prefer a dated .caulking/override.approved file for auditable PR-level bypass."
    )


# ----------------------- new client-wide commands -----------------------------

GUARDED_HOOK = """#!/usr/bin/env bash
# Caulking guarded pre-commit hook (global template).
# Behavior:
#   - Run Ruff first (fast fail)
#   - If repo has .pre-commit-config.yaml -> run pre-commit (blocking)
#   - Else -> run gitleaks with global Caulking rules (blocking)
# Bypass:
#   - env:  CAULKING_BYPASS=1 git commit …
#   - file: .caulking/override.approved (first line ISO date: 2025-11-30)
set -euo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
CAULKING_DIR="${HOME}/.caulking"
RULES="${CAULKING_DIR}/rules/gitleaks.toml"
OVERRIDE_FILE="${REPO_ROOT}/.caulking/override.approved"

die() { printf '%s\\n' "$*" >&2; exit 1; }

# explicit bypass
if [[ "${CAULKING_BYPASS:-}" == "1" ]]; then
  printf 'Caulking: bypass via env set. Proceeding.\\n' >&2
  exit 0
fi

if [[ -f "$OVERRIDE_FILE" ]]; then
  EXP_DATE="$(head -n1 "$OVERRIDE_FILE" | tr -d '[:space:]')"
  if [[ "$EXP_DATE" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]]; then
    TODAY="$(date -u +%F)"
    if [[ "$EXP_DATE" < "$TODAY" ]]; then
      printf 'Caulking: override.approved expired (%s < %s). Blocking.\\n' "$EXP_DATE" "$TODAY" >&2
    else
      printf 'Caulking: override.approved valid until %s. Proceeding.\\n' "$EXP_DATE" >&2
      exit 0
    fi
  else
    printf 'Caulking: invalid override.approved header; expected ISO date on first line.\\n' >&2
  fi
fi

# Ruff first (fast, optional). Do not hard-fail if Ruff is missing; fail if it *finds* issues.
if command -v uv >/dev/null 2>&1; then
  if uv run ruff check --quiet; then :; else
    echo 'Caulking: Ruff found issues; commit blocked.' >&2
    exit 1
  fi
elif command -v ruff >/dev/null 2>&1; then
  if ruff check --quiet; then :; else
    echo 'Caulking: Ruff found issues; commit blocked.' >&2
    exit 1
  fi
fi

# If repo declares pre-commit config, defer to it
if [[ -f "${REPO_ROOT}/.pre-commit-config.yaml" ]]; then
  if command -v uv >/dev/null 2>&1; then
    exec uv run pre-commit run --hook-stage=pre-commit
  elif command -v pre-commit >/dev/null 2>&1; then
    exec pre-commit run --hook-stage=pre-commit
  else
    die "Caulking: pre-commit not found (install uv or pre-commit)."
  fi
fi

# fallback: run gitleaks with global rules
if ! command -v gitleaks >/dev/null 2>&1; then
  die "Caulking: gitleaks not found in PATH. Install it (brew install gitleaks)."
fi
if [[ ! -f "$RULES" ]]; then
  die "Caulking: missing rules at $RULES (run caulking bootstrap-client again)."
fi

printf 'Caulking: running fallback gitleaks scan with global rules.\\n' >&2
exec gitleaks detect --no-banner --redact --config="$RULES" --source="${REPO_ROOT}"
"""


@dataclass
class BootstrapOutcome:
    template_dir: Path
    hook_path: Path
    rules_src: Path
    rules_dst: Path
    previous_template: str


@app.command(
    "bootstrap-client", help="One-time: install global git template + seed ~/.caulking/rules."
)
def bootstrap_client() -> None:
    # Require uv strongly (for consistent pre-commit invocation)
    if not uv_run_available():
        typer.echo(
            "error: uv not found in PATH. Install uv (e.g., brew install uv) and re-run.", err=True
        )
        raise typer.Exit(2)

    # Seed ~/.caulking/rules from this repo's ./rules
    repo_rules = Path("rules")
    if not repo_rules.exists():
        typer.echo(
            "error: ./rules not found in this repo. Run from the caulking repo root.", err=True
        )
        raise typer.Exit(2)
    caulking_home = Path.home() / ".caulking"
    rules_dst = caulking_home / "rules"
    copytree(repo_rules, rules_dst)

    # Install template with guarded pre-commit (Ruff-first)
    template_dir = Path.home() / ".git-template"
    hooks_dir = template_dir / "hooks"
    ensure_file(hooks_dir / "pre-commit", GUARDED_HOOK, mode=0o755)

    # Configure git
    prev_template = git_config_get("global", "init.templateDir")
    git_config_set("global", "init.templateDir", str(template_dir))

    # Print outcome
    outcome = BootstrapOutcome(
        template_dir=template_dir,
        hook_path=hooks_dir / "pre-commit",
        rules_src=repo_rules.resolve(),
        rules_dst=rules_dst.resolve(),
        previous_template=prev_template,
    )
    typer.echo(
        "Bootstrap complete:\n"
        f"  - rules: {outcome.rules_src} -> {outcome.rules_dst}\n"
        f"  - template: {outcome.template_dir}\n"
        f"  - hook: {outcome.hook_path}\n"
        f"  - previous init.templateDir: {outcome.previous_template or '<unset>'}\n\n"
        "New clones/inits will pick up the guard automatically.\n"
        "Existing repos: see `caulking ensure-all-repos` to retrofit hooks where configs exist."
    )


@app.command("ensure-all-repos", help="Install pre-commit hooks across existing repos under ROOT.")
def ensure_all_repos(
    root: Annotated[
        Path, typer.Argument(..., exists=True, file_okay=False, dir_okay=True, readable=True)
    ],
    update: Annotated[
        bool, typer.Option("--update", help="Run `pre-commit autoupdate` per repo.")
    ] = False,
    maxdepth: Annotated[int, typer.Option(help="How deep to scan for repos.")] = 4,
) -> None:
    if not uv_run_available():
        typer.echo("error: uv not found in PATH. Install uv first.", err=True)
        raise typer.Exit(2)

    scanned = 0
    changed = 0
    for git_dir in root.rglob(".git"):
        rel = git_dir.relative_to(root)
        if len(rel.parts) > maxdepth:
            continue
        repo = git_dir.parent
        scanned += 1
        cfg = repo / ".pre-commit-config.yaml"
        if cfg.exists():
            typer.echo(f"Installing pre-commit hooks in: {repo}")
            run(
                ["uv", "run", "pre-commit", "install", "-t", "pre-commit", "-t", "pre-push"],
                cwd=repo,
                check=True,
            )
            if update:
                run(["uv", "run", "pre-commit", "autoupdate"], cwd=repo)
            changed += 1
    typer.echo(f"Scanned {scanned} repos. Installed/updated hooks in {changed} repos.")


@app.command(help="Diagnose client setup: template, hook, rules, and common pitfalls.")
def doctor() -> None:
    template_dir = git_config_get("global", "init.templateDir") or "<unset>"
    hook_path = Path(template_dir) / "hooks" / "pre-commit" if template_dir != "<unset>" else None
    gitleaks_path = which("gitleaks") or "<missing>"
    uv_path = which("uv") or "<missing>"
    rules_path = Path.home() / ".caulking" / "rules" / "gitleaks.toml"

    typer.echo("Caulking doctor\n----------------")
    typer.echo(f"uv: {uv_path}")
    typer.echo(f"gitleaks: {gitleaks_path}")
    typer.echo(f"git init.templateDir: {template_dir}")
    typer.echo(f"global hook exists: {hook_path if hook_path and hook_path.exists() else '<none>'}")
    typer.echo(f"global rules: {rules_path if rules_path.exists() else '<missing>'}")

    hooks_path = git_config_get("global", "core.hooksPath")
    if hooks_path:
        typer.echo(
            f"warning: global core.hooksPath is set to {hooks_path}. "
            "Caulking uses init.templateDir instead; consider unsetting the global hooksPath."
        )


if __name__ == "__main__":  # pragma: no cover
    app()
