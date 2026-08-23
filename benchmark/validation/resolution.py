"""App-root resolution helpers for benchmark validation."""

from __future__ import annotations

from pathlib import Path

from ._bootstrap import ensure_mosaic_package

ensure_mosaic_package()

from .taxonomy import FindingKind, FindingLevel, ValidationFinding, ValidationReport


def resolve_chain_app_root(task_id: str, tasks_dir: Path | None = None) -> Path:
    """Resolve the concrete app root for a benchmark task."""
    import mosaic.deploy as deploy_mod
    import mosaic.tasks as task_mod

    tasks_root = task_mod.resolve_tasks_dir(tasks_dir)
    task = task_mod.get_task(task_id, tasks_root)
    config = deploy_mod.ABC_BENCH_APPS.get(task_id)
    if config is not None:
        candidate = task.path / config.app_dir
        if candidate.is_dir():
            return candidate
        raise FileNotFoundError(
            f"Resolved task {task_id!r} but app directory is missing: {candidate}"
        )
    if task.path.is_dir():
        return task.path
    raise FileNotFoundError(f"Task root not found for {task_id!r}: {task.path}")


def validate_chain_app_root(task_id: str, tasks_dir: Path | None = None) -> ValidationReport:
    """Validate that a task's app root can be resolved from the benchmark apps tree."""
    findings: list[ValidationFinding] = []
    try:
        root = resolve_chain_app_root(task_id, tasks_dir)
        findings.append(
            ValidationFinding(
                kind=FindingKind.APP_ROOT,
                level=FindingLevel.PASS,
                code="app_root_resolved",
                message=f"Resolved app root for {task_id}",
                path=str(root),
                details={"task_id": task_id, "resolved_path": str(root)},
            )
        )
    except Exception as exc:
        findings.append(
            ValidationFinding(
                kind=FindingKind.APP_ROOT,
                level=FindingLevel.FAIL,
                code="app_root_unresolved",
                message=str(exc),
                details={"task_id": task_id},
            )
        )
    return ValidationReport.from_findings(
        name=f"app-root:{task_id}",
        findings=findings,
        metadata={"task_id": task_id},
    )
