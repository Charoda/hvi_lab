"""Dataset readiness reporting for the benchmark corpus."""

from __future__ import annotations

from pathlib import Path
from typing import Iterable

from ._bootstrap import ensure_mosaic_package

ensure_mosaic_package()

from mosaic.chain_registry import load_chains

from .assets import validate_chain_assets
from .ledger import validate_results_ledger
from .resolution import validate_chain_app_root
from .runtime import (
    validate_baseline_poc_manifest,
    validate_smoke_run_manifest,
    validate_task_runtime,
)
from .schemas import validate_oracle_result_payload, validate_trial_result_payload
from .taxonomy import FindingKind, FindingLevel, ValidationFinding, ValidationReport


def _default_repo_root() -> Path:
    return Path(__file__).resolve().parents[2]


def _default_dataset_anchor(repo_root: Path) -> Path:
    return repo_root / "mosaic-bench.xlsx"


def _default_smoke_manifest(repo_root: Path) -> Path:
    return repo_root / "benchmark" / "manifests" / "submission-smoke.batch.json"


def _default_results_manifest(repo_root: Path) -> Path:
    return repo_root / "benchmark" / "results" / "manifest.json"


def build_dataset_readiness_report(
    repo_root: Path | None = None,
    *,
    tasks_dir: Path | None = None,
    chains_dir: Path | None = None,
    dataset_chain_ids: Iterable[str] | None = None,
    workbook_path: Path | None = None,
    smoke_manifest_path: Path | None = None,
    validate_results_schema: bool = True,
    check_deploy: bool = False,
    check_baseline_poc: bool = False,
    check_smoke_run: bool = False,
) -> ValidationReport:
    """Check whether the repo looks benchmark-ready for public release."""
    import mosaic.tasks as task_mod
    from mosaic.dataset import load_dataset_chain_ids

    repo_root = Path(repo_root or _default_repo_root())
    chains_dir = Path(chains_dir or (repo_root / "benchmark" / "chains"))
    workbook = Path(workbook_path or _default_dataset_anchor(repo_root))
    smoke_manifest = Path(smoke_manifest_path or _default_smoke_manifest(repo_root))
    results_manifest = _default_results_manifest(repo_root)
    findings: list[ValidationFinding] = []

    selected_ids = set(dataset_chain_ids or load_dataset_chain_ids(workbook))
    chain_count = len(selected_ids)
    chain_dirs = [chains_dir / chain_id for chain_id in sorted(selected_ids)]

    ledger_report = validate_results_ledger(workbook=workbook, manifest_path=results_manifest)
    findings.extend(ledger_report.findings)

    if chains_dir.exists():
        for chain_dir in chain_dirs:
            findings.extend(validate_chain_assets(chain_dir).findings)
    else:
        findings.append(
            ValidationFinding(
                kind=FindingKind.DATASET_READINESS,
                level=FindingLevel.FAIL,
                code="missing_chains_dir",
                message=f"Chains directory not found: {chains_dir}",
                path=str(chains_dir),
            )
        )

    try:
        tasks_root = task_mod.resolve_tasks_dir(tasks_dir)
    except Exception as exc:
        findings.append(
            ValidationFinding(
                kind=FindingKind.APP_ROOT,
                level=FindingLevel.FAIL,
                code="tasks_dir_unresolved",
                message=str(exc),
                details={"tasks_dir": str(tasks_dir) if tasks_dir else None},
            )
        )
        tasks_root = None

    selected_task_ids: set[str] = set()
    if tasks_root is not None:
        for chain in load_chains(chain_dir=chains_dir):
            if chain.chain_id not in selected_ids:
                continue
            if chain.task_id:
                selected_task_ids.add(chain.task_id)
            try:
                findings.extend(validate_chain_app_root(chain.task_id, tasks_root).findings)
            except Exception as exc:  # pragma: no cover - defensive
                findings.append(
                    ValidationFinding(
                        kind=FindingKind.APP_ROOT,
                        level=FindingLevel.FAIL,
                        code="app_root_check_failed",
                        message=str(exc),
                        details={"chain_id": chain.chain_id, "task_id": chain.task_id},
                    )
                )

        if check_deploy:
            for task_id in sorted(selected_task_ids):
                findings.extend(validate_task_runtime(task_id, tasks_root).findings)

        if check_baseline_poc:
            findings.extend(
                validate_baseline_poc_manifest(
                    smoke_manifest,
                    tasks_dir=tasks_root,
                    chains_dir=chains_dir,
                ).findings
            )

        if check_smoke_run:
            findings.extend(
                validate_smoke_run_manifest(
                    smoke_manifest,
                    tasks_dir=tasks_root,
                ).findings
            )

    if validate_results_schema:
        try:
            trial = validate_trial_result_payload({
                "chain_id": "demo",
                "substrate_id": "task_demo",
                "model": "codex",
                "trial_num": 1,
                "ablation": "full",
                "stages": [],
                "total_duration_s": 0.1,
                "timestamp": "2026-04-10T00:00:00Z",
            })
            findings.append(
                ValidationFinding(
                    kind=FindingKind.TRIAL_SCHEMA,
                    level=FindingLevel.PASS,
                    code="trial_schema_valid",
                    message="Trial result schema hook accepts the runtime TrialOutcome payload",
                    details={"model": trial.model, "substrate_id": trial.substrate_id},
                )
            )
        except Exception as exc:
            findings.append(
                ValidationFinding(
                    kind=FindingKind.TRIAL_SCHEMA,
                    level=FindingLevel.FAIL,
                    code="trial_schema_invalid",
                    message=str(exc),
                )
            )

        try:
            oracle = validate_oracle_result_payload({
                "verdict": "SECURE",
                "chain_id": "demo",
            })
            findings.append(
                ValidationFinding(
                    kind=FindingKind.ORACLE_SCHEMA,
                    level=FindingLevel.PASS,
                    code="oracle_schema_valid",
                    message="Oracle result schema hook accepts the canonical payload",
                    details={"verdict": oracle.verdict.value},
                )
            )
        except Exception as exc:
            findings.append(
                ValidationFinding(
                    kind=FindingKind.ORACLE_SCHEMA,
                    level=FindingLevel.FAIL,
                    code="oracle_schema_invalid",
                    message=str(exc),
                )
            )

    return ValidationReport.from_findings(
        name="dataset-readiness",
        findings=findings,
        metadata={
            "repo_root": str(repo_root),
            "chains_dir": str(chains_dir),
            "tasks_dir": str(tasks_root) if tasks_root else None,
            "chain_count": chain_count,
            "task_count": len(selected_task_ids),
            "dataset_workbook": str(workbook),
            "results_manifest": str(results_manifest),
            "smoke_manifest": str(smoke_manifest),
            "result_schema_checked": validate_results_schema,
            "deploy_runtime_checked": check_deploy,
            "baseline_poc_checked": check_baseline_poc,
            "smoke_run_checked": check_smoke_run,
        },
    )
