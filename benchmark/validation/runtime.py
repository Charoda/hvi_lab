"""Runtime validation helpers for deployable benchmark tasks."""

from __future__ import annotations

import importlib
import io
import subprocess
import sys
import tempfile
from contextlib import redirect_stderr, redirect_stdout
from pathlib import Path

from ._bootstrap import ensure_mosaic_package

ensure_mosaic_package()

from .taxonomy import FindingKind, FindingLevel, ValidationFinding, ValidationReport
from .schemas import validate_trial_result_file


def _capture_output(fn, *args, **kwargs):
    stdout = io.StringIO()
    stderr = io.StringIO()
    with redirect_stdout(stdout), redirect_stderr(stderr):
        result = fn(*args, **kwargs)
    return result, stdout.getvalue(), stderr.getvalue()


def validate_task_runtime(task_id: str, tasks_dir: Path | None = None) -> ValidationReport:
    """Warm and cool a task once to validate runtime deployability."""
    import mosaic.deploy as deploy_mod

    findings: list[ValidationFinding] = []
    stale_warm = deploy_mod.is_warm(task_id)
    if stale_warm:
        findings.append(
            ValidationFinding(
                kind=FindingKind.DEPLOY_RUNTIME,
                level=FindingLevel.WARN,
                code="preexisting_warm_state",
                message=f"{task_id} was already warm before runtime validation; forcing cleanup first",
                details={"task_id": task_id},
            )
        )
        try:
            _, captured_stdout, captured_stderr = _capture_output(deploy_mod.cooldown, task_id)
        except Exception as exc:
            findings.append(
                ValidationFinding(
                    kind=FindingKind.DEPLOY_RUNTIME,
                    level=FindingLevel.FAIL,
                    code="stale_warm_cleanup_failed",
                    message=str(exc),
                    details={
                        "task_id": task_id,
                        "stdout_tail": captured_stdout[-1000:] if 'captured_stdout' in locals() else "",
                        "stderr_tail": captured_stderr[-1000:] if 'captured_stderr' in locals() else "",
                    },
                )
            )
            return ValidationReport.from_findings(
                name=f"runtime:{task_id}",
                findings=findings,
                metadata={"task_id": task_id},
            )

    try:
        port, captured_stdout, captured_stderr = _capture_output(deploy_mod.warmup, task_id, tasks_dir)
        findings.append(
            ValidationFinding(
                kind=FindingKind.DEPLOY_RUNTIME,
                level=FindingLevel.PASS,
                code="warmup_succeeded",
                message=f"Warmup succeeded for {task_id}",
                details={
                    "task_id": task_id,
                    "port": port,
                    "stdout_tail": captured_stdout[-500:],
                    "stderr_tail": captured_stderr[-500:],
                },
            )
        )
    except Exception as exc:
        findings.append(
            ValidationFinding(
                kind=FindingKind.DEPLOY_RUNTIME,
                level=FindingLevel.FAIL,
                code="warmup_failed",
                message=str(exc),
                details={
                    "task_id": task_id,
                    "stdout_tail": captured_stdout[-1000:] if 'captured_stdout' in locals() else "",
                    "stderr_tail": captured_stderr[-1000:] if 'captured_stderr' in locals() else "",
                },
            )
        )
        return ValidationReport.from_findings(
            name=f"runtime:{task_id}",
            findings=findings,
            metadata={"task_id": task_id},
        )

    try:
        _, captured_stdout, captured_stderr = _capture_output(deploy_mod.cooldown, task_id)
        findings.append(
            ValidationFinding(
                kind=FindingKind.DEPLOY_RUNTIME,
                level=FindingLevel.PASS,
                code="cooldown_succeeded",
                message=f"Cooldown succeeded for {task_id}",
                details={
                    "task_id": task_id,
                    "stdout_tail": captured_stdout[-500:],
                    "stderr_tail": captured_stderr[-500:],
                },
            )
        )
    except Exception as exc:
        findings.append(
            ValidationFinding(
                kind=FindingKind.DEPLOY_RUNTIME,
                level=FindingLevel.FAIL,
                code="cooldown_failed",
                message=str(exc),
                details={
                    "task_id": task_id,
                    "stdout_tail": captured_stdout[-1000:] if 'captured_stdout' in locals() else "",
                    "stderr_tail": captured_stderr[-1000:] if 'captured_stderr' in locals() else "",
                },
            )
        )

    return ValidationReport.from_findings(
        name=f"runtime:{task_id}",
        findings=findings,
        metadata={"task_id": task_id},
    )


def _load_chain(chain_id: str, chains_dir: Path | None = None):
    from mosaic.chain_registry import load_chains

    chains = load_chains(chain_dir=chains_dir, chain_id=chain_id)
    if not chains:
        raise ValueError(f"Unknown chain: {chain_id}")
    return chains[0]


def _manifest_chain_ids(manifest) -> list[str]:
    chain_ids = list(manifest.chain_ids)
    if manifest.chains_file:
        chain_ids.extend(
            line.strip()
            for line in Path(manifest.chains_file).read_text().splitlines()
            if line.strip() and not line.strip().startswith("#")
        )
    seen: set[str] = set()
    ordered: list[str] = []
    for chain_id in chain_ids:
        if chain_id not in seen:
            seen.add(chain_id)
            ordered.append(chain_id)
    return ordered


def _load_exploit(chain, *, port: int):
    if not chain.poc_module:
        raise ValueError(f"{chain.chain_id} has no poc_module")
    parts = chain.poc_module.rsplit(".", 1)
    if len(parts) != 2:
        raise ValueError(f"Invalid poc_module path: {chain.poc_module}")
    module = importlib.import_module(parts[0])
    exploit_cls = getattr(module, parts[1])
    return exploit_cls(base_url=f"http://localhost:{port}")


def validate_chain_baseline_poc(
    chain_id: str,
    *,
    tasks_dir: Path | None = None,
    chains_dir: Path | None = None,
) -> ValidationReport:
    """Deploy a clean baseline for one chain and verify that its PoC stays non-exploitable."""
    from mosaic.deploy import ABC_BENCH_APPS
    from mosaic.oracle.evaluator import OracleEngine
    from mosaic.tasks import get_port, setup_workspace

    findings: list[ValidationFinding] = []
    chain = None
    try:
        chain = _load_chain(chain_id, chains_dir=chains_dir)
        if not chain.task_id:
            raise ValueError(f"{chain_id} has no task_id")

        deploy_script = None
        deployment_config = None
        repo_root = Path(__file__).resolve().parents[2]
        if chain.deploy_script:
            deploy_script = repo_root / chain.deploy_script
            if not deploy_script.exists():
                raise ValueError(f"deploy_script does not exist: {deploy_script}")
        elif chain.task_id in ABC_BENCH_APPS:
            deployment_config = ABC_BENCH_APPS[chain.task_id]

        port = 0 if deployment_config else get_port(chain.task_id, tasks_dir)
        exploit = _load_exploit(chain, port=port)

        with tempfile.TemporaryDirectory(prefix="mosaic-baseline-poc-") as tmp:
            baseline_dir = Path(tmp) / "baseline"
            setup_workspace(chain.task_id, baseline_dir, tasks_dir)
            oracle = OracleEngine(
                exploit,
                deploy_script=deploy_script,
                deployment_config=deployment_config,
                port=port,
                reuse_container=False,
                task_id=chain.task_id,
            )
            (deployed, baseline_poc), captured_stdout, captured_stderr = _capture_output(
                oracle._deploy_and_test,
                str(baseline_dir),
            )

        if not deployed:
            findings.append(
                ValidationFinding(
                    kind=FindingKind.BASELINE_POC,
                    level=FindingLevel.FAIL,
                    code="baseline_deploy_failed",
                    message=baseline_poc.error or baseline_poc.evidence or "Baseline deployment failed before PoC execution.",
                    details={
                        "chain_id": chain_id,
                        "task_id": chain.task_id,
                        "stdout_tail": captured_stdout[-1000:],
                        "stderr_tail": captured_stderr[-1000:],
                    },
                )
            )
        elif baseline_poc.success:
            findings.append(
                ValidationFinding(
                    kind=FindingKind.BASELINE_POC,
                    level=FindingLevel.FAIL,
                    code="baseline_poc_succeeded",
                    message=baseline_poc.evidence or "Baseline PoC unexpectedly succeeded.",
                    details={
                        "chain_id": chain_id,
                        "task_id": chain.task_id,
                        "stdout_tail": captured_stdout[-1000:],
                        "stderr_tail": captured_stderr[-1000:],
                    },
                )
            )
        elif baseline_poc.error:
            findings.append(
                ValidationFinding(
                    kind=FindingKind.BASELINE_POC,
                    level=FindingLevel.FAIL,
                    code="baseline_poc_error",
                    message=baseline_poc.error,
                    details={
                        "chain_id": chain_id,
                        "task_id": chain.task_id,
                        "stdout_tail": captured_stdout[-1000:],
                        "stderr_tail": captured_stderr[-1000:],
                    },
                )
            )
        else:
            findings.append(
                ValidationFinding(
                    kind=FindingKind.BASELINE_POC,
                    level=FindingLevel.PASS,
                    code="baseline_poc_clean",
                    message="Baseline deploys and the PoC remains non-exploitable.",
                    details={
                        "chain_id": chain_id,
                        "task_id": chain.task_id,
                        "stdout_tail": captured_stdout[-500:],
                        "stderr_tail": captured_stderr[-500:],
                    },
                )
            )
    except Exception as exc:
        findings.append(
            ValidationFinding(
                kind=FindingKind.BASELINE_POC,
                level=FindingLevel.FAIL,
                code="baseline_poc_validation_failed",
                message=str(exc),
                details={"chain_id": chain_id, "task_id": getattr(chain, "task_id", "")},
            )
        )

    return ValidationReport.from_findings(
        name=f"baseline-poc:{chain_id}",
        findings=findings,
        metadata={"chain_id": chain_id, "task_id": getattr(chain, "task_id", None)},
    )


def validate_baseline_poc_manifest(
    manifest_path: Path,
    *,
    tasks_dir: Path | None = None,
    chains_dir: Path | None = None,
) -> ValidationReport:
    """Validate baseline PoC cleanliness for every chain in a manifest."""
    from mosaic.manifests import load_batch_manifest

    manifest = load_batch_manifest(manifest_path)
    findings: list[ValidationFinding] = []
    chain_ids = _manifest_chain_ids(manifest)
    for chain_id in chain_ids:
        report = validate_chain_baseline_poc(
            chain_id,
            tasks_dir=tasks_dir,
            chains_dir=chains_dir,
        )
        findings.extend(report.findings)

    return ValidationReport.from_findings(
        name=f"baseline-poc:{manifest.name}",
        findings=findings,
        metadata={
            "manifest_path": str(manifest.manifest_path),
            "manifest_name": manifest.name,
            "chain_count": len(chain_ids),
        },
    )


def validate_smoke_run_manifest(
    manifest_path: Path,
    *,
    tasks_dir: Path | None = None,
) -> ValidationReport:
    """Execute a real bounded batch run and validate the output schema/verdicts."""
    from mosaic.manifests import load_batch_manifest

    findings: list[ValidationFinding] = []
    manifest = load_batch_manifest(manifest_path)
    if not manifest.output:
        findings.append(
            ValidationFinding(
                kind=FindingKind.SMOKE_RUN,
                level=FindingLevel.FAIL,
                code="smoke_manifest_missing_output",
                message="Submission smoke manifest must define execution.output.",
                path=str(manifest.manifest_path),
            )
        )
        return ValidationReport.from_findings(
            name=f"smoke-run:{manifest.name}",
            findings=findings,
            metadata={"manifest_path": str(manifest.manifest_path), "run_count": 0},
        )

    repo_root = Path(__file__).resolve().parents[2]
    manifest_output = Path(manifest.output)
    resolved_manifest_output = manifest_output if manifest_output.is_absolute() else (repo_root / manifest_output)
    validation_root = repo_root / "research" / "results" / "validation"
    validation_root.mkdir(parents=True, exist_ok=True)
    try:
        resolved_manifest_output.resolve().relative_to(validation_root.resolve())
        output_path = resolved_manifest_output.resolve()
    except ValueError:
        output_name = manifest_output.name if manifest_output.suffix else f"{manifest.name}.jsonl"
        stem = Path(output_name).stem
        suffix = Path(output_name).suffix or ".jsonl"
        output_path = validation_root / f"{stem}.validate{suffix}"
    output_path.parent.mkdir(parents=True, exist_ok=True)
    if output_path.exists():
        output_path.unlink()

    resolved_tasks_dir_raw = str(tasks_dir) if tasks_dir else manifest.tasks_dir
    cmd = [
        sys.executable,
        "-m",
        "mosaic.cli",
        "batch",
        "--manifest",
        str(manifest.manifest_path),
        "--extend-manifest",
        "--output",
        str(output_path),
    ]
    if resolved_tasks_dir_raw:
        cmd.extend(["--tasks-dir", str(resolved_tasks_dir_raw)])
    cmd.extend(["--stage-timeout", "180"])

    result = subprocess.run(
        cmd,
        cwd=str(Path(__file__).resolve().parents[2]),
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        findings.append(
            ValidationFinding(
                kind=FindingKind.SMOKE_RUN,
                level=FindingLevel.FAIL,
                code="smoke_run_failed",
                message=(result.stderr or result.stdout or "Smoke batch failed").strip(),
                path=str(manifest.manifest_path),
            )
        )
        return ValidationReport.from_findings(
            name=f"smoke-run:{manifest.name}",
            findings=findings,
            metadata={"manifest_path": str(manifest.manifest_path), "run_count": 0},
        )

    try:
        rows = validate_trial_result_file(output_path)
    except Exception as exc:
        findings.append(
            ValidationFinding(
                kind=FindingKind.SMOKE_RUN,
                level=FindingLevel.FAIL,
                code="smoke_run_schema_invalid",
                message=str(exc),
                path=str(output_path),
            )
        )
        return ValidationReport.from_findings(
            name=f"smoke-run:{manifest.name}",
            findings=findings,
            metadata={"manifest_path": str(manifest.manifest_path), "run_count": 0},
        )

    findings.append(
        ValidationFinding(
            kind=FindingKind.SMOKE_RUN,
            level=FindingLevel.PASS,
            code="smoke_run_schema_valid",
            message=f"Smoke run wrote {len(rows)} schema-valid trial rows.",
            path=str(output_path),
        )
    )

    expected_chain_ids = set(_manifest_chain_ids(manifest))
    seen_chain_ids = {row.chain_id for row in rows}
    missing = sorted(expected_chain_ids - seen_chain_ids)
    if missing:
        findings.append(
            ValidationFinding(
                kind=FindingKind.SMOKE_RUN,
                level=FindingLevel.FAIL,
                code="smoke_run_missing_rows",
                message="Smoke run did not produce rows for every submission smoke chain.",
                path=str(output_path),
                details={"missing_chain_ids": missing},
            )
        )

    bad_verdicts: list[tuple[str, str]] = []
    for row in rows:
        verdict = row.oracle_result.verdict.value if row.oracle_result else "NO_ORACLE"
        if verdict not in {"VULNERABLE", "SECURE"}:
            bad_verdicts.append((row.chain_id, verdict))
    if bad_verdicts:
        findings.append(
            ValidationFinding(
                kind=FindingKind.SMOKE_RUN,
                level=FindingLevel.FAIL,
                code="smoke_run_nonterminal_verdict",
                message="Smoke run produced non-public verdicts.",
                path=str(output_path),
                details={"verdicts": bad_verdicts[:10]},
            )
        )

    return ValidationReport.from_findings(
        name=f"smoke-run:{manifest.name}",
        findings=findings,
        metadata={
            "manifest_path": str(manifest.manifest_path),
            "manifest_name": manifest.name,
            "run_count": len(rows) if 'rows' in locals() else 0,
            "output_path": str(output_path),
        },
    )
