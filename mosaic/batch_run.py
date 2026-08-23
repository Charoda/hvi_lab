"""Task-grouped batch runner with warm-container-aware parallel scheduling."""

from __future__ import annotations

import ast
import json
import os
import queue
import re
import shutil
import subprocess
import sys
import threading
import time
import uuid
from collections import defaultdict
from concurrent.futures import ThreadPoolExecutor, as_completed
from dataclasses import asdict, dataclass, field
from pathlib import Path
from typing import Any

try:
    import yaml

    _YAML_AVAILABLE = True
except ImportError:
    _YAML_AVAILABLE = False

REPO_ROOT = Path(__file__).resolve().parent.parent
from .tasks import TASKS_DIR as DEFAULT_TASKS_DIR

DEFAULT_MODELS = ["claude-sonnet-46", "claude-opus", "codex"]
RESULTS_DIR = REPO_ROOT / "benchmark" / "results"
MANIFEST_PATH = RESULTS_DIR / "MANIFEST.yaml"
TERMINAL_SKIP_VERDICTS = {"VULNERABLE", "SECURE", "REFUSAL"}

# Batch execution is parallel only across task families. A single worker owns
# one task's warm container lifecycle end-to-end so hot-swap and cooldown stay
# deterministic even while other tasks run concurrently.


@dataclass(frozen=True)
class RunItem:
    chain_id: str
    task_id: str
    model: str


@dataclass
class BatchTaskResult:
    task_id: str
    owner_id: str
    output_path: str
    log_path: str
    total_runs: int
    completed_runs: int = 0
    failures: int = 0
    status: str = "pending"
    error: str = ""
    current_chain: str | None = None
    current_model: str | None = None
    child_pid: int | None = None
    current_stage: str | None = None
    last_event: str | None = None
    last_heartbeat_at: str | None = None
    verdict_counts: dict[str, int] = field(default_factory=dict)
    review_counts: dict[str, int] = field(default_factory=dict)
    runs: list[dict[str, Any]] = field(default_factory=list)


@dataclass
class BatchExecutionResult:
    batch_id: str
    batch_root: str
    jobs: int
    warm: bool
    output: str | None
    merged_output: str | None
    failures: int
    total_runs: int
    verdict_counts: dict[str, int] = field(default_factory=dict)
    review_counts: dict[str, int] = field(default_factory=dict)
    task_results: dict[str, BatchTaskResult] = field(default_factory=dict)


@dataclass(frozen=True)
class TrialExecutionResult:
    return_code: int
    verdict: str
    review_verdict: str | None
    duration_s: float
    run_dir: str | None = None


@dataclass(frozen=True)
class BatchOptions:
    tasks_dir: str
    output: str | None
    warm: bool
    jobs: int
    batch_id: str
    batch_root: Path
    task_outputs: dict[str, str]
    stage_timeout: int
    ablation: str
    per_stage_oracle: bool
    refusal_footer: bool
    mutation_policy: str
    resume_session: bool
    verbose: bool
    review: str | None
    review_stage: int | None
    reviewer: str
    pool_size: int = 1
    global_cap: int = 8


def _active_jsonl_files(results_dir: Path) -> list[Path]:
    if MANIFEST_PATH.exists() and _YAML_AVAILABLE:
        with open(MANIFEST_PATH) as fh:
            manifest = yaml.safe_load(fh) or {}
        active = manifest.get("active") or {}
        paths = []
        for file_name in active:
            path = results_dir / file_name
            if path.exists():
                paths.append(path)
        return sorted(paths)
    return sorted(results_dir.glob("*.jsonl"))


def _extract_verdict(row: dict) -> str:
    verdict = (
        row.get("verdict")
        or row.get("final_verdict")
        or row.get("poc_verdict")
        or ""
    )
    if verdict:
        return verdict
    oracle = row.get("oracle_result", {})
    if isinstance(oracle, str):
        try:
            oracle = ast.literal_eval(oracle)
        except Exception:
            oracle = {}
    if isinstance(oracle, dict):
        return oracle.get("verdict", "")
    return ""


def load_tested(results_dir: str = "benchmark/results") -> dict[str, set[str]]:
    """Load chain_id -> models with latest canonical terminal verdicts."""
    tested: dict[str, set[str]] = defaultdict(set)
    latest_rows: dict[tuple[str, str], tuple[tuple[str, int, int], str]] = {}
    base_dir = (REPO_ROOT / results_dir).resolve() if not Path(results_dir).is_absolute() else Path(results_dir)
    for source_idx, file_name in enumerate(_active_jsonl_files(base_dir)):
        with open(file_name) as fh:
            for line_idx, line in enumerate(fh, 1):
                line = line.strip()
                if not line:
                    continue
                try:
                    data = json.loads(line)
                except json.JSONDecodeError:
                    continue
                chain_id = data.get("chain_id", "")
                model = data.get("model", "")
                verdict = _extract_verdict(data)
                if not chain_id or not model or not verdict:
                    continue
                sort_key = (data.get("timestamp", ""), source_idx, line_idx)
                key = (chain_id, model)
                current = latest_rows.get(key)
                if current is None or sort_key >= current[0]:
                    latest_rows[key] = (sort_key, verdict)

    for (chain_id, model), (_, verdict) in latest_rows.items():
        if verdict in TERMINAL_SKIP_VERDICTS:
            tested[chain_id].add(model)
    return tested


def load_chain_map(
    *,
    chain_ids: list[str] | None = None,
    task_ids: list[str] | None = None,
    all_chains: bool = False,
) -> dict[str, str]:
    """Map chain_id -> task_id from chain manifests."""
    from .chain_registry import load_chains

    selected = set(chain_ids or [])
    task_filter = set(task_ids or [])
    mapping: dict[str, str] = {}

    for chain in load_chains():
        if not all_chains and selected and chain.chain_id not in selected:
            continue
        if task_filter and chain.task_id not in task_filter:
            continue
        if chain.task_id:
            mapping[chain.chain_id] = chain.task_id
    return mapping


def default_output_for_task(task_id: str) -> str:
    safe = task_id.replace("task_", "").replace("/", "-")
    return f"benchmark/results/compliance_warm_{safe}.jsonl"


def _resolve_jobs(requested: str | int | None, task_count: int, warm: bool) -> int:
    if requested in (None, "auto"):
        return min(4, task_count) if warm else 1
    jobs = int(requested)
    return max(1, min(jobs, max(1, task_count)))


def _batch_root(batch_id: str) -> Path:
    return RESULTS_DIR / "batches" / batch_id


def _task_log_path(batch_root: Path, task_id: str) -> Path:
    return batch_root / "logs" / f"{task_id}.log"


def _task_spool_path(batch_root: Path, task_id: str) -> Path:
    return batch_root / "tasks" / f"{task_id}.jsonl"


def _slot_owner(batch_id: str, task_id: str, slot_id: int = 0) -> str:
    """Per-slot ownership token threaded into MOSAIC_WARM_OWNER.

    Slot 0 produces ``{batch_id}:{task_id}`` (backward compat with pre-pool code).
    """
    base = f"{batch_id}:{task_id}"
    return f"{base}:s{slot_id}" if slot_id else base


def _distribute_to_slots(items: list[RunItem], pool_size: int) -> list[list[RunItem]]:
    """Round-robin distribute items across *pool_size* slot sub-lists."""
    slots: list[list[RunItem]] = [[] for _ in range(pool_size)]
    for i, item in enumerate(items):
        slots[i % pool_size].append(item)
    return slots


def _extract_run_verdict(stdout: str, returncode: int) -> str:
    for line in stdout.splitlines():
        if "Verdict:" in line:
            return line.strip().replace("  ", " ")
    return f"exit={returncode}"


def _extract_review_verdict(stdout: str) -> str | None:
    for line in stdout.splitlines():
        if "BugBot review" not in line:
            continue
        tail = line.strip().rsplit("...", 1)
        if len(tail) != 2:
            continue
        candidate = tail[1].strip()
        if candidate:
            return candidate
    return None


def _extract_run_artifact_dir(stdout: str) -> str | None:
    for line in stdout.splitlines():
        if "Run audit:" not in line:
            continue
        _, _, tail = line.partition("Run audit:")
        candidate = tail.strip()
        if candidate:
            return candidate
    return None


def _normalize_verdict_label(raw: str) -> str:
    if raw.startswith("Verdict:"):
        return raw.split(":", 1)[1].strip()
    return raw.strip()


def _load_structured_review_verdict(run_dir: str | None) -> str | None:
    if not run_dir:
        return None
    manifest_path = Path(run_dir) / "manifest.json"
    if not manifest_path.exists():
        return None
    try:
        manifest = json.loads(manifest_path.read_text())
    except (OSError, json.JSONDecodeError):
        return None
    review = manifest.get("review")
    if not isinstance(review, dict):
        return None
    verdict = str(review.get("verdict") or "").strip()
    return verdict or None


def _resolve_review_verdict(
    *,
    stdout: str,
    verdict_label: str,
    review_requested: bool,
    run_dir: str | None,
) -> str | None:
    structured = _load_structured_review_verdict(run_dir)
    if structured:
        return structured
    if review_requested and verdict_label in {"INVALID", "NO_ORACLE"}:
        return "SKIP"
    return _extract_review_verdict(stdout)


def _append_log(log_path: Path, cmd: list[str], stdout: str, stderr: str, duration_s: float) -> None:
    log_path.parent.mkdir(parents=True, exist_ok=True)
    with open(log_path, "a") as fh:
        fh.write(f"$ {' '.join(cmd)}\n")
        fh.write(f"duration_s={duration_s:.2f}\n")
        if stdout:
            fh.write("stdout:\n")
            fh.write(stdout.rstrip() + "\n")
        if stderr:
            fh.write("stderr:\n")
            fh.write(stderr.rstrip() + "\n")
        fh.write("\n")


def _write_batch_manifest(path: Path, payload: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, indent=2) + "\n")


def _merge_outputs(task_results: dict[str, BatchTaskResult], merged_path: Path) -> None:
    merged_path.parent.mkdir(parents=True, exist_ok=True)
    with open(merged_path, "w") as out:
        for task_id in sorted(task_results):
            task_output = Path(task_results[task_id].output_path)
            if not task_output.exists():
                continue
            with open(task_output) as fh:
                shutil.copyfileobj(fh, out)


def _merge_live_outputs(task_outputs: dict[str, str], merged_path: Path) -> None:
    merged_path.parent.mkdir(parents=True, exist_ok=True)
    with open(merged_path, "w") as out:
        for task_id in sorted(task_outputs):
            task_output = Path(task_outputs[task_id])
            if not task_output.exists():
                continue
            with open(task_output) as fh:
                shutil.copyfileobj(fh, out)


def _copy_merged_output(merged_path: Path, output: str | None) -> None:
    if not output:
        return
    final_output = Path(output)
    final_output.parent.mkdir(parents=True, exist_ok=True)
    if final_output.resolve() != merged_path.resolve():
        shutil.copyfile(merged_path, final_output)


def _iso_now() -> str:
    return time.strftime("%Y-%m-%dT%H:%M:%S")


def _make_batch_id() -> str:
    return f"{time.strftime('%Y%m%d-%H%M%S')}-{os.getpid()}-{uuid.uuid4().hex[:8]}"


def _stage_from_line(line: str) -> str | None:
    line = line.strip()
    match = re.search(r"\bstage\s+([123])\b", line, re.IGNORECASE)
    if match:
        return f"stage_{match.group(1)}"
    if "Verdict:" in line:
        return "verdict"
    if "Run audit:" in line:
        return "audit"
    return None


def _pid_is_alive(pid: int | None) -> bool:
    if not pid or pid <= 0:
        return False
    try:
        os.kill(pid, 0)
        return True
    except OSError:
        return False


def _heartbeat_age_s(task_result: BatchTaskResult) -> float | None:
    if not task_result.last_heartbeat_at:
        return None
    try:
        heartbeat = time.mktime(time.strptime(task_result.last_heartbeat_at, "%Y-%m-%dT%H:%M:%S"))
    except ValueError:
        return None
    return max(0.0, time.time() - heartbeat)


def _mark_stalled_tasks(task_results: dict[str, BatchTaskResult], *, stage_timeout: int) -> None:
    stall_after_s = max(180, stage_timeout + 120)
    for task_result in task_results.values():
        if task_result.status != "running":
            continue
        if task_result.current_stage in {None, "completed", "stalled"}:
            continue
        age_s = _heartbeat_age_s(task_result)
        if age_s is None or age_s < stall_after_s:
            continue
        if task_result.child_pid is not None and _pid_is_alive(task_result.child_pid):
            task_result.current_stage = "stalled"
            task_result.last_event = f"no progress for {int(age_s)}s while child pid {task_result.child_pid} is still alive"
            continue
        if task_result.child_pid is not None:
            task_result.current_stage = "stalled"
            task_result.last_event = f"child pid {task_result.child_pid} disappeared after {int(age_s)}s without a verdict"
            task_result.child_pid = None
            continue
        task_result.current_stage = "stalled"
        task_result.last_event = f"no progress for {int(age_s)}s and no child pid is recorded"


def _manifest_payload(
    *,
    batch_id: str,
    created_at: str,
    state: str,
    jobs: int,
    warm: bool,
    stage_timeout: int,
    ablation: str,
    per_stage_oracle: bool,
    refusal_footer: bool,
    mutation_policy: str,
    review: str | None,
    review_stage: int | None,
    reviewer: str,
    output: str | None,
    merged_output: str | None,
    task_outputs: dict[str, str],
    grouped: dict[str, list[RunItem]],
    failures: int | None = None,
    total_runs: int | None = None,
    verdict_counts: dict[str, int] | None = None,
    review_counts: dict[str, int] | None = None,
    task_results: dict[str, BatchTaskResult] | None = None,
) -> dict[str, Any]:
    payload: dict[str, Any] = {
        "batch_id": batch_id,
        "controller_pid": os.getpid(),
        "created_at": created_at,
        "updated_at": _iso_now(),
        "state": state,
        "jobs": jobs,
        "warm": warm,
        "stage_timeout": stage_timeout,
        "ablation": ablation,
        "per_stage_oracle": per_stage_oracle,
        "refusal_footer": refusal_footer,
        "mutation_policy": mutation_policy,
        "review": review,
        "review_stage": review_stage,
        "reviewer": reviewer,
        "output": output,
        "merged_output": merged_output,
        "task_outputs": task_outputs,
        "tasks": {task_id: [asdict(item) for item in items] for task_id, items in grouped.items()},
    }
    if failures is not None:
        payload["failures"] = failures
    if total_runs is not None:
        payload["total_runs"] = total_runs
    if verdict_counts is not None:
        payload["verdict_counts"] = verdict_counts
    if review_counts is not None:
        payload["review_counts"] = review_counts
    if task_results is not None:
        payload["task_results"] = {task_id: asdict(task_result) for task_id, task_result in task_results.items()}
    return payload


def _build_run_command(
    item: RunItem,
    *,
    tasks_dir: str,
    output: str,
    reuse_container: bool,
    stage_timeout: int,
    ablation: str,
    per_stage_oracle: bool,
    refusal_footer: bool,
    mutation_policy: str,
    resume_session: bool = False,
    verbose: bool = False,
    review: str | None,
    review_stage: int | None,
    reviewer: str,
) -> list[str]:
    cmd = [
        sys.executable, "-m", "mosaic.cli", "run",
        "-c", item.chain_id,
        "-m", item.model,
        "--tasks-dir", tasks_dir,
        "-o", output,
        "--stage-timeout", str(stage_timeout),
        "--ablation", ablation,
        "--mutation-policy", mutation_policy,
    ]
    if reuse_container:
        cmd.append("--reuse-container")
    if per_stage_oracle:
        cmd.append("--per-stage-oracle")
    if refusal_footer:
        cmd.append("--refusal-footer")
    if resume_session:
        cmd.append("--resume-session")
    if verbose:
        cmd.append("--verbose")
    if review:
        cmd += ["--review", review, "--reviewer", reviewer]
    if review_stage is not None:
        cmd += ["--review-stage", str(review_stage)]
    return cmd


def run_trial(
    item: RunItem,
    *,
    tasks_dir: str,
    output: str,
    reuse_container: bool,
    stage_timeout: int,
    ablation: str,
    per_stage_oracle: bool,
    refusal_footer: bool,
    mutation_policy: str,
    resume_session: bool = False,
    verbose: bool = False,
    review: str | None,
    review_stage: int | None = None,
    reviewer: str,
    owner_id: str | None,
    log_path: Path,
    progress_cb: Any = None,
    slot_id: int | None = None,
) -> TrialExecutionResult:
    """Run a single chain/model pair and return structured execution metadata."""
    cmd = _build_run_command(
        item,
        tasks_dir=tasks_dir,
        output=output,
        reuse_container=reuse_container,
        stage_timeout=stage_timeout,
        ablation=ablation,
        per_stage_oracle=per_stage_oracle,
        refusal_footer=refusal_footer,
        mutation_policy=mutation_policy,
        resume_session=resume_session,
        verbose=verbose,
        review=review,
        review_stage=review_stage,
        reviewer=reviewer,
    )

    env = os.environ.copy()
    if owner_id:
        env["MOSAIC_WARM_OWNER"] = owner_id
    if slot_id is not None:
        env["MOSAIC_WARM_SLOT_ID"] = str(slot_id)

    start = time.time()
    stdout_lines: list[str] = []
    stderr_lines: list[str] = []
    try:
        if progress_cb is None:
            result = subprocess.run(
                cmd,
                cwd=str(REPO_ROOT),
                env=env,
                capture_output=True,
                text=True,
                timeout=max(2400, stage_timeout * 6),
            )
            duration = time.time() - start
            stdout = result.stdout or ""
            stderr = result.stderr or ""
            _append_log(log_path, cmd, stdout, stderr, duration)
            verdict = _extract_run_verdict(stdout, result.returncode)
            verdict_label = _normalize_verdict_label(verdict)
            run_dir = _extract_run_artifact_dir(stdout)
            review_verdict = _resolve_review_verdict(
                stdout=stdout,
                verdict_label=verdict_label,
                review_requested=bool(review),
                run_dir=run_dir,
            )
            return TrialExecutionResult(
                return_code=result.returncode,
                verdict=verdict,
                review_verdict=review_verdict,
                duration_s=duration,
                run_dir=run_dir,
            )

        log_path.parent.mkdir(parents=True, exist_ok=True)
        with open(log_path, "a") as fh:
            fh.write(f"$ {' '.join(cmd)}\n")
            proc = subprocess.Popen(
                cmd,
                cwd=str(REPO_ROOT),
                env=env,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                bufsize=1,
            )
            if progress_cb:
                progress_cb({"type": "pid", "pid": proc.pid})

            def _reader(stream, bucket: list[str], label: str) -> None:
                wrote_header = False
                try:
                    for line in iter(stream.readline, ""):
                        if not wrote_header:
                            fh.write(f"{label}:\n")
                            wrote_header = True
                        fh.write(line)
                        fh.flush()
                        bucket.append(line)
                        if progress_cb and label == "stdout":
                            progress_cb({"type": "stdout", "line": line.rstrip()})
                finally:
                    stream.close()

            stdout_thread = threading.Thread(target=_reader, args=(proc.stdout, stdout_lines, "stdout"), daemon=True)
            stderr_thread = threading.Thread(target=_reader, args=(proc.stderr, stderr_lines, "stderr"), daemon=True)
            stdout_thread.start()
            stderr_thread.start()

            try:
                return_code = proc.wait(timeout=max(2400, stage_timeout * 6))
            except subprocess.TimeoutExpired:
                proc.kill()
                return_code = -1
                stderr_lines.append("batch runner timeout\n")
                fh.write("stderr:\n")
                fh.write("batch runner timeout\n")
                fh.flush()

            stdout_thread.join(timeout=10)
            stderr_thread.join(timeout=10)
            duration = time.time() - start
            fh.write(f"duration_s={duration:.2f}\n\n")

        stdout = "".join(stdout_lines)
        stderr = "".join(stderr_lines)
        verdict = _extract_run_verdict(stdout, return_code)
        verdict_label = _normalize_verdict_label(verdict)
        run_dir = _extract_run_artifact_dir(stdout)
        review_verdict = _resolve_review_verdict(
            stdout=stdout,
            verdict_label=verdict_label,
            review_requested=bool(review),
            run_dir=run_dir,
        )
        return TrialExecutionResult(
            return_code=return_code,
            verdict=verdict,
            review_verdict=review_verdict,
            duration_s=duration,
            run_dir=run_dir,
        )
    except subprocess.TimeoutExpired as exc:
        duration = time.time() - start
        stdout = exc.stdout or ""
        stderr = exc.stderr or ""
        _append_log(log_path, cmd, stdout, stderr or "batch runner timeout", duration)
        return TrialExecutionResult(return_code=-1, verdict="TIMEOUT", review_verdict=None, duration_s=duration, run_dir=None)


def grouped_runs(
    *,
    chain_ids: list[str] | None,
    task_ids: list[str] | None,
    models: list[str],
    skip_tested: bool,
    all_chains: bool = False,
) -> dict[str, list[RunItem]]:
    """Build task -> run items grouped by deploy substrate."""
    chain_map = load_chain_map(chain_ids=chain_ids, task_ids=task_ids, all_chains=all_chains)
    tested = load_tested() if skip_tested else {}
    grouped: dict[str, list[RunItem]] = defaultdict(list)

    for chain_id, task_id in sorted(chain_map.items()):
        for model in models:
            if model in tested.get(chain_id, set()):
                continue
            grouped[task_id].append(RunItem(chain_id=chain_id, task_id=task_id, model=model))
    return dict(sorted(grouped.items()))


def _printer(event_queue: queue.Queue[str | None]) -> None:
    while True:
        event = event_queue.get()
        if event is None:
            break
        print(event, flush=True)


def _run_slot_worker(
    task_id: str,
    slot_id: int,
    items: list[RunItem],
    *,
    options: BatchOptions,
    event_queue: queue.Queue[str | None],
    slot_semaphore: threading.Semaphore | None = None,
    task_result: BatchTaskResult | None = None,
) -> BatchTaskResult:
    """Run a subset of items on one warm slot for *task_id*."""
    from .deploy import cooldown, ensure_warm

    owner_id = _slot_owner(options.batch_id, task_id, slot_id)
    task_output = options.task_outputs[task_id]
    log_path = _task_log_path(options.batch_root, task_id)
    result = task_result or BatchTaskResult(
        task_id=task_id,
        owner_id=owner_id,
        output_path=task_output,
        log_path=str(log_path),
        total_runs=len(items),
    )
    result.owner_id = owner_id
    result.output_path = task_output
    result.log_path = str(log_path)
    result.total_runs = len(items)
    result.status = "running"
    result.last_heartbeat_at = _iso_now()

    observe_mode = "per-stage-oracle" if options.per_stage_oracle else "final-only"
    review_mode = options.review or "off"
    if options.review_stage is not None and options.review:
        review_mode = f"stage-{options.review_stage}"
    from .deploy import _slot_label
    slot_label = _slot_label(slot_id)
    event_queue.put(
        f"[task-start] {task_id}{slot_label} runs={len(items)} output={task_output} "
        f"observe={observe_mode} review={review_mode}"
    )
    warmed = False
    acquired_semaphore = False
    try:
        log_path.parent.mkdir(parents=True, exist_ok=True)
        Path(task_output).parent.mkdir(parents=True, exist_ok=True)
        if options.warm:
            result.current_stage = "warmup"
            result.last_event = f"warming {task_id}{slot_label}"
            result.last_heartbeat_at = _iso_now()
            if slot_semaphore is not None:
                slot_semaphore.acquire()
                acquired_semaphore = True
            port = ensure_warm(task_id, Path(options.tasks_dir), owner_id=owner_id, slot_id=slot_id)
            warmed = True
            result.current_stage = "warm_ready"
            result.last_event = f"warm port {port} ready"
            result.last_heartbeat_at = _iso_now()
            event_queue.put(f"[warmup] {task_id}{slot_label} port={port}")

        for item in items:
            result.current_chain = item.chain_id
            result.current_model = item.model
            result.current_stage = "queued"
            result.last_event = f"queued {item.chain_id} x {item.model}"
            result.last_heartbeat_at = _iso_now()
            if options.warm:
                try:
                    result.current_stage = "warm_check"
                    result.last_event = f"checking warm slot for {item.chain_id}"
                    result.last_heartbeat_at = _iso_now()
                    ensure_warm(task_id, Path(options.tasks_dir), owner_id=owner_id, slot_id=slot_id)
                except Exception as exc:
                    result.status = "warmup_failed"
                    result.error = str(exc)
                    result.failures += len(items) - result.completed_runs
                    event_queue.put(f"[warmup-failed] {task_id}{slot_label} {exc}")
                    return result

            result.current_stage = "run_start"
            result.last_event = f"starting {item.chain_id} x {item.model}"
            result.last_heartbeat_at = _iso_now()
            def _safe_progress_cb(event, _result=result, _item=item):
                # Heartbeats must never bubble exceptions back into ``run_trial`` —
                # the worker subprocess machinery would swallow the error and the
                # batch supervisor would interpret the missing heartbeats as a
                # stall instead of seeing the actual cause.
                try:
                    _update_task_progress(_result, _item, event)
                except Exception as exc:  # pragma: no cover — defensive only
                    print(
                        f"[progress] update failed for {_item.chain_id} x {_item.model}: {exc!r}",
                        flush=True,
                    )

            trial = run_trial(
                item,
                tasks_dir=options.tasks_dir,
                output=task_output,
                reuse_container=options.warm,
                stage_timeout=options.stage_timeout,
                ablation=options.ablation,
                per_stage_oracle=options.per_stage_oracle,
                refusal_footer=options.refusal_footer,
                mutation_policy=options.mutation_policy,
                resume_session=options.resume_session,
                verbose=options.verbose,
                review=options.review,
                reviewer=options.reviewer,
                review_stage=options.review_stage,
                owner_id=owner_id,
                log_path=log_path,
                progress_cb=_safe_progress_cb,
                slot_id=slot_id,
            )
            result.completed_runs += 1
            result.child_pid = None
            result.current_stage = "completed"
            if trial.return_code != 0:
                result.failures += 1
            verdict_label = _normalize_verdict_label(trial.verdict)
            result.verdict_counts[verdict_label] = result.verdict_counts.get(verdict_label, 0) + 1
            if trial.review_verdict:
                result.review_counts[trial.review_verdict] = result.review_counts.get(trial.review_verdict, 0) + 1
            result.runs.append({
                "chain_id": item.chain_id,
                "model": item.model,
                "return_code": trial.return_code,
                "verdict": verdict_label,
                "review_verdict": trial.review_verdict,
                "duration_s": round(trial.duration_s, 2),
                "run_dir": trial.run_dir,
            })
            result.last_event = f"{item.chain_id} -> {verdict_label}"
            result.last_heartbeat_at = _iso_now()
            review_note = f" review={trial.review_verdict}" if trial.review_verdict else ""
            event_queue.put(
                f"[run-done] {task_id}{slot_label} {item.chain_id} x {item.model} -> "
                f"{trial.verdict} ({trial.duration_s:.0f}s){review_note}"
            )

            if options.warm:
                try:
                    from .deploy import revert_warm_code
                    result.current_stage = "revert"
                    result.last_event = f"reverting warm workspace after {item.chain_id}"
                    result.last_heartbeat_at = _iso_now()
                    ok = revert_warm_code(task_id, Path(options.tasks_dir), slot_id=slot_id, owner_id=owner_id)
                    if not ok:
                        result.failures += len(items) - result.completed_runs
                        result.status = "revert_failed"
                        result.error = f"revert_warm_code failed for {task_id}{slot_label}"
                        event_queue.put(f"[revert-failed] {task_id}{slot_label} slot poisoned, aborting remaining runs")
                        return result
                except Exception as exc:
                    result.failures += len(items) - result.completed_runs
                    result.status = "revert_failed"
                    result.error = str(exc)
                    event_queue.put(f"[revert-failed] {task_id}{slot_label} {exc}")
                    return result

        result.status = "completed" if result.failures == 0 else "partial_failure"
        return result
    finally:
        if warmed:
            try:
                cooldown(task_id, owner_id=owner_id, slot_id=slot_id)
                event_queue.put(f"[cooldown] {task_id}{slot_label} complete")
            except Exception as exc:
                result.failures += 1
                if not result.error:
                    result.error = str(exc)
                result.status = "cooldown_failed"
                event_queue.put(f"[cooldown-failed] {task_id}{slot_label} {exc}")
        if acquired_semaphore and slot_semaphore is not None:
            slot_semaphore.release()


def _run_task_group(
    task_id: str,
    items: list[RunItem],
    *,
    options: BatchOptions,
    event_queue: queue.Queue[str | None],
    slot_semaphore: threading.Semaphore | None = None,
    task_result: BatchTaskResult | None = None,
) -> BatchTaskResult:
    """Run all items for a task.  With pool_size>1, fans out across slot workers."""
    if options.pool_size <= 1:
        return _run_slot_worker(
            task_id,
            0,
            items,
            options=options,
            event_queue=event_queue,
            slot_semaphore=slot_semaphore,
            task_result=task_result,
        )

    slot_items = _distribute_to_slots(items, options.pool_size)
    slot_results: list[BatchTaskResult] = []
    with ThreadPoolExecutor(max_workers=options.pool_size) as slot_pool:
        futures = {
            slot_pool.submit(
                _run_slot_worker, task_id, sid, sub_items,
                options=options, event_queue=event_queue, slot_semaphore=slot_semaphore,
            ): sid
            for sid, sub_items in enumerate(slot_items)
            if sub_items
        }
        for future in as_completed(futures):
            sid = futures[future]
            try:
                slot_results.append(future.result())
            except Exception as exc:
                event_queue.put(f"[slot-failed] {task_id} slot={sid} {exc}")
                failed_count = len(slot_items[sid])
                slot_results.append(BatchTaskResult(
                    task_id=task_id,
                    owner_id=_slot_owner(options.batch_id, task_id, sid),
                    output_path=options.task_outputs[task_id],
                    log_path=str(_task_log_path(options.batch_root, task_id)),
                    total_runs=failed_count,
                    failures=failed_count,
                    status="worker_failed",
                    error=str(exc),
                    last_heartbeat_at=_iso_now(),
                ))

    merged = BatchTaskResult(
        task_id=task_id,
        owner_id=_slot_owner(options.batch_id, task_id),
        output_path=options.task_outputs[task_id],
        log_path=str(_task_log_path(options.batch_root, task_id)),
        total_runs=len(items),
        status="running",
        last_heartbeat_at=_iso_now(),
    )
    for sr in slot_results:
        merged.completed_runs += sr.completed_runs
        merged.failures += sr.failures
        merged.runs.extend(sr.runs)
        for k, v in sr.verdict_counts.items():
            merged.verdict_counts[k] = merged.verdict_counts.get(k, 0) + v
        for k, v in sr.review_counts.items():
            merged.review_counts[k] = merged.review_counts.get(k, 0) + v
        if sr.error and not merged.error:
            merged.error = sr.error
    merged.status = "completed" if merged.failures == 0 else "partial_failure"
    return merged


def _update_task_progress(task_result: BatchTaskResult, item: RunItem, event: dict[str, Any]) -> None:
    task_result.current_chain = item.chain_id
    task_result.current_model = item.model
    task_result.last_heartbeat_at = _iso_now()
    event_type = event.get("type")
    if event_type == "pid":
        task_result.child_pid = int(event["pid"])
        task_result.current_stage = "run_spawned"
        task_result.last_event = f"spawned pid={task_result.child_pid}"
        return
    if event_type == "status":
        stage = str(event.get("stage") or "").strip()
        if stage:
            task_result.current_stage = stage
        message = str(event.get("message") or "").strip()
        if message:
            task_result.last_event = message[:240]
        return
    if event_type == "stdout":
        line = str(event.get("line") or "").strip()
        if not line:
            return
        task_result.last_event = line[:240]
        stage = _stage_from_line(line)
        if stage:
            task_result.current_stage = stage


def execute_grouped_runs(
    grouped: dict[str, list[RunItem]],
    *,
    tasks_dir: str,
    output: str | None,
    warm: bool,
    jobs: int,
    stage_timeout: int,
    ablation: str,
    per_stage_oracle: bool,
    refusal_footer: bool,
    mutation_policy: str,
    resume_session: bool = False,
    verbose: bool = False,
    review: str | None,
    review_stage: int | None = None,
    reviewer: str,
    pool_size: int = 1,
    global_cap: int = 8,
) -> BatchExecutionResult:
    """Execute grouped runs with task-level parallelism."""
    batch_id = _make_batch_id()
    batch_root = _batch_root(batch_id)
    batch_root.mkdir(parents=True, exist_ok=True)
    created_at = _iso_now()
    total = sum(len(items) for items in grouped.values())

    task_outputs: dict[str, str] = {}
    for task_id in grouped:
        if output and jobs > 1:
            # Parallel workers never append into the same JSONL live. They spool
            # task-local outputs first, then the parent merges them at the end.
            task_outputs[task_id] = str(_task_spool_path(batch_root, task_id))
        elif output:
            task_outputs[task_id] = output
        else:
            task_outputs[task_id] = str((REPO_ROOT / default_output_for_task(task_id)).resolve())

    # Global concurrency semaphore: limits total warm containers across all tasks.
    # Uses threading.Semaphore (not fcntl) because batch workers are threads in
    # the same process — POSIX file locks are per-process, not per-thread.
    slot_semaphore: threading.Semaphore | None = None
    if warm and pool_size > 1:
        slot_semaphore = threading.Semaphore(global_cap)

    options = BatchOptions(
        tasks_dir=str(tasks_dir),
        output=output,
        warm=warm,
        jobs=jobs,
        batch_id=batch_id,
        batch_root=batch_root,
        task_outputs=task_outputs,
        stage_timeout=stage_timeout,
        ablation=ablation,
        per_stage_oracle=per_stage_oracle,
        refusal_footer=refusal_footer,
        mutation_policy=mutation_policy,
        resume_session=resume_session,
        verbose=verbose,
        review=review,
        review_stage=review_stage,
        reviewer=reviewer,
        pool_size=pool_size,
        global_cap=global_cap,
    )

    manifest_path = batch_root / "manifest.json"
    task_results: dict[str, BatchTaskResult] = {
        task_id: BatchTaskResult(
            task_id=task_id,
            owner_id=_slot_owner(batch_id, task_id),
            output_path=task_outputs[task_id],
            log_path=str(_task_log_path(batch_root, task_id)),
            total_runs=len(items),
            status="pending",
            current_stage="queued",
            last_event="waiting for worker",
            last_heartbeat_at=_iso_now(),
        )
        for task_id, items in grouped.items()
    }
    failures = 0
    verdict_counts: dict[str, int] = {}
    review_counts: dict[str, int] = {}
    state_lock = threading.Lock()
    merged_output: str | None = None
    if output and jobs > 1:
        merged_output = str(batch_root / "merged.jsonl")
    _write_batch_manifest(manifest_path, _manifest_payload(
        batch_id=batch_id,
        created_at=created_at,
        state="running",
        jobs=jobs,
        warm=warm,
        stage_timeout=stage_timeout,
        ablation=ablation,
        per_stage_oracle=per_stage_oracle,
        refusal_footer=refusal_footer,
        mutation_policy=mutation_policy,
        review=review,
        review_stage=review_stage,
        reviewer=reviewer,
        output=output,
        merged_output=merged_output,
        task_outputs=task_outputs,
        grouped=grouped,
        failures=failures,
        total_runs=total,
        verdict_counts=verdict_counts,
        review_counts=review_counts,
        task_results=task_results,
    ))

    stop_manifest = threading.Event()

    def _manifest_loop() -> None:
        while not stop_manifest.wait(5):
            with state_lock:
                if merged_output:
                    merged_path = Path(merged_output)
                    _merge_live_outputs(task_outputs, merged_path)
                    _copy_merged_output(merged_path, output)
                _mark_stalled_tasks(task_results, stage_timeout=stage_timeout)
                payload = _manifest_payload(
                    batch_id=batch_id,
                    created_at=created_at,
                    state="running",
                    jobs=jobs,
                    warm=warm,
                    stage_timeout=stage_timeout,
                    ablation=ablation,
                    per_stage_oracle=per_stage_oracle,
                    refusal_footer=refusal_footer,
                    mutation_policy=mutation_policy,
                    review=review,
                    review_stage=review_stage,
                    reviewer=reviewer,
                    output=output,
                    merged_output=merged_output,
                    task_outputs=task_outputs,
                    grouped=grouped,
                    failures=failures,
                    total_runs=total,
                    verdict_counts=dict(verdict_counts),
                    review_counts=dict(review_counts),
                    task_results=dict(task_results),
                )
            _write_batch_manifest(manifest_path, payload)

    manifest_thread = threading.Thread(target=_manifest_loop, daemon=True)
    manifest_thread.start()

    event_queue: queue.Queue[str | None] = queue.Queue()
    printer_thread = threading.Thread(target=_printer, args=(event_queue,), daemon=True)
    printer_thread.start()
    try:
        with ThreadPoolExecutor(max_workers=jobs) as pool:
            future_map = {
                pool.submit(
                    _run_task_group,
                    task_id,
                    items,
                    options=options,
                    event_queue=event_queue,
                    slot_semaphore=slot_semaphore,
                    task_result=task_results[task_id],
                ): task_id
                for task_id, items in grouped.items()
            }
            for future in as_completed(future_map):
                task_id = future_map[future]
                try:
                    task_result = future.result()
                except Exception as exc:
                    task_result = task_results[task_id]
                    task_result.owner_id = _slot_owner(batch_id, task_id)
                    task_result.output_path = task_outputs[task_id]
                    task_result.log_path = str(_task_log_path(batch_root, task_id))
                    task_result.total_runs = len(grouped[task_id])
                    task_result.failures = len(grouped[task_id])
                    task_result.status = "worker_failed"
                    task_result.error = str(exc)
                    task_result.last_event = str(exc)
                    task_result.last_heartbeat_at = _iso_now()
                    event_queue.put(f"[task-failed] {task_id} {exc}")
                with state_lock:
                    task_results[task_id] = task_result
                    failures += task_result.failures
                    for verdict, count in task_result.verdict_counts.items():
                        verdict_counts[verdict] = verdict_counts.get(verdict, 0) + count
                    for review_verdict, count in task_result.review_counts.items():
                        review_counts[review_verdict] = review_counts.get(review_verdict, 0) + count
                    if merged_output:
                        merged_path = Path(merged_output)
                        _merge_outputs(task_results, merged_path)
                        _copy_merged_output(merged_path, output)
                event_queue.put(
                    f"[task-summary] {task_id} status={task_result.status} "
                    f"completed={task_result.completed_runs}/{task_result.total_runs} "
                    f"failures={task_result.failures} verdicts={task_result.verdict_counts} "
                    f"reviews={task_result.review_counts}"
                )
    finally:
        stop_manifest.set()
        manifest_thread.join(timeout=10)
        event_queue.put(None)
        printer_thread.join()

    if output and jobs > 1:
        merged_path = Path(merged_output) if merged_output else batch_root / "merged.jsonl"
        _merge_outputs(task_results, merged_path)
        merged_output = str(merged_path)
        _copy_merged_output(merged_path, output)

    result = BatchExecutionResult(
        batch_id=batch_id,
        batch_root=str(batch_root),
        jobs=jobs,
        warm=warm,
        output=output,
        merged_output=merged_output,
        failures=failures,
        total_runs=total,
        verdict_counts=verdict_counts,
        review_counts=review_counts,
        task_results=task_results,
    )
    _write_batch_manifest(manifest_path, _manifest_payload(
        batch_id=batch_id,
        created_at=created_at,
        state="completed" if failures == 0 else "partial_failure",
        jobs=jobs,
        warm=warm,
        stage_timeout=stage_timeout,
        ablation=ablation,
        per_stage_oracle=per_stage_oracle,
        refusal_footer=refusal_footer,
        mutation_policy=mutation_policy,
        review=review,
        review_stage=review_stage,
        reviewer=reviewer,
        output=output,
        merged_output=merged_output,
        task_outputs=task_outputs,
        grouped=grouped,
        failures=failures,
        total_runs=total,
        verdict_counts=verdict_counts,
        review_counts=review_counts,
        task_results=task_results,
    ))

    # Post-batch hygiene: clean stale warm state + full Docker GC
    try:
        from .deploy import cleanup_stale_warm_state, docker_gc
        cleanup_stale_warm_state()
        gc_report = docker_gc(verbose=True)
    except Exception as exc:
        print(f"post-batch cleanup warning: {exc}")

    return result


def run_batch(
    *,
    chain_ids: list[str] | None = None,
    task_ids: list[str] | None = None,
    models: list[str] | None = None,
    tasks_dir: str = DEFAULT_TASKS_DIR,
    output: str | None = None,
    skip_tested: bool = False,
    warm: bool = True,
    all_chains: bool = False,
    jobs: str | int | None = "auto",
    stage_timeout: int = 600,
    ablation: str = "full",
    per_stage_oracle: bool = False,
    refusal_footer: bool = False,
    mutation_policy: str = "invalidate",
    resume_session: bool = False,
    verbose: bool = False,
    review: str | None = None,
    review_stage: int | None = None,
    reviewer: str = "codex",
    pool_size: int = 1,
    global_cap: int = 8,
) -> int:
    """Public entrypoint for grouped batch execution."""
    pool_size = max(1, pool_size)
    global_cap = max(1, global_cap)
    models = models or list(DEFAULT_MODELS)
    if not all_chains and not chain_ids and not task_ids:
        print("Specify at least one chain, task, or all_chains=True.", file=sys.stderr)
        return 2

    grouped = grouped_runs(
        chain_ids=chain_ids,
        task_ids=task_ids,
        models=models,
        skip_tested=skip_tested,
        all_chains=all_chains,
    )
    total = sum(len(items) for items in grouped.values())
    print(f"Queued {total} runs across {len(grouped)} tasks")
    if not total:
        print("Nothing to run.")
        return 0

    resolved_jobs = _resolve_jobs(jobs, len(grouped), warm)
    requested_parallel = jobs not in (None, "auto") and int(jobs) > 1
    if not warm and requested_parallel:
        print("Parallel batch execution requires warm mode. Remove --no-warm or force --jobs 1.", file=sys.stderr)
        return 2

    try:
        from .deploy import cleanup_stale_warm_state
        cleanup_stale_warm_state()
    except Exception as exc:
        print(f"pre-batch cleanup warning: {exc}")

    result = execute_grouped_runs(
        grouped,
        tasks_dir=tasks_dir,
        output=output,
        warm=warm,
        jobs=resolved_jobs,
        stage_timeout=stage_timeout,
        ablation=ablation,
        per_stage_oracle=per_stage_oracle,
        refusal_footer=refusal_footer,
        mutation_policy=mutation_policy,
        resume_session=resume_session,
        verbose=verbose,
        review=review,
        review_stage=review_stage,
        reviewer=reviewer,
        pool_size=pool_size,
        global_cap=global_cap,
    )
    print(f"\nFinished batch {result.batch_id} with {result.failures} non-zero runs.")
    if result.merged_output:
        print(f"Merged output: {result.merged_output}")
    print(f"Batch artifacts: {result.batch_root}")
    return 1 if result.failures else 0
