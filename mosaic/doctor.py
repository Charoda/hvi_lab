"""Preflight checks for running MOSAIC on a local workstation."""

from __future__ import annotations

import importlib
import shutil
import subprocess
from dataclasses import asdict, dataclass, field
from pathlib import Path
from typing import Iterable


@dataclass
class DoctorCheck:
    """Result of a single preflight check."""

    id: str
    status: str
    summary: str
    details: dict[str, object] = field(default_factory=dict)
    fix_hint: str | None = None

    def to_dict(self) -> dict[str, object]:
        return asdict(self)


def _run(cmd: list[str], *, timeout: int = 15) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        cmd,
        capture_output=True,
        text=True,
        timeout=timeout,
    )


def _command_check(
    *,
    check_id: str,
    binary: str,
    probe: list[str],
    missing_hint: str,
    probe_hint: str,
) -> DoctorCheck:
    path = shutil.which(binary)
    if not path:
        return DoctorCheck(
            id=check_id,
            status="warn",
            summary=f"{binary} is not installed or not on PATH.",
            fix_hint=missing_hint,
        )

    try:
        result = _run([binary] + probe)
    except subprocess.TimeoutExpired:
        return DoctorCheck(
            id=check_id,
            status="warn",
            summary=f"{binary} is installed but the probe timed out.",
            details={"path": path, "probe": " ".join([binary] + probe)},
            fix_hint=probe_hint,
        )

    if result.returncode != 0:
        return DoctorCheck(
            id=check_id,
            status="warn",
            summary=f"{binary} is installed but the probe failed.",
            details={
                "path": path,
                "probe": " ".join([binary] + probe),
                "exit_code": result.returncode,
                "stderr": (result.stderr or "")[-500:],
                "stdout": (result.stdout or "")[-500:],
            },
            fix_hint=probe_hint,
        )

    first_line = next(
        (line.strip() for line in (result.stdout or "").splitlines() if line.strip()),
        f"{binary} probe succeeded",
    )
    return DoctorCheck(
        id=check_id,
        status="ok",
        summary=first_line,
        details={"path": path, "probe": " ".join([binary] + probe)},
    )


def check_python_package() -> DoctorCheck:
    try:
        importlib.import_module("mosaic.cli")
        importlib.import_module("mosaic.chain_registry")
        importlib.import_module("mosaic.oracle")
    except Exception as exc:  # pragma: no cover - defensive
        return DoctorCheck(
            id="python_package",
            status="fail",
            summary="The installed MOSAIC package failed to import cleanly.",
            details={"error": str(exc)},
            fix_hint="Reinstall with `pip install -e .` and re-run `mosaic doctor`.",
        )
    return DoctorCheck(
        id="python_package",
        status="ok",
        summary="The package imports cleanly.",
    )


def check_git_cli() -> DoctorCheck:
    return _command_check(
        check_id="git_cli",
        binary="git",
        probe=["--version"],
        missing_hint="Install Git and ensure `git` is callable on PATH.",
        probe_hint="Fix the local Git installation before running MOSAIC.",
    )


def check_docker_cli() -> DoctorCheck:
    return _command_check(
        check_id="docker_cli",
        binary="docker",
        probe=["--version"],
        missing_hint="Install Docker Desktop and ensure `docker` is callable on PATH.",
        probe_hint="Fix the Docker CLI installation before running MOSAIC.",
    )


def check_docker_daemon() -> DoctorCheck:
    path = shutil.which("docker")
    if not path:
        return DoctorCheck(
            id="docker_daemon",
            status="skip",
            summary="Skipped because the Docker CLI is not installed.",
        )
    try:
        result = _run(["docker", "info"], timeout=20)
    except subprocess.TimeoutExpired:
        return DoctorCheck(
            id="docker_daemon",
            status="fail",
            summary="Docker is installed but the daemon probe timed out.",
            fix_hint="Start Docker Desktop and wait until `docker info` succeeds.",
        )
    if result.returncode != 0:
        return DoctorCheck(
            id="docker_daemon",
            status="fail",
            summary="Docker is installed but the daemon is not reachable.",
            details={"stderr": (result.stderr or "")[-500:]},
            fix_hint="Start Docker Desktop and verify `docker info` works from the terminal.",
        )
    server_line = next(
        (line.strip() for line in (result.stdout or "").splitlines() if "Server Version" in line),
        "Docker daemon is reachable.",
    )
    return DoctorCheck(
        id="docker_daemon",
        status="ok",
        summary=server_line,
    )


def check_tasks_dir(tasks_dir: str | None) -> DoctorCheck:
    from .bootstrap import BENCHMARK_TASK_IDS_FILE, load_benchmark_task_ids
    from .tasks import list_tasks, resolve_tasks_dir

    try:
        resolved = resolve_tasks_dir(tasks_dir)
        tasks = list_tasks(resolved)
    except Exception as exc:
        return DoctorCheck(
            id="tasks_dir",
            status="fail",
            summary="The ABC-Bench benchmark apps directory could not be resolved.",
            details={"configured_value": tasks_dir, "error": str(exc)},
            fix_hint="Run `mosaic init`, or point `MOSAIC_TASKS_DIR` at extracted OpenMOSS-Team/ABC-Bench app directories.",
        )

    if not tasks:
        return DoctorCheck(
            id="tasks_dir",
            status="fail",
            summary="The benchmark apps directory exists, but no ABC-Bench apps are installed.",
            details={"path": str(resolved)},
            fix_hint="Run `mosaic init` to install the repo-local benchmark apps.",
        )

    available = {task.task_id for task in tasks}
    required = load_benchmark_task_ids()
    missing = sorted(required - available)
    if missing:
        return DoctorCheck(
            id="tasks_dir",
            status="warn",
            summary=f"Resolved benchmark apps dir with {len(tasks)} apps, but {len(missing)} benchmark app IDs are missing.",
            details={
                "path": str(resolved),
                "benchmark_source": str(BENCHMARK_TASK_IDS_FILE) if BENCHMARK_TASK_IDS_FILE.exists() else "chain_registry_fallback",
                "missing_task_ids": missing[:10],
                "missing_count": len(missing),
            },
            fix_hint="Re-run `mosaic init --subset benchmark --force` or populate the missing benchmark app directories.",
        )

    return DoctorCheck(
        id="tasks_dir",
        status="ok",
        summary=f"Resolved benchmark apps dir with {len(tasks)} apps and full benchmark coverage.",
        details={
            "path": str(resolved),
            "benchmark_source": str(BENCHMARK_TASK_IDS_FILE) if BENCHMARK_TASK_IDS_FILE.exists() else "chain_registry_fallback",
            "required_app_ids": len(required),
        },
    )


def check_chain_registry() -> DoctorCheck:
    from .chain_registry import load_chains

    try:
        chains = load_chains()
    except Exception as exc:
        return DoctorCheck(
            id="chain_registry",
            status="fail",
            summary="The chain registry failed to load.",
            details={"error": str(exc)},
            fix_hint="Fix broken chain definitions or import paths under `benchmark/chains/`.",
        )

    if not chains:
        return DoctorCheck(
            id="chain_registry",
            status="fail",
            summary="No active chains loaded.",
            fix_hint="Populate `benchmark/chains/` with supported chain definitions.",
        )

    substrates = sorted({chain.substrate_id for chain in chains})
    return DoctorCheck(
        id="chain_registry",
        status="ok",
        summary=f"Loaded {len(chains)} active chains across {len(substrates)} substrates.",
        details={"sample_chains": [chain.chain_id for chain in chains[:5]]},
    )


def check_dataset_workbook() -> DoctorCheck:
    from .dataset import DATASET_WORKBOOK, dataset_summary

    if not DATASET_WORKBOOK.exists():
        return DoctorCheck(
            id="dataset_workbook",
            status="fail",
            summary="The workbook-backed dataset source of truth is missing.",
            details={"expected_path": str(DATASET_WORKBOOK)},
            fix_hint="Restore `mosaic-bench.xlsx` before publishing the benchmark surface.",
        )

    try:
        summary = dataset_summary(DATASET_WORKBOOK)
    except Exception as exc:
        return DoctorCheck(
            id="dataset_workbook",
            status="fail",
            summary="The dataset workbook could not be parsed.",
            details={"path": str(DATASET_WORKBOOK), "error": str(exc)},
            fix_hint="Fix `mosaic-bench.xlsx` or the workbook parser before relying on dataset-backed manifests.",
        )

    gaps = summary.get("registry_gaps", {})
    missing = sum(len(gaps.get(key, [])) for key in ("missing_registry", "missing_task_id", "missing_poc"))
    status = "warn" if missing else "ok"
    summary_text = (
        f"Loaded workbook dataset with {summary['chain_count']} chains across {len(summary['apps'])} apps."
    )
    return DoctorCheck(
        id="dataset_workbook",
        status=status,
        summary=summary_text,
        details=summary,
        fix_hint=(
            "Fix workbook-to-registry gaps before treating the dataset as submission-ready."
            if missing
            else None
        ),
    )


def check_results_manifest() -> DoctorCheck:
    from .dataset import DATASET_WORKBOOK
    from .results_manifest import RESULTS_MANIFEST_PATH, load_results_manifest
    from benchmark.validation.ledger import validate_results_ledger

    try:
        manifest = load_results_manifest(RESULTS_MANIFEST_PATH)
    except FileNotFoundError:
        return DoctorCheck(
            id="results_manifest",
            status="warn",
            summary="Results ledger not shipped with the public release; ASR/BugBot tables live in mosaic-bench.xlsx and the paper.",
            details={"path": str(RESULTS_MANIFEST_PATH)},
            fix_hint="Optional: copy `benchmark/results/manifest.json.template` → `manifest.json` to track your local re-runs. See benchmark/results/README.md.",
        )
    except Exception as exc:
        return DoctorCheck(
            id="results_manifest",
            status="warn",
            summary="Results ledger present but unreadable.",
            details={"path": str(RESULTS_MANIFEST_PATH), "error": str(exc)},
            fix_hint="Repair or remove `benchmark/results/manifest.json`.",
        )

    report = validate_results_ledger(
        workbook=DATASET_WORKBOOK,
        manifest_path=RESULTS_MANIFEST_PATH,
    )
    summary = report.summary
    status = "fail" if summary["fail"] else ("warn" if summary["warn"] else "ok")
    return DoctorCheck(
        id="results_manifest",
        status=status,
        summary=(
            f"Public results ledger checked with {summary['pass']} pass, "
            f"{summary['warn']} warn, {summary['fail']} fail findings."
        ),
        details={
            "path": str(RESULTS_MANIFEST_PATH),
            "dataset_workbook": manifest.dataset_workbook,
            "archive_root": str(manifest.archive_root),
            "finding_sample": [finding.model_dump() for finding in report.findings if finding.level.value != "pass"][:5],
        },
        fix_hint=(
            "Anchor the ledger to mosaic-bench.xlsx and keep canonical/validation/archive entries schema-valid."
            if status != "ok"
            else None
        ),
    )


def check_public_manifests() -> DoctorCheck:
    from .manifests import load_batch_manifest

    manifest_paths = [
        Path("benchmark/manifests/starter.batch.json"),
        Path("benchmark/manifests/submission-smoke.batch.json"),
        Path("benchmark/manifests/v2-dataset.batch.json"),
    ]
    resolved: list[dict[str, object]] = []
    errors: list[dict[str, str]] = []
    for rel_path in manifest_paths:
        path = Path(__file__).resolve().parent.parent / rel_path
        try:
            config = load_batch_manifest(path)
            resolved.append(
                {
                    "path": str(path),
                    "name": config.name,
                    "subset": config.subset,
                    "output": config.output,
                }
            )
        except Exception as exc:
            errors.append({"path": str(path), "error": str(exc)})

    if errors:
        return DoctorCheck(
            id="public_manifests",
            status="fail",
            summary="One or more canonical public manifests failed to load.",
            details={"errors": errors},
            fix_hint="Repair `benchmark/manifests/*.batch.json` so `mosaic manifest validate` works on the public set.",
        )

    return DoctorCheck(
        id="public_manifests",
        status="ok",
        summary=f"Loaded {len(resolved)} canonical public manifests.",
        details={"manifests": resolved},
    )


def check_cli_commands(commands: Iterable[str]) -> DoctorCheck:
    expected = {
        "run",
        "batch",
        "init",
        "doctor",
        "validate",
        "manifest",
        "warmup",
        "cooldown",
        "chains",
        "tasks",
        "docker",
        "artifacts",
    }
    actual = set(commands)
    missing = sorted(expected - actual)
    if missing:
        return DoctorCheck(
            id="cli_commands",
            status="fail",
            summary="The public CLI surface is missing expected commands.",
            details={"missing": missing},
            fix_hint="Restore the missing public commands before publishing the benchmark surface.",
        )
    return DoctorCheck(
        id="cli_commands",
        status="ok",
        summary="The public CLI surface is present.",
    )


def check_agent_clis(agents: Iterable[str]) -> list[DoctorCheck]:
    probes = {
        "claude": ["--help"],
        "codex": ["--help"],
        "opencode": ["--help"],
        "gemini": ["--help"],
    }
    hints = {
        "claude": "Install Claude Code and ensure `claude` is callable on PATH.",
        "codex": "Install Codex CLI and ensure `codex` is callable on PATH.",
        "opencode": "Install OpenCode and ensure `opencode` is callable on PATH.",
        "gemini": "Install Gemini CLI and ensure `gemini` is callable on PATH.",
    }
    checks: list[DoctorCheck] = []
    for agent in agents:
        binary = agent.strip()
        if not binary:
            continue
        if binary not in probes:
            checks.append(DoctorCheck(
                id=f"agent_{binary}",
                status="skip",
                summary=f"Unknown agent probe `{binary}` was skipped.",
            ))
            continue
        checks.append(_command_check(
            check_id=f"agent_{binary}",
            binary=binary,
            probe=probes[binary],
            missing_hint=hints[binary],
            probe_hint=f"Fix the `{binary}` CLI so `{binary} --help` succeeds.",
        ))
    return checks


def check_model_aliases() -> DoctorCheck:
    from .agent_runners import resolve_model_config

    aliases = [
        "claude-opus",
        "claude-sonnet-46",
        "codex",
        "gemini-flash",
        "gemini-pro",
        "opencode",
        "opencode:openrouter/qwen/qwen3.6-plus",
    ]
    resolved: dict[str, object] = {}
    try:
        for alias in aliases:
            resolved[alias] = resolve_model_config(alias)
    except Exception as exc:
        return DoctorCheck(
            id="model_aliases",
            status="fail",
            summary="Model alias resolution failed.",
            details={"error": str(exc)},
            fix_hint="Fix alias parsing in `mosaic/agent_runners.py` before running matrix jobs.",
        )
    return DoctorCheck(
        id="model_aliases",
        status="ok",
        summary="Model alias resolution succeeded for the public model set.",
        details={"resolved": resolved},
    )


def check_smoke_deploy(task_id: str, tasks_dir: str | None) -> DoctorCheck:
    from .deploy import ABC_BENCH_APPS, _load_warm_state, cooldown, is_warm, warmup
    from .tasks import resolve_tasks_dir

    if task_id not in ABC_BENCH_APPS:
        return DoctorCheck(
            id="smoke_deploy",
            status="fail",
            summary=f"{task_id} is not a supported deployable benchmark app.",
            fix_hint="Choose a task present in `mosaic.deploy.ABC_BENCH_APPS`.",
        )

    tasks_path = resolve_tasks_dir(tasks_dir)
    if is_warm(task_id):
        state = _load_warm_state().get(task_id, {})
        return DoctorCheck(
            id="smoke_deploy",
            status="ok",
            summary=f"{task_id} is already warm.",
            details={"port": state.get("port")},
        )

    try:
        port = warmup(task_id, tasks_path)
    except Exception as exc:
        return DoctorCheck(
            id="smoke_deploy",
            status="fail",
            summary=f"Warmup failed for {task_id}.",
            details={"error": str(exc)},
            fix_hint="Fix Docker/task setup before trying full benchmark runs.",
        )

    try:
        return DoctorCheck(
            id="smoke_deploy",
            status="ok",
            summary=f"Warmup/cooldown succeeded for {task_id}.",
            details={"port": port},
        )
    finally:
        try:
            cooldown(task_id)
        except Exception:
            pass


def run_doctor(
    *,
    tasks_dir: str | None,
    cli_commands: Iterable[str],
    agents: Iterable[str],
    smoke_deploy: str | None = None,
) -> list[DoctorCheck]:
    checks = [
        check_python_package(),
        check_git_cli(),
        check_docker_cli(),
        check_docker_daemon(),
        check_tasks_dir(tasks_dir),
        check_chain_registry(),
        check_dataset_workbook(),
        check_results_manifest(),
        check_public_manifests(),
        check_cli_commands(cli_commands),
        check_model_aliases(),
    ]
    checks.extend(check_agent_clis(agents))
    if smoke_deploy:
        checks.append(check_smoke_deploy(smoke_deploy, tasks_dir))
    return checks


def doctor_exit_code(checks: Iterable[DoctorCheck], *, strict: bool = False) -> int:
    statuses = {check.status for check in checks}
    if "fail" in statuses:
        return 1
    if strict and "warn" in statuses:
        return 1
    return 0


def render_text_report(checks: Iterable[DoctorCheck], *, verbose: bool = False) -> str:
    lines = ["MOSAIC Doctor", ""]
    counts = {"ok": 0, "warn": 0, "fail": 0, "skip": 0}
    for check in checks:
        counts[check.status] = counts.get(check.status, 0) + 1
        lines.append(f"[{check.status.upper():4s}] {check.id}: {check.summary}")
        if verbose and check.details:
            for key, value in check.details.items():
                lines.append(f"       {key}: {value}")
        if check.fix_hint and check.status in {"warn", "fail"}:
            lines.append(f"       fix: {check.fix_hint}")
    lines.extend([
        "",
        f"Summary: ok={counts['ok']} warn={counts['warn']} fail={counts['fail']} skip={counts['skip']}",
    ])
    return "\n".join(lines)
