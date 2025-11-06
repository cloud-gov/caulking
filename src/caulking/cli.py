from __future__ import annotations

from pathlib import Path
from typing import Any

import typer
import yaml

from .detector import detect_repo
from .installer import plan_merge, write_precommit

app = typer.Typer(help="Caulking: enforce blocking secret scans + ecosystem guardrails.")


@app.command("smart-install")
def smart_install(
    config_path: str = typer.Option(".pre-commit-config.yaml", "--config", "-c"),
) -> None:
    """
    Install or augment pre-commit config with:
      - mandatory secrets scanning (gitleaks + detect-secrets baseline)
      - language-aware optional hooks (ruff/bandit, tflint, shellcheck, etc.)
    """
    root = Path(".").resolve()
    current: dict[str, Any] = {}
    cfg_file = Path(config_path)

    if cfg_file.exists():
        current = yaml.safe_load(cfg_file.read_text(encoding="utf-8")) or {}
        if not isinstance(current, dict):
            raise typer.Exit(code=2)

    d = detect_repo(root)
    merged, changes = plan_merge(
        current,
        python=d.python,
        node=d.node,
        go=d.go,
        terraform=d.terraform,
        docker=d.docker,
        has_shell=d.has_shell,
    )
    write_precommit(cfg_file, merged)

    if not changes:
        typer.echo("No changes. Your hooks already meet baseline expectations.")
        raise typer.Exit(code=0)

    typer.echo("Applied changes:")
    for change in changes:
        note = ""
        if "gitleaks" in change or "detect-secrets" in change:
            note = "[SEC][SI-3/SI-7][CM-6]: blocking secret scans"
        elif "ruff" in change:
            note = "[CS][style+lint]: fast feedback"
        elif "bandit" in change:
            note = "[SEC][SA]: basic static analysis"
        elif "tflint" in change:
            note = "[IaC]: terraform lint"
        elif "shellcheck" in change:
            note = "[shell]: static analysis"
        elif "hadolint" in change:
            note = "[docker]: Dockerfile lint"
        typer.echo(f"- {change} {note}".rstrip())


@app.command("explain")
def explain(config_path: str = typer.Option(".pre-commit-config.yaml", "--config", "-c")) -> None:
    """
    Print a short explanation of what will run and why, based on config content.
    """
    cfg_file = Path(config_path)
    if not cfg_file.exists():
        typer.echo("No pre-commit config found.")
        raise typer.Exit(code=1)

    data = yaml.safe_load(cfg_file.read_text(encoding="utf-8")) or {}
    repos = data.get("repos") or []

    def has_entry(text: str) -> bool:
        for repo in repos:
            repo_val = str(repo.get("repo", ""))
            hooks = repo.get("hooks") or []
            if text in repo_val:
                return True
            for h in hooks:
                # look in id/name/entry fields
                if any(text in str(h.get(k, "")) for k in ("id", "name", "entry")):
                    return True
        return False

    lines: list[str] = []
    if has_entry("gitleaks"):
        lines.append(
            "- gitleaks: blocks secrets before they become a ticket. You'll thank me later."
        )
    if has_entry("detect-secrets"):
        lines.append("- detect-secrets: baseline comparisons to prevent regressions.")
    if has_entry("ruff-pre-commit"):
        lines.append("- ruff: fast style + lint. If it's noisy, fix the code, not the tool.")
    if has_entry("PyCQA/bandit") or has_entry(" bandit"):
        lines.append("- bandit: cheap guardrails. If it fires, you probably deserved it.")
    if has_entry("tflint"):
        lines.append("- tflint: IaC linting for Terraform.")
    if has_entry("shellcheck"):
        lines.append("- shellcheck: stop shipping bash foot-guns.")
    if has_entry("hadolint"):
        lines.append("- hadolint: lint Dockerfiles so prod doesn't yell at you.")

    typer.echo("What runs and why:\n-------------------")
    for line in lines:
        typer.echo(line)
    if not lines:
        typer.echo("Your config is oddly empty. That's brave. Add secrets scanning at minimum.")


if __name__ == "__main__":
    app()
