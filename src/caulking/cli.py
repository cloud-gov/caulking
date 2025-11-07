from __future__ import annotations

from pathlib import Path
from typing import Annotated

import typer

from caulking.audit import audit
from caulking.doctor import format_preflight, preflight
from caulking.installer import (  # re-exports
    GlobalMode,
    apply_smart_install,
    plan_smart_install,
    read_precommit,
)
from caulking.installer import _format_plan as fmt  # keep API tidy, avoid PLC0415

app = typer.Typer(help="Caulking: enforce blocking secret scans + ecosystem guardrails.")


@app.command("preflight")
def preflight_cmd(path: str = typer.Argument(".", help="Repository path")) -> None:
    """Quick environment sanity: tools, PATH, hooksPath, config presence."""
    root = Path(path).resolve()
    checks = preflight(root)
    typer.echo(format_preflight(checks))


@app.command("smart-install")
def smart_install(
    path: str = typer.Argument(".", help="Repository path (must contain .git)"),
    apply: bool = typer.Option(False, "--apply", help="Actually perform changes."),
    global_mode: Annotated[
        GlobalMode,
        typer.Option(
            "--global-mode",
            help=(
                "Set global core.hooksPath: off|advisory|enforce "
                "(behavior identical; policy decides)."
            ),
        ),
    ] = "advisory",
) -> None:
    root = Path(path).resolve()
    plan = plan_smart_install(root, global_mode=global_mode)

    if not apply:
        typer.echo("Plan (dry-run):\n-------------")
        typer.echo(fmt(plan))
        typer.echo("\nNothing applied. Re-run with --apply to make changes.")
        raise SystemExit(0)

    log_path = (
        (root / ".git" / "caulking.log") if (root / ".git").exists() else (root / ".caulking.log")
    )
    results = apply_smart_install(plan, log_path=log_path)

    typer.echo("Applied:\n--------")
    for kind, rc, note in results:
        status = "OK" if rc == 0 else f"RC={rc}"
        typer.echo(f"- [{kind}] {status}: {note}")

    typer.echo(f"\nLog: {log_path}")
    typer.echo("Hints:")
    typer.echo("  - Open a new shell or 'source' your rc file(s) if PATH was updated.")
    typer.echo("  - If gitleaks was missing, install it (e.g., 'brew install gitleaks' on macOS).")


@app.command("explain")
def explain(path: str = typer.Argument(".", help="Path with .pre-commit-config.yaml")) -> None:
    data = read_precommit(Path(path).resolve() / ".pre-commit-config.yaml")

    def has_any(substrs: list[str]) -> bool:
        repos = data.get("repos", [])
        for repo in repos:
            repo_str = str(repo.get("repo", ""))
            if any(s in repo_str for s in substrs):
                return True
            for h in repo.get("hooks", []):
                if any(s in str(h.get("id", "")) for s in substrs):
                    return True
        return False

    checks: list[tuple[list[str], str]] = [
        (["gitleaks"], "- gitleaks: blocks secrets; safer excludes via rules/gitleaks.toml"),
        (["detect-secrets"], "- detect-secrets: baseline safety net"),
        (["ruff", "ruff-pre-commit"], "- ruff: fast lint/format for Python"),
        (["PyCQA/bandit", "bandit"], "- bandit: cheap guardrails"),
        (["tflint"], "- tflint: terraform lint"),
        (["terraform-fmt"], "- terraform fmt: formatting as policy"),
        (["shellcheck"], "- shellcheck: sh hygiene"),
        (["hadolint"], "- hadolint: Dockerfile lint"),
        (["golangci-lint"], "- golangci-lint + gofmt for Go"),
        (["cargo"], "- cargo fmt/clippy for Rust"),
        (["maven-verify", "gradle-check"], "- Maven/Gradle sanity"),
        (["rubocop"], "- rubocop for Ruby"),
        (["php-lint"], "- php -l for PHP"),
        (["dotnet-format"], "- dotnet format for .NET"),
        (["eslint", "prettier", "stylelint"], "- web: eslint/prettier/stylelint (if present)"),
        (["check-yaml", "check-json"], "- basics: YAML/JSON/whitespace/merge-conflicts"),
    ]
    lines = [msg for keys, msg in checks if has_any(keys)]
    typer.echo("What runs and why:\n-------------------")
    for line in lines or ["Your config is empty. At minimum, enable secrets scanning."]:
        typer.echo(line)


@app.command("audit")
def audit_cmd() -> None:
    res = audit(strict=False)
    typer.echo(res.report_text)
    raise SystemExit(0 if res.ok else 2)


def main() -> None:
    app()


if __name__ == "__main__":
    main()
