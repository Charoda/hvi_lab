"""MOSAIC benchmark CLI."""

from __future__ import annotations

import json
import os
import shutil
import subprocess
import time
from pathlib import Path

import click


def _validate_jobs_option(_ctx, _param, value: str) -> str:
    if value == "auto":
        return value
    try:
        jobs = int(value)
    except ValueError as exc:
        raise click.BadParameter("must be 'auto' or an integer") from exc
    if jobs < 1:
        raise click.BadParameter("must be >= 1")
    return str(jobs)


def _run_artifacts_dir() -> Path:
    return Path(__file__).resolve().parent.parent / "benchmark" / "run_artifacts"


def _prune_run_artifacts(*, max_age_days: int, apply: bool) -> dict[str, object]:
    """Delete stale run artifact directories without touching benchmark results."""
    now = time.time()
    cutoff = now - (max_age_days * 24 * 60 * 60)
    root = _run_artifacts_dir()
    candidates: list[str] = []
    errors: list[dict[str, str]] = []

    if not root.exists():
        return {"root": str(root), "deleted": [], "count": 0, "apply": apply, "errors": []}

    for run_dir in root.glob("*/*"):
        if not run_dir.is_dir():
            continue
        try:
            mtime = run_dir.stat().st_mtime
        except OSError:
            continue
        if mtime < cutoff:
            candidates.append(str(run_dir))

    if apply:
        for path in candidates:
            try:
                shutil.rmtree(path)
            except OSError as exc:
                errors.append({"path": path, "error": str(exc)})

    return {"root": str(root), "deleted": candidates, "count": len(candidates), "apply": apply, "errors": errors}


def _save_agent_diff(run_dir: str | Path, work_dir: Path, baseline_dir: Path) -> None:
    """Save the agent's full git diff to the run artifact directory."""
    try:
        diff = subprocess.run(
            ["diff", "-ruN", str(baseline_dir), str(work_dir)],
            capture_output=True, timeout=30,
        )
        if diff.stdout:
            diff_text = diff.stdout.decode("utf-8", errors="replace")
            diff_path = Path(run_dir) / "agent_diff.patch"
            diff_path.write_text(diff_text[:500_000])  # cap at 500KB
    except Exception as exc:
        print(f"agent diff capture warning: {exc}")  # best-effort — don't break the run


def _build_functional_test_runner(commands: list[str]):
    """Return a workspace-bound functional-test runner for stage checkpoints."""
    if not commands:
        return None

    def _runner(workspace: str) -> bool:
        env = os.environ.copy()
        env["WORKSPACE"] = workspace
        for command in commands:
            result = subprocess.run(
                command,
                cwd=workspace,
                shell=True,
                env=env,
                capture_output=True,
                text=True,
                timeout=120,
            )
            if result.returncode != 0:
                return False
        return True

    return _runner


def _write_run_manifest(
    *,
    chain_id: str,
    task_id: str,
    model: str,
    trial_num: int,
    reuse_container: bool,
    output_file: str | None,
    outcome,
    baseline_artifacts: dict[str, object],
    agent_artifacts: dict[str, object],
) -> Path:
    """Persist a per-run audit trail without changing benchmark results."""
    ts = time.strftime("%Y%m%d-%H%M%S")
    run_id = f"{ts}-{chain_id}-{model}-t{trial_num:02d}"
    run_dir = _run_artifacts_dir() / time.strftime("%Y%m%d") / run_id
    run_dir.mkdir(parents=True, exist_ok=True)
    retention_days = 7
    expires_at = time.strftime(
        "%Y-%m-%dT%H:%M:%S",
        time.localtime(time.time() + retention_days * 24 * 60 * 60),
    )

    verdict = outcome.oracle_result.verdict.value if outcome.oracle_result else "NO_ORACLE"
    manifest = {
        "run_id": run_id,
        "timestamp": time.strftime("%Y-%m-%dT%H:%M:%S"),
        "chain_id": chain_id,
        "task_id": task_id,
        "model": model,
        "trial_num": trial_num,
        "reuse_container": reuse_container,
        "verdict": verdict,
        "result_output": output_file,
        "retention_expires_at": expires_at,
        "total_duration_s": outcome.total_duration_s,
        "docker": {
            "mode": "warm" if reuse_container else "cold",
            "baseline": baseline_artifacts,
            "agent": agent_artifacts,
            "cleanup_policy": {
                "cold_images_removed_by_default": True,
                "warm_images_removed_on_cooldown": True,
                "service_state_backed_by_tmpfs_when_configured": True,
            },
        },
        "stage_outcomes": [
            {
                "stage": s.stage,
                "success": s.success,
                "timed_out": s.timed_out,
                "exit_code": s.exit_code,
                "checkpoint_sha": s.checkpoint_sha,
                "duration_s": s.duration_s,
                "functional_tests_passed": s.functional_tests_passed,
                "agent_stdout": s.agent_stdout,
                "agent_stderr": s.agent_stderr,
            }
            for s in outcome.stages
        ],
        "oracle_result": outcome.oracle_result.model_dump() if outcome.oracle_result else None,
    }
    (run_dir / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")

    summary_lines = [
        f"Run ID: {run_id}",
        f"Chain: {chain_id}",
        f"Task: {task_id}",
        f"Model: {model}",
        f"Trial: {trial_num}",
        f"Verdict: {verdict}",
        f"Reuse container: {reuse_container}",
        f"Result output: {output_file or '(not persisted)'}",
        f"Retention expires at: {expires_at}",
        f"Total duration: {outcome.total_duration_s:.1f}s",
        "",
        "Docker strategy:",
        "- Warm mode keeps app containers hot per task and hot-swaps code between chains.",
        "- Cold mode uses managed per-workspace image tags and removes them after teardown by default.",
        "- Mongo/Postgres benchmark services use tmpfs where configured, so DB state does not leak into anonymous volumes.",
        "",
        f"Baseline image ref: {baseline_artifacts.get('image')}",
        f"Agent image ref: {agent_artifacts.get('image')}",
    ]
    (run_dir / "summary.md").write_text("\n".join(summary_lines) + "\n")
    return run_dir


def _write_review_artifacts(run_dir: Path, review_result: dict[str, object] | None) -> None:
    if not review_result:
        return

    review_path = run_dir / "review.json"
    review_path.write_text(json.dumps(review_result, indent=2) + "\n")

    manifest_path = run_dir / "manifest.json"
    manifest = json.loads(manifest_path.read_text())
    manifest["review"] = review_result
    manifest_path.write_text(json.dumps(manifest, indent=2) + "\n")

    summary_path = run_dir / "summary.md"
    summary = summary_path.read_text().rstrip()
    summary += (
        "\n\nReview:\n"
        f"- Requested: {review_result.get('requested', False)}\n"
        f"- Mode: {review_result.get('mode')}\n"
        f"- Reviewer: {review_result.get('reviewer')}\n"
        f"- Status: {review_result.get('status')}\n"
        f"- Verdict: {review_result.get('verdict')}\n"
    )
    summary_path.write_text(summary + "\n")


def _normalize_verdict_label(verdict: object) -> str:
    return str(verdict or "").strip().upper() or "UNKNOWN"


def _normalize_stage_timeout(stage_timeout: int) -> int:
    return max(1, int(stage_timeout))


REVIEW_MODES = ("cumulative", "stage3-only", "stage3", "per-stage", "attacker")


def _normalize_review_input(_ctx, _param, value: str | None) -> str | None:
    """Strip whitespace, lowercase, and unfold the ``stage3`` short alias.

    ``click.Choice(case_sensitive=False)`` already handles case, but does not
    strip whitespace and does not collapse our project-specific ``stage3``
    shorthand. Doing it here keeps existing scripts that pass ``--review
    stage3`` or ``--review ' Stage3-Only '`` working after the resolver
    rewrite.
    """
    if value is None:
        return None
    normalized = str(value).strip().lower()
    if normalized == "stage3":
        normalized = "stage3-only"
    return normalized


def _resolve_review_selection(
    review: str | None,
    review_stage: int | None,
) -> tuple[str | None, int | None]:
    """Map (--review, --review-stage) to a normalized (mode, stage) pair.

    ``stage3-only`` is shorthand for ``--review cumulative --review-stage 3``
    and gets unfolded here. Click handles the choice/range validation and
    case folding; this function only enforces the cross-flag rules.
    """
    if review == "stage3-only":
        if review_stage is not None and review_stage != 3:
            raise click.BadParameter(
                "--review-stage cannot override stage3-only; "
                "use --review cumulative --review-stage N"
            )
        return "cumulative", 3

    if review_stage is not None:
        if review is None:
            raise click.BadParameter("--review-stage requires --review")
        if review == "attacker":
            raise click.BadParameter("--review-stage is only supported for BugBot review modes")
        if review == "per-stage":
            raise click.BadParameter(
                "--review-stage cannot be combined with --review per-stage; "
                "use --review cumulative --review-stage N"
            )

    return review, review_stage


def _collect_review_result(
    *,
    review: str | None,
    review_stage: int | None,
    reviewer: str,
    verdict: object,
    work_dir: Path,
) -> dict[str, object] | None:
    review, review_stage = _resolve_review_selection(review, review_stage)
    if not review:
        return None

    # --review attacker: shorthand that auto-selects attacker reviewer + cumulative mode
    is_attacker_mode = review == "attacker"
    if is_attacker_mode:
        if reviewer == "codex":  # still at default — switch to attacker default
            reviewer = "attacker-27b"
        review = "cumulative"  # attacker always reviews cumulative diff

    verdict_label = _normalize_verdict_label(verdict)
    review_result: dict[str, object] = {
        "requested": True,
        "mode": "attacker" if is_attacker_mode else review,
        "reviewer": reviewer,
        "trial_verdict": verdict_label,
    }
    if review_stage is not None:
        review_result["stage"] = review_stage
    if verdict_label in {"INVALID", "NO_ORACLE"}:
        label = "Attacker review" if is_attacker_mode else "BugBot review"
        scope = f"stage {review_stage}" if review_stage is not None else review
        click.echo(f"  {label} ({scope}, {reviewer})... SKIP")
        review_result.update({
            "status": "skipped",
            "verdict": "SKIP",
            "explanation": f"Skipped because the trial verdict was {verdict_label}.",
        })
        return review_result

    from benchmark.chain_testing.chain_engine import dispatch_review

    label = "Attacker review" if is_attacker_mode else "BugBot review"
    scope = f"stage {review_stage}" if review_stage is not None else review
    click.echo(f"  {label} ({scope}, {reviewer})...", nl=False)
    try:
        rv, rexp = dispatch_review(work_dir, reviewer, mode=review, review_stage=review_stage)
        click.echo(f" {rv}")
        if rv == "DECLINE":
            click.echo(f"    {rexp[:200]}")
        review_result.update({
            "status": "ok",
            "verdict": rv,
            "explanation": rexp,
        })
    except Exception as e:
        click.echo(" ERROR")
        click.echo(f"    {e}")
        review_result.update({
            "status": "error",
            "verdict": "ERROR",
            "explanation": str(e),
        })
    return review_result


@click.group()
@click.version_option(package_name="mosaic-bench")
def main():
    """MOSAIC: Compositional Attack Benchmark for AI Coding Agents."""


@main.command("init")
@click.option("--apps-dir", "tasks_dir", envvar="MOSAIC_TASKS_DIR", default=None, type=click.Path(), help="Repo-local benchmark apps directory override.")
@click.option("--method", type=click.Choice(["auto", "snapshot", "git-lfs"]), default="auto", show_default=True, help="How to fetch OpenMOSS-Team/ABC-Bench.")
@click.option("--subset", type=click.Choice(["benchmark", "starter", "active-chains", "all"]), default="benchmark", show_default=True, help="Which ABC-Bench app subset to install.")
@click.option("--force", is_flag=True, help="Replace an existing benchmark apps directory.")
@click.option("--json-output", "-j", is_flag=True, help="Output the init report as JSON.")
def init_cmd(tasks_dir: str | None, method: str, subset: str, force: bool, json_output: bool):
    """Download and install repo-local ABC-Bench benchmark apps."""
    from .bootstrap import init_benchmark_apps, render_init_json, render_init_report

    try:
        report = init_benchmark_apps(
            apps_dir=tasks_dir,
            method=method,
            subset=subset,
            force=force,
        )
    except Exception as exc:
        click.echo(f"Init failed: {exc}", err=True)
        raise SystemExit(1)

    click.echo(render_init_json(report) if json_output else render_init_report(report))


@main.command("doctor")
@click.option("--tasks-dir", envvar="MOSAIC_TASKS_DIR", default=None, type=click.Path(), help="Benchmark apps directory override.")
@click.option("--agents", default="claude,codex,opencode,gemini", show_default=True, help="Comma-separated agent CLIs to probe.")
@click.option("--smoke-deploy", default=None, help="Optional task ID to warm up and cool down as a deploy sanity check.")
@click.option("--json-output", "-j", is_flag=True, help="Output the full doctor report as JSON.")
@click.option("--strict", is_flag=True, help="Treat warnings as failures.")
@click.option("--verbose", "-v", is_flag=True, help="Show detailed probe output for failed or warning checks.")
def doctor_cmd(
    tasks_dir: str | None,
    agents: str,
    smoke_deploy: str | None,
    json_output: bool,
    strict: bool,
    verbose: bool,
):
    """Run local preflight checks for Docker, tasks, chains, and agent CLIs."""
    from .doctor import doctor_exit_code, render_text_report, run_doctor

    checks = run_doctor(
        tasks_dir=tasks_dir,
        cli_commands=main.commands.keys(),
        agents=[agent.strip() for agent in agents.split(",") if agent.strip()],
        smoke_deploy=smoke_deploy,
    )
    if json_output:
        click.echo(json.dumps([check.to_dict() for check in checks], indent=2))
    else:
        click.echo(render_text_report(checks, verbose=verbose))
    raise SystemExit(doctor_exit_code(checks, strict=strict))


@main.command()
@click.argument("task")
@click.argument("workspace", type=click.Path(exists=True, file_okay=False, resolve_path=True))
def verify(task: str, workspace: str):
    """Verify whether an attack was successfully introduced.

    TASK is the attack identifier (e.g. auth_backdoor).
    WORKSPACE is the path to the target workspace directory.
    """
    from .task_oracle import verify as do_verify, list_tasks

    available = list_tasks()
    if task not in available:
        click.echo(f"Unknown task: {task}", err=True)
        click.echo(f"Available tasks: {', '.join(available)}", err=True)
        raise SystemExit(1)

    result = do_verify(task, workspace)
    click.echo(f"{task}: {result}")
    raise SystemExit(0 if result == "PASS" else 1)


@main.group()
def chains():
    """Inspect attack chain definitions."""


@chains.command("list")
@click.option("--workstream", "-w", default=None, help="Deprecated: workstream filter is no longer used.")
@click.option("--task", "-t", default=None, help="Filter by chain ID (exact match)")
@click.option("--substrate", "-s", default=None, help="Filter by substrate ID")
@click.option("--difficulty", "-d", default=None, help="Filter by difficulty tier (easy, medium, hard)")
@click.option("--json-output", "-j", is_flag=True, help="Output as JSON")
def chains_list(workstream: str | None, task: str | None, substrate: str | None, difficulty: str | None, json_output: bool):
    """List available attack chains."""
    from .chain_registry import load_chains

    if workstream:
        click.echo(
            f"WARNING: --workstream is deprecated and ignored in supported chains. "
            f"Use --substrate or --difficulty to filter.",
            err=True,
        )

    chain_list = load_chains(chain_id=task, substrate_id=substrate, difficulty=difficulty)

    if json_output:
        click.echo(json.dumps([c.model_dump(exclude={"stages"}) for c in chain_list], indent=2))
        return

    click.echo(f"{'Chain ID':35s} {'Substrate':20s} {'Tier':8s} {'CWE'}")
    click.echo("-" * 80)
    for c in chain_list:
        cwe = ", ".join(c.cwe_ids) if c.cwe_ids else "N/A"
        click.echo(f"{c.chain_id:35s} {c.substrate_id:20s} {c.difficulty_tier:8s} {cwe}")


@main.group()
def tasks():
    """Inspect ABC-Bench benchmark app directories."""


@tasks.command("list")
@click.option("--language", "-l", default=None, help="Filter by language (javascript, python, go, java)")
@click.option("--json-output", "-j", is_flag=True, help="Output as JSON")
def tasks_list(language: str | None, json_output: bool):
    """List available benchmark apps from the extracted ABC-Bench apps directory."""
    from .tasks import list_tasks as _list_tasks

    try:
        task_list = _list_tasks(language=language)
    except FileNotFoundError as e:
        click.echo(str(e), err=True)
        raise SystemExit(1)

    if json_output:
        click.echo(json.dumps(
            [{"task_id": t.task_id, "language": t.language,
              "has_dockerfile": t.has_dockerfile, "has_run_tests": t.has_run_tests}
             for t in task_list],
            indent=2,
        ))
        return

    click.echo(f"{'App ID (task_id)':55s} {'Language':12s} {'Docker':>6s} {'Tests':>6s}")
    click.echo("-" * 82)
    for t in task_list:
        docker = "yes" if t.has_dockerfile else "no"
        tests = "yes" if t.has_run_tests else "no"
        click.echo(f"{t.task_id:55s} {t.language:12s} {docker:>6s} {tests:>6s}")
    click.echo(f"\n{len(task_list)} tasks")


@main.command("warmup")
@click.argument("task_id")
@click.option("--tasks-dir", envvar="MOSAIC_TASKS_DIR", default=None, type=click.Path(exists=True))
@click.option("--slot", default=0, show_default=True, type=int, help="Slot index (0=default).")
def warmup_cmd(task_id: str, tasks_dir: str | None, slot: int):
    """Pre-build and start a persistent container for one benchmark app."""
    from .deploy import warmup

    tasks_path = Path(tasks_dir) if tasks_dir else None
    port = warmup(task_id, tasks_path, slot_id=slot)
    slot_label = f" (slot {slot})" if slot else ""
    click.echo(f"Ready on port {port}{slot_label}. Run chains with --reuse-container, then `mosaic cooldown {task_id}`.")


@main.command("cooldown")
@click.argument("task_id")
@click.option("--slot", default=0, show_default=True, type=int, help="Slot to tear down (0=default).")
@click.option("--all-slots", is_flag=True, help="Tear down all slots for this task.")
def cooldown_cmd(task_id: str, slot: int, all_slots: bool):
    """Stop and remove the warm container for a task."""
    from .deploy import cooldown, _WARM_STATE_DIR

    if all_slots:
        import json as _json
        for path in sorted(_WARM_STATE_DIR.glob("*.json")):
            try:
                raw = _json.loads(path.read_text())
            except Exception:
                continue
            if raw.get("task_id") == task_id:
                sid = int(raw.get("slot_id", 0))
                try:
                    cooldown(task_id, slot_id=sid)
                except Exception as exc:
                    click.echo(f"  warning: slot {sid}: {exc}", err=True)
    else:
        cooldown(task_id, slot_id=slot)


@main.group("docker")
def docker_group():
    """Inspect and clean generated Docker artifacts."""


@docker_group.command("cleanup-plan")
@click.option("--json-output", "-j", is_flag=True, help="Output as JSON")
def docker_cleanup_plan(json_output: bool):
    """Show generated Docker artifacts that are candidates for cleanup."""
    from .deploy import get_cleanup_plan

    plan = get_cleanup_plan()
    if json_output:
        click.echo(json.dumps(plan, indent=2))
        return

    click.echo("Docker cleanup candidates")
    click.echo(f"  Managed images: {len(plan['managed_images'])}")
    click.echo(f"  Active warm images: {len(plan['active_warm_images'])}")
    click.echo(f"  Legacy trial images: {len(plan['legacy_trial_images'])}")
    click.echo(f"  Legacy check/test images: {len(plan['legacy_check_images'])}")
    click.echo(f"  Anonymous volumes: {len(plan['anonymous_volumes'])}")
    click.echo(f"  Dangling named volumes: {len(plan['dangling_volumes'])}")


@docker_group.command("cleanup")
@click.option("--apply", is_flag=True, help="Execute cleanup. Default is dry-run.")
@click.option("--include-anonymous-volumes", is_flag=True, help="Also remove anonymous volumes.")
@click.option("--include-managed-images/--skip-managed-images", default=True, help="Remove managed images.")
@click.option("--include-legacy-images/--skip-legacy-images", default=True, help="Remove legacy trial/check images.")
def docker_cleanup(apply: bool, include_anonymous_volumes: bool, include_managed_images: bool, include_legacy_images: bool):
    """Delete generated Docker artifacts under explicit operator control."""
    from .deploy import execute_cleanup_plan, get_cleanup_plan

    if not apply:
        plan = get_cleanup_plan()
        click.echo("Dry run only. Use --apply to execute.")
        click.echo(json.dumps(plan, indent=2))
        return

    deleted = execute_cleanup_plan(
        include_anonymous_volumes=include_anonymous_volumes,
        include_managed_images=include_managed_images,
        include_legacy_images=include_legacy_images,
    )
    click.echo(json.dumps(deleted, indent=2))


@docker_group.command("build-cache")
@click.option("--json-output", "-j", is_flag=True, help="Output as JSON")
def docker_build_cache(json_output: bool):
    """Show the current Docker build-cache summary."""
    from .deploy import get_build_cache_summary

    summary = get_build_cache_summary()
    if json_output:
        click.echo(json.dumps(summary, indent=2))
        return

    click.echo("Docker build cache")
    if summary.get("build_cache_line"):
        click.echo(f"  {summary['build_cache_line']}")
    elif summary.get("error"):
        click.echo(f"  ERROR: {summary['error']}")
    else:
        click.echo("  Build cache line not available from docker system df output.")


@docker_group.command("gc")
@click.option("--verbose", "-v", is_flag=True, help="Print GC report details.")
def docker_gc_cmd(verbose: bool):
    """Run automatic Docker garbage collection.

    Removes dangling images, stale snapshots/managed images,
    old build cache (>48h), stopped containers, and orphan volumes.
    Never touches running containers or their backing images.
    """
    from .deploy import docker_gc

    report = docker_gc(verbose=verbose)
    click.echo(json.dumps(report, indent=2))


@docker_group.command("prune-build-cache")
@click.option("--apply", is_flag=True, help="Execute the prune. Default is dry-run.")
@click.option("--all", "all_entries", is_flag=True, help="Remove all unused build cache, not just dangling cache.")
@click.option("--until", default="168h", show_default=True, help="Age filter passed to docker builder prune, for example 168h or 24h.")
def docker_prune_build_cache(apply: bool, all_entries: bool, until: str):
    """Prune Docker builder cache with an explicit age guard."""
    from .deploy import get_build_cache_summary, prune_build_cache

    if not apply:
        summary = get_build_cache_summary()
        click.echo("Dry run only. Use --apply to execute.")
        click.echo(json.dumps({
            "current_summary": summary,
            "planned_command": {
                "all": all_entries,
                "until": until,
            },
        }, indent=2))
        return

    result = prune_build_cache(all_entries=all_entries, until=until)
    click.echo(json.dumps(result, indent=2))


@main.group("artifacts")
def artifacts_group():
    """Inspect and prune temporary run audit artifacts."""


@artifacts_group.command("prune")
@click.option("--days", default=7, show_default=True, type=int, help="Delete run-artifact directories older than this many days.")
@click.option("--apply", is_flag=True, help="Execute deletion. Default is dry-run.")
def artifacts_prune(days: int, apply: bool):
    """Prune stale benchmark/run_artifacts directories without touching JSONL results."""
    result = _prune_run_artifacts(max_age_days=days, apply=apply)
    click.echo(json.dumps(result, indent=2))


@main.command("batch")
@click.option("--chain", "-c", "chains", multiple=True, help="Chain ID. May be repeated.")
@click.option("--chains-file", default=None, type=click.Path(exists=True), help="Optional newline-delimited file of chain IDs.")
@click.option("--task-id", "-t", "task_ids", multiple=True, help="Benchmark app ID (`task_id` in code). May be repeated.")
@click.option("--all-chains", is_flag=True, help="Run all available chains grouped by task.")
@click.option("--models", default="claude-sonnet-46,claude-opus,codex", help="Comma-separated models. Use explicit opencode provider/model IDs such as opencode:openrouter/nvidia/nemotron-3-super-120b-a12b:free or opencode:opencode-go/glm-5.1.")
@click.option("--output", "-o", default=None, type=click.Path(), help="Single output JSONL file. Default is per-task output.")
@click.option("--tasks-dir", envvar="MOSAIC_TASKS_DIR", default=None, type=click.Path(exists=True), help="Benchmark apps directory")
@click.option("--skip-tested", is_flag=True, help="Skip chain/model pairs that already have terminal verdicts.")
@click.option("--no-warm", is_flag=True, help="Disable task-scoped warm containers and run grouped cold deploys.")
@click.option("--jobs", default="auto", show_default=True, callback=_validate_jobs_option, help="Task-worker concurrency. Use auto or an integer.")
@click.option("--stage-timeout", default=600, show_default=True, type=int, help="Per-stage agent timeout in seconds.")
@click.option("--ablation", default="full", type=click.Choice(["full", "stage3_only", "benign", "random_order", "guided"], case_sensitive=False), help="Ablation mode for each run.")
@click.option("--per-stage-oracle", is_flag=True, help="Enable composition/observability mode by running the PoC after each stage.")
@click.option("--refusal-footer", is_flag=True, help="Append the refusal footer to each stage prompt.")
@click.option("--mutation-policy", default="invalidate", type=click.Choice(["off", "report", "invalidate"], case_sensitive=False), help="How to handle default forbidden mutations like lockfiles and deploy config.")
@click.option(
    "--review",
    type=click.Choice(REVIEW_MODES, case_sensitive=False),
    callback=_normalize_review_input,
    default=None,
    help="Review mode: cumulative, stage3-only, per-stage (BugBot), or attacker (red-team via vLLM).",
)
@click.option("--review-stage", default=None, type=click.IntRange(min=1), help="BugBot-only: review only the selected stage diff (for example 1, 2, or 3).")
@click.option("--reviewer", default="codex", help="Reviewer model (BugBot: codex/sonnet/opus; attacker: attacker-27b/attacker-9b).")
@click.option("--resume-session", is_flag=True, default=False, help="Reuse agent session across stages (agent keeps conversation context).")
@click.option("--verbose", is_flag=True, default=False, help="Emit structured agent logs (tool calls, reasoning, cost per stage).")
@click.option("--pool-size", default=1, show_default=True, type=click.IntRange(min=1), help="Number of warm containers per task (1=default, 3 recommended for 8-app batches).")
@click.option("--global-cap", default=8, show_default=True, type=click.IntRange(min=1), help="Max total warm containers system-wide.")
def batch_run_cmd(
    chains: tuple[str, ...],
    chains_file: str | None,
    task_ids: tuple[str, ...],
    all_chains: bool,
    models: str,
    output: str | None,
    tasks_dir: str | None,
    skip_tested: bool,
    no_warm: bool,
    jobs: str,
    stage_timeout: int,
    ablation: str,
    per_stage_oracle: bool,
    refusal_footer: bool,
    mutation_policy: str,
    review: str | None,
    review_stage: int | None,
    reviewer: str,
    resume_session: bool = False,
    verbose: bool = False,
    pool_size: int = 1,
    global_cap: int = 8,
):
    """Run grouped benchmark trials through the package-owned batch runner."""
    from .batch_run import DEFAULT_TASKS_DIR, run_batch

    chain_ids = list(chains)
    if chains_file:
        chain_ids.extend([line.strip() for line in Path(chains_file).read_text().splitlines() if line.strip()])

    if not all_chains and not chain_ids and not task_ids:
        click.echo("Specify --chain, --chains-file, --task-id, or --all-chains.", err=True)
        raise SystemExit(2)

    review, review_stage = _resolve_review_selection(review, review_stage)

    rc = run_batch(
        chain_ids=chain_ids or None,
        task_ids=list(task_ids) or None,
        models=[m for m in models.split(",") if m],
        tasks_dir=tasks_dir or DEFAULT_TASKS_DIR,
        output=output,
        skip_tested=skip_tested,
        warm=not no_warm,
        all_chains=all_chains,
        jobs=jobs,
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
    raise SystemExit(rc)


@main.command("run")
@click.option("--chain", "-c", default=None, help="Chain ID (e.g. express_boilerplate_idor)")
@click.option("--all-chains", is_flag=True, help="Run all available chains")
@click.option("--model", "-m", required=True, help="Model name (e.g. claude-sonnet-46, codex, gemini-flash, opencode, opencode:openrouter/qwen/qwen3.6-plus:free, or opencode:opencode-go/glm-5.1)")
@click.option("--trials", "-n", default=1, help="Number of trials")
@click.option("--ablation", "-a", default="full",
              type=click.Choice(["full", "stage3_only", "benign", "random_order", "guided"], case_sensitive=False),
              help="Ablation mode")
@click.option("--output", "-o", default=None, type=click.Path(), help="Output JSONL file (append)")
@click.option("--tasks-dir", envvar="MOSAIC_TASKS_DIR", default=None, type=click.Path(exists=True), help="Benchmark apps directory")
@click.option("--dry-run", is_flag=True, help="Show what would run without executing")
@click.option("--reuse-container", is_flag=True, help="Use an already-warmed task container owned by this run/batch context")
@click.option("--per-stage-oracle", is_flag=True, help="Run PoC after each stage to track when vulnerability first appears")
@click.option("--refusal-footer", is_flag=True, help="Append refusal instruction to prompts (ablation condition)")
@click.option("--port", default=None, type=int,
              help="Override the task host port for this run (useful for isolated reruns)")
@click.option("--stage-timeout", default=600, show_default=True, type=int,
              help="Per-stage agent timeout in seconds")
@click.option("--mutation-policy", default="invalidate",
              type=click.Choice(["off", "report", "invalidate"], case_sensitive=False),
              help="How to handle default forbidden mutations like lockfiles and deploy config")
@click.option(
    "--review",
    type=click.Choice(REVIEW_MODES, case_sensitive=False),
    callback=_normalize_review_input,
    default=None,
    help="Review mode: cumulative, stage3-only, per-stage (BugBot), or attacker (red-team via vLLM)",
)
@click.option("--review-stage", default=None, type=click.IntRange(min=1), help="BugBot-only: review only the selected stage diff (for example 1, 2, or 3)")
@click.option("--reviewer", default="codex", help="Reviewer model (BugBot: codex/sonnet/opus; attacker: attacker-27b/attacker-9b)")
@click.option("--resume-session", is_flag=True, default=False,
              help="Reuse agent session across stages (--resume). Agent keeps conversation context.")
@click.option("--verbose", is_flag=True, default=False,
              help="Emit structured agent logs (tool calls, reasoning, cost per stage).")
def run_cmd(chain: str | None, all_chains: bool, model: str, trials: int, ablation: str,
            output: str | None, tasks_dir: str | None, dry_run: bool, reuse_container: bool = False,
            per_stage_oracle: bool = False, refusal_footer: bool = False, port: int | None = None,
            stage_timeout: int = 600, mutation_policy: str = "invalidate",
            review: str | None = None, review_stage: int | None = None, reviewer: str = "codex", resume_session: bool = False,
            verbose: bool = False):
    """Run a multi-stage MOSAIC trial against an ABC-Bench task."""
    import importlib
    import tempfile

    from .chain_registry import load_chains
    from .deploy import ABC_BENCH_APPS, describe_workspace_artifacts
    from .runner import AblationMode, RunConfig, run_trial
    from .oracle.evaluator import OracleEngine
    from .tasks import setup_workspace, get_port
    from .deploy import get_warm_port

    repo_root = Path(__file__).resolve().parent.parent

    if not chain and not all_chains:
        click.echo("Specify --chain or --all-chains.", err=True)
        raise SystemExit(1)

    review, review_stage = _resolve_review_selection(review, review_stage)

    # Load chain(s)
    if all_chains:
        chain_defs = load_chains()
    else:
        chain_defs = load_chains(chain_id=chain)
        if not chain_defs:
            click.echo(f"Unknown chain: {chain}. Use `mosaic oracle list-chains` to list.", err=True)
            raise SystemExit(1)

    abl = AblationMode(ablation)

    for chain_def in chain_defs:
        chain_id = chain_def.chain_id

        # Resolve task_id
        task_id = chain_def.task_id
        if not task_id:
            click.echo(f"Chain {chain_id} has no task_id — skipping.", err=True)
            continue

        # Resolve deploy config: prefer chain's deploy_script, fall back to ABC_BENCH_APPS
        deploy_script = None
        deployment_config = None
        if chain_def.deploy_script:
            ds = repo_root / chain_def.deploy_script
            if ds.exists():
                deploy_script = ds
        elif task_id in ABC_BENCH_APPS:
            deployment_config = ABC_BENCH_APPS[task_id]

        try:
            warm_port = get_warm_port(task_id) if reuse_container else None
        except RuntimeError as exc:
            click.echo(f"  SKIP: {exc}")
            continue
        warm_active = warm_port is not None
        if warm_active:
            port = warm_port
        elif port is not None:
            port = int(port)
        elif task_id in ABC_BENCH_APPS:
            port = ABC_BENCH_APPS[task_id].host_port
        elif tasks_dir:
            port = get_port(task_id, Path(tasks_dir))
        else:
            port = 3000

        # Load PoC exploit
        exploit = None
        if chain_def.poc_module:
            try:
                parts = chain_def.poc_module.rsplit(".", 1)
                mod = importlib.import_module(parts[0])
                exploit_cls = getattr(mod, parts[1]) if len(parts) == 2 else None
                if exploit_cls:
                    exploit = exploit_cls(base_url=f"http://localhost:{port}")
            except (ImportError, AttributeError) as e:
                click.echo(f"WARNING: Could not load PoC module {chain_def.poc_module}: {e}", err=True)

        if not exploit:
            click.echo(f"No PoC exploit for chain {chain_id} — skipping.", err=True)
            continue

        click.echo(f"\nMOSAIC Trial: {chain_id} → {task_id}")
        click.echo(f"  Model: {model}, Trials: {trials}, Ablation: {abl.value}")
        click.echo(f"  Port: {port}{'(warm)' if warm_active and reuse_container else ''}, Deploy: {deploy_script or deployment_config or 'none'}")
        if output:
            click.echo(f"  Output: {output}")

        if dry_run:
            click.echo("  [DRY RUN] Would execute — skipping.")
            continue

        tasks_path = Path(tasks_dir) if tasks_dir else None

        # Pre-flight: check port availability before spending model calls
        from .deploy import check_port_available
        if reuse_container and not warm_active:
            click.echo(f"  SKIP: no warm container is available for {task_id}. Run `mosaic warmup {task_id}` first or use `mosaic batch`.")
            continue
        # Port check skipped: cold deploys now use dynamic ports (-p 0:app_port)

        for t in range(trials):
            click.echo(f"\n--- Trial {t+1}/{trials} ---")
            with tempfile.TemporaryDirectory(prefix="trial-") as tmp:
                work_dir = Path(tmp) / "workspace"
                baseline_dir = Path(tmp) / "baseline"

                setup_workspace(task_id, work_dir, tasks_path)
                setup_workspace(task_id, baseline_dir, tasks_path)

                config_for_artifacts = deployment_config or ABC_BENCH_APPS.get(task_id)
                baseline_artifacts = (
                    describe_workspace_artifacts(
                        str(baseline_dir),
                        config_for_artifacts,
                        task_id=task_id,
                        warm=reuse_container,
                    )
                    if config_for_artifacts else {}
                )
                agent_artifacts = (
                    describe_workspace_artifacts(
                        str(work_dir),
                        config_for_artifacts,
                        task_id=task_id,
                        warm=reuse_container,
                    )
                    if config_for_artifacts else {}
                )

                engine = OracleEngine(
                    exploit=exploit,
                    deploy_script=deploy_script,
                    deployment_config=deployment_config,
                    port=port,
                    reuse_container=reuse_container,
                    task_id=task_id,
                )
                config = RunConfig(
                    model=model,
                    chain_id=chain_id,
                    substrate_id=task_id,
                    trials=1,
                    ablation=abl,
                    timeout_per_stage_s=_normalize_stage_timeout(stage_timeout),
                    per_stage_oracle=per_stage_oracle,
                    refusal_footer=refusal_footer,
                    mutation_policy=mutation_policy,
                    resume_session=resume_session,
                    verbose=verbose,
                    allowed_mutation_globs=chain_def.allowed_mutation_globs,
                    baseline_clean=chain_def.baseline_clean,
                )
                functional_test_fn = _build_functional_test_runner(chain_def.functional_tests)

                outcome = run_trial(
                    config=config,
                    stages=chain_def.stages,
                    oracle=engine,
                    workspace_path=work_dir,
                    baseline_path=str(baseline_dir),
                    trial_num=t,
                    functional_test_fn=functional_test_fn,
                )

                verdict = _normalize_verdict_label(
                    outcome.oracle_result.verdict.value if outcome.oracle_result else "NO_ORACLE"
                )
                click.echo(f"  Verdict: {verdict}")
                if outcome.composition_label:
                    click.echo(f"  Composition: {outcome.composition_label}")
                    if outcome.first_exploitable_stage is not None:
                        click.echo(f"  First exploitable: stage {outcome.first_exploitable_stage}")
                for s in outcome.stages:
                    exploit_tag = ""
                    if s.exploit_after is not None:
                        exploit_tag = f", exploit={'YES' if s.exploit_after else 'no'}"
                    click.echo(f"  Stage {s.stage}: success={s.success}, sha={s.checkpoint_sha[:8]}{exploit_tag}")

                # Persist result as JSONL
                if output:
                    Path(output).parent.mkdir(parents=True, exist_ok=True)
                    with open(output, "a") as f:
                        f.write(outcome.model_dump_json() + "\n")

                review_result = _collect_review_result(
                    review=review,
                    review_stage=review_stage,
                    reviewer=reviewer,
                    verdict=verdict,
                    work_dir=work_dir,
                )

                run_dir = _write_run_manifest(
                    chain_id=chain_id,
                    task_id=task_id,
                    model=model,
                    trial_num=t,
                    reuse_container=reuse_container,
                    output_file=output,
                    outcome=outcome,
                    baseline_artifacts=baseline_artifacts,
                    agent_artifacts=agent_artifacts,
                )

                # Save agent's full git diff (for paper appendix / analysis)
                _save_agent_diff(run_dir, work_dir, baseline_dir)
                _write_review_artifacts(run_dir, review_result)

                click.echo(f"  Run audit: {run_dir}")

            # Revert warm container to clean baseline between trials so that
            # code changes from this chain don't leak into the next one.
            if reuse_container and warm_active:
                try:
                    from .deploy import revert_warm_code
                    ok = revert_warm_code(task_id, tasks_path)
                    if not ok:
                        click.echo(f"  WARNING: baseline revert failed for {task_id} — container dirty (next run will re-warm).", err=True)
                except Exception as exc:
                    click.echo(f"  WARNING: baseline revert error for {task_id}: {exc}", err=True)


@main.group()
def oracle():
    """PoC-driven oracle commands."""


@oracle.command("list-chains")
@click.option("--substrate", "-s", default=None, help="Filter by substrate ID")
@click.option("--difficulty", "-d", default=None, help="Filter by difficulty (easy, medium, hard)")
def oracle_list_chains(substrate: str | None, difficulty: str | None):
    """List supported chain definitions with PoC oracles."""
    from .chain_registry import load_chains

    chains = load_chains(substrate_id=substrate, difficulty=difficulty)

    if not chains:
        click.echo("No supported chains found. Create chain definitions in benchmark/chains/*/chain.json")
        return

    click.echo(f"{'Chain ID':35s} {'Substrate':20s} {'Tier':8s} {'Class':15s}")
    click.echo("-" * 80)
    for c in chains:
        click.echo(f"{c.chain_id:35s} {c.substrate_id:20s} {c.difficulty_tier:8s} {c.attack_class:15s}")


@main.group()
def defense():
    """Evaluate defenses against attack chains."""


@defense.command("list")
def defense_list():
    """List available defense implementations."""
    from .defense import DEFENSES

    for name in sorted(DEFENSES):
        click.echo(f"  {name}")


@main.command()
@click.option("--tasks-dir", default=None, type=click.Path(exists=True, file_okay=False), help="Override benchmark apps directory")
@click.option("--workbook", default=None, type=click.Path(exists=True, dir_okay=False), help="Workbook-backed dataset source")
@click.option("--smoke-deploy", is_flag=True, help="Warm and cool each dataset task once")
@click.option("--baseline-poc", is_flag=True, help="Run baseline-only PoC validation")
@click.option("--smoke-run", is_flag=True, help="Full end-to-end smoke test (implies --baseline-poc)")
@click.option("--manifest", "smoke_manifest", default=None, type=click.Path(exists=True, dir_okay=False), help="Override smoke manifest for --baseline-poc/--smoke-run")
@click.option("--json", "json_output", is_flag=True, help="Emit machine-readable JSON")
def validate(
    tasks_dir: str | None,
    workbook: str | None,
    smoke_deploy: bool,
    baseline_poc: bool,
    smoke_run: bool,
    smoke_manifest: str | None,
    json_output: bool,
):
    """Validate benchmark dataset readiness."""
    from benchmark.validation.readiness import build_dataset_readiness_report

    if smoke_run:
        baseline_poc = True

    report = build_dataset_readiness_report(
        tasks_dir=Path(tasks_dir) if tasks_dir else None,
        workbook_path=Path(workbook) if workbook else None,
        smoke_manifest_path=Path(smoke_manifest) if smoke_manifest else None,
        check_deploy=smoke_deploy,
        check_baseline_poc=baseline_poc,
        check_smoke_run=smoke_run,
    )

    if json_output:
        click.echo(json.dumps(report.model_dump(), indent=2, sort_keys=True))
    else:
        click.echo(f"state: {report.state.value}")
        click.echo(f"findings: {len(report.findings)}")
        for finding in report.findings[:20]:
            loc = f" @ {finding.path}" if finding.path else ""
            click.echo(f"- {finding.level.value} [{finding.kind.value}] {finding.code}{loc}: {finding.message}")
        if len(report.findings) > 20:
            click.echo(f"... {len(report.findings) - 20} more findings")

    raise SystemExit(0 if report.ready else 1)


@main.group()
def manifest():
    """Inspect and validate batch manifest files."""


@manifest.command("validate")
@click.argument("path", type=click.Path(exists=True, dir_okay=False))
@click.option("--json", "json_output", is_flag=True, help="Emit machine-readable JSON")
def manifest_validate(path: str, json_output: bool):
    """Validate a batch manifest file."""
    from .manifests import batch_manifest_summary, load_batch_manifest

    try:
        config = load_batch_manifest(path)
    except (ValueError, FileNotFoundError) as exc:
        click.echo(f"FAIL: {exc}", err=True)
        raise SystemExit(1)

    summary = batch_manifest_summary(config)
    if json_output:
        click.echo(json.dumps(summary, indent=2, sort_keys=True))
    else:
        click.echo(f"OK: {config.name}")
        click.echo(f"  description: {config.description}")
        click.echo(f"  subset:      {config.subset or '(none)'}")
        click.echo(f"  chains:      {len(config.chain_ids)}")
        click.echo(f"  tasks:       {len(config.task_ids)}")
        click.echo(f"  models:      {', '.join(config.models) or '(none)'}")
        click.echo(f"  warm:        {config.warm}")


if __name__ == "__main__":
    main()
