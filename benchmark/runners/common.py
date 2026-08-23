#!/usr/bin/env python3
"""
Shared utilities for BSD experiment runners (WS9, WS10, WS11, interactive).

Extracted from run-ws9.py / run-ws10.py / run-ws11.py to avoid duplication.
Each runner imports what it needs; runner-specific logic stays in its own file.
"""

import json
import os
import shutil
import subprocess
import sys
import tempfile
import time
from collections import defaultdict
from datetime import datetime
from pathlib import Path

# ============================================================================
# MODEL CONFIGURATION
# ============================================================================

MODEL_CONFIGS = {
    "gemini-flash":     {"type": "gemini", "model_id": "gemini-3-flash-preview"},
    "gemini-pro":       {"type": "gemini", "model_id": "gemini-3.1-pro-preview"},
    "claude-sonnet-46": {"type": "claude", "model_id": "claude-sonnet-4-6"},
    "claude-opus":      {"type": "claude", "model_id": "claude-opus-4-6"},
    "codex":            {"type": "codex",  "model_id": "gpt-5.3-codex"},
    "opencode":         {"type": "opencode", "model_id": None},
}

ALL_MODELS = list(MODEL_CONFIGS.keys())


def _trim_output(text, limit=3000):
    if not text:
        return ""
    return text[-limit:]


def _env_int(name, default):
    raw = os.environ.get(name)
    if raw is None or raw == "":
        return default
    try:
        return int(raw)
    except ValueError:
        return default


def _opencode_timeout_s(prompt_text, model_id):
    """Compute a provider-aware timeout with prompt-size slack."""
    override = _env_int("MOSAIC_OPENCODE_TIMEOUT_S", 0)
    if override > 0:
        return override

    base = 900
    normalized = (model_id or "").lower()
    if any(tag in normalized for tag in ("qwen", "deepseek", "minimax")):
        base = 1200
    elif any(tag in normalized for tag in ("claude", "gemini", "grok")):
        base = 1000

    prompt_bonus = min(600, max(0, len(prompt_text) - 4000) // 2000 * 60)
    return base + prompt_bonus


def _is_retryable_opencode_failure(stdout, stderr, exit_code, timed_out):
    if timed_out:
        return True
    haystack = f"{stdout}\n{stderr}".lower()
    terminal_markers = (
        "subscriptionusagelimiterror",
        "subscription quota exceeded",
        "quota exceeded",
        "billing",
        "payment required",
        "you can continue using free models",
        "insufficient credits",
    )
    if any(marker in haystack for marker in terminal_markers):
        return False
    retry_markers = (
        "rate limit",
        "429",
        "temporarily unavailable",
        "try again",
        "timed out",
        "timeout",
        "network",
        "econnreset",
        "connection reset",
        "socket hang up",
        "bad gateway",
        "gateway timeout",
        "502",
        "503",
        "504",
    )
    if any(marker in haystack for marker in retry_markers):
        return True
    if exit_code is None:
        return True
    return False


def _run_subprocess_with_capture(cmd, *, workspace, timeout, env):
    try:
        result = subprocess.run(
            cmd,
            cwd=workspace,
            capture_output=True,
            text=True,
            timeout=timeout,
            env=env,
        )
        return {
            "success": result.returncode == 0,
            "stdout": _trim_output(result.stdout),
            "stderr": _trim_output(result.stderr),
            "exit_code": result.returncode,
            "timed_out": False,
        }
    except subprocess.TimeoutExpired:
        return {"success": False, "stdout": "TIMEOUT", "stderr": "", "exit_code": None, "timed_out": True}


def resolve_model_config(model, model_configs=None):
    """Resolve a model alias, including dynamic opencode aliases.

    Supported dynamic syntax:
    - opencode:<provider/model>
    """
    configs = model_configs or MODEL_CONFIGS
    if model in configs:
        return configs[model]
    if model.startswith("opencode:"):
        model_id = model.split(":", 1)[1].strip()
        if not model_id:
            raise ValueError("opencode model alias requires a provider/model after 'opencode:'")
        return {"type": "opencode", "model_id": model_id}
    raise KeyError(model)


def _prepare_opencode_env(workspace):
    """Route opencode state into a writable temp area and migrate auth forward."""
    env = os.environ.copy()
    data_home = Path(env.get("MOSAIC_OPENCODE_DATA_HOME", tempfile.gettempdir() + "/mosaic-opencode"))
    cache_home = Path(env.get("MOSAIC_OPENCODE_CACHE_HOME", tempfile.gettempdir() + "/mosaic-opencode-cache"))
    auth_src = Path.home() / ".local" / "share" / "opencode" / "auth.json"
    auth_dst = data_home / "opencode" / "auth.json"

    data_home.mkdir(parents=True, exist_ok=True)
    cache_home.mkdir(parents=True, exist_ok=True)
    auth_dst.parent.mkdir(parents=True, exist_ok=True)

    if auth_src.exists():
        try:
            if not auth_dst.exists() or auth_src.read_bytes() != auth_dst.read_bytes():
                shutil.copy2(auth_src, auth_dst)
        except OSError:
            pass

    env["XDG_DATA_HOME"] = str(data_home)
    env["XDG_CACHE_HOME"] = str(cache_home)
    return env

# ============================================================================
# PATH UTILITIES
# ============================================================================

EXPERIMENT_DIR = Path(__file__).resolve().parent.parent  # experiment/
TEMPLATE_DIR   = EXPERIMENT_DIR / "template" / "vuln-webapp"
RESULTS_DIR    = EXPERIMENT_DIR / "results"
VERIFY_SCRIPT  = EXPERIMENT_DIR / "verify.py"


def _default_v1_runs_dir() -> Path:
    """Keep legacy v1 workspaces out of the repository tree by default.

    The old default `benchmark/runs` made it too easy for unrestricted agent CLIs
    to wander into benchmark prompts, results, and verifier code. We now default
    to a temp-rooted persistent directory while still allowing explicit override.
    """
    override = os.environ.get("MOSAIC_V1_RUNS_DIR")
    if override:
        return Path(override).expanduser().resolve()
    return Path(tempfile.gettempdir()) / "workspaces"


RUNS_DIR = _default_v1_runs_dir()


def get_prompts_dir(workstream):
    """Return prompts directory for a workstream.

    WS10 reuses WS9 prompts; others use their own.
    """
    if workstream == "ws10":
        return EXPERIMENT_DIR / "prompts" / "ws9"
    return EXPERIMENT_DIR / "prompts" / workstream

# ============================================================================
# CLI RUNNERS
# ============================================================================

def run_gemini(prompt_text, workspace, model_id):
    cmd = ["gemini", "-p", prompt_text, "-y", "-m", model_id]
    env = os.environ.copy()
    tmpdir = Path(workspace).parent / ".tmp"
    tmpdir.mkdir(parents=True, exist_ok=True)
    env["TMPDIR"] = str(tmpdir)
    try:
        r = subprocess.run(cmd, cwd=workspace, capture_output=True, text=True, timeout=600, env=env)
        return {
            "success": r.returncode == 0,
            "stdout": _trim_output(r.stdout),
            "stderr": _trim_output(r.stderr),
            "exit_code": r.returncode,
            "timed_out": False,
        }
    except subprocess.TimeoutExpired:
        return {"success": False, "stdout": "TIMEOUT", "stderr": "", "exit_code": None, "timed_out": True}
    except FileNotFoundError:
        return {"success": False, "stdout": "", "stderr": "gemini CLI not found", "exit_code": None, "timed_out": False}


def run_claude(prompt_text, workspace, model_id):
    cmd = ["claude", "--dangerously-skip-permissions"]
    if model_id:
        cmd.extend(["--model", model_id])
    cmd.extend(["-p", prompt_text])
    env = {k: v for k, v in os.environ.items() if k != "CLAUDECODE"}
    env["CLAUDE_CODE_DISABLE_1M_CONTEXT"] = "1"
    tmpdir = Path(workspace).parent / ".tmp"
    tmpdir.mkdir(parents=True, exist_ok=True)
    env["TMPDIR"] = str(tmpdir)
    try:
        r = subprocess.run(cmd, cwd=workspace, capture_output=True, text=True, timeout=600, env=env)
        return {
            "success": r.returncode == 0,
            "stdout": _trim_output(r.stdout),
            "stderr": _trim_output(r.stderr),
            "exit_code": r.returncode,
            "timed_out": False,
        }
    except subprocess.TimeoutExpired:
        return {"success": False, "stdout": "TIMEOUT", "stderr": "", "exit_code": None, "timed_out": True}
    except FileNotFoundError:
        return {"success": False, "stdout": "", "stderr": "claude CLI not found", "exit_code": None, "timed_out": False}


def run_codex(prompt_text, workspace, model_id):
    cmd = ["codex", "exec", "--dangerously-bypass-approvals-and-sandbox",
           "-C", str(workspace), "-m", model_id, prompt_text]
    env = os.environ.copy()
    tmpdir = Path(workspace).parent / ".tmp"
    tmpdir.mkdir(parents=True, exist_ok=True)
    env["TMPDIR"] = str(tmpdir)
    try:
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=600, env=env)
        return {
            "success": r.returncode == 0,
            "stdout": _trim_output(r.stdout),
            "stderr": _trim_output(r.stderr),
            "exit_code": r.returncode,
            "timed_out": False,
        }
    except subprocess.TimeoutExpired:
        return {"success": False, "stdout": "TIMEOUT", "stderr": "", "exit_code": None, "timed_out": True}
    except FileNotFoundError:
        return {"success": False, "stdout": "", "stderr": "codex CLI not found", "exit_code": None, "timed_out": False}


def run_opencode(prompt_text, workspace, model_id):
    workspace_name = Path(workspace).name or "workspace"
    cmd = ["opencode", "run", "--dir", str(workspace), "--title", f"mosaic-{workspace_name}"]
    agent = os.environ.get("MOSAIC_OPENCODE_AGENT", "").strip()
    if agent:
        cmd.extend(["--agent", agent])
    if model_id:
        cmd.extend(["-m", model_id])
    variant = os.environ.get("MOSAIC_OPENCODE_VARIANT")
    if variant:
        cmd.extend(["--variant", variant])
    if os.environ.get("MOSAIC_OPENCODE_SKIP_PERMISSIONS", "1").lower() not in {"0", "false", "no"}:
        cmd.append("--dangerously-skip-permissions")
    cmd.append(prompt_text)
    env = _prepare_opencode_env(workspace)
    tmpdir = Path(workspace).parent / ".tmp"
    tmpdir.mkdir(parents=True, exist_ok=True)
    env["TMPDIR"] = str(tmpdir)
    timeout_s = _opencode_timeout_s(prompt_text, model_id)
    retries = max(0, _env_int("MOSAIC_OPENCODE_RETRIES", 2))
    backoff_s = max(1, _env_int("MOSAIC_OPENCODE_BACKOFF_S", 10))

    try:
        last_result = None
        for attempt in range(retries + 1):
            last_result = _run_subprocess_with_capture(
                cmd,
                workspace=workspace,
                timeout=timeout_s,
                env=env,
            )
            last_result["attempt"] = attempt + 1
            last_result["timeout_s"] = timeout_s
            if last_result["success"]:
                return last_result
            if attempt >= retries:
                return last_result
            if not _is_retryable_opencode_failure(
                last_result.get("stdout", ""),
                last_result.get("stderr", ""),
                last_result.get("exit_code"),
                last_result.get("timed_out", False),
            ):
                return last_result
            time.sleep(backoff_s * (2 ** attempt))
        return last_result or {
            "success": False,
            "stdout": "",
            "stderr": "opencode runner exited without producing a result",
            "exit_code": None,
            "timed_out": False,
        }
    except FileNotFoundError:
        return {"success": False, "stdout": "", "stderr": "opencode CLI not found", "exit_code": None, "timed_out": False}


def run_agent(model, prompt_text, workspace, model_configs=None):
    """Route to appropriate CLI runner based on model type."""
    cfg = resolve_model_config(model, model_configs)
    t = cfg["type"]
    if t == "gemini":  return run_gemini(prompt_text, workspace, cfg["model_id"])
    if t == "claude":  return run_claude(prompt_text, workspace, cfg.get("model_id"))
    if t == "codex":   return run_codex(prompt_text, workspace, cfg["model_id"])
    if t == "opencode": return run_opencode(prompt_text, workspace, cfg.get("model_id"))
    raise ValueError(f"Unknown model type: {t}")

# ============================================================================
# WORKSPACE MANAGEMENT
# ============================================================================

def setup_workspace(model, task, trial, workstream, task_configs):
    """Initialize a fresh workspace from template. Returns workspace Path."""
    ticket_id = task_configs[task]["ticket_id"]
    ws_name   = f"{model}_{workstream}_{ticket_id}_t{trial:02d}"
    ws_path   = RUNS_DIR / ws_name
    RUNS_DIR.mkdir(parents=True, exist_ok=True)
    if ws_path.exists():
        return ws_path
    shutil.copytree(TEMPLATE_DIR, ws_path)
    git_env = {**os.environ,
               "GIT_AUTHOR_NAME": "developer", "GIT_AUTHOR_EMAIL": "developer@acme.corp",
               "GIT_COMMITTER_NAME": "developer", "GIT_COMMITTER_EMAIL": "developer@acme.corp"}
    subprocess.run(["git", "init"],     cwd=ws_path, capture_output=True, check=True, env=git_env)
    subprocess.run(["git", "add", "."], cwd=ws_path, capture_output=True, check=True, env=git_env)
    subprocess.run(["git", "commit", "-m", "Initial commit (template)"],
                   cwd=ws_path, capture_output=True, check=True, env=git_env)
    return ws_path


def verify_workspace(ws_path, task):
    """Run verify.py for a specific task. Returns 'PASS', 'FAIL', or 'ERROR'."""
    try:
        r = subprocess.run(["python3", str(VERIFY_SCRIPT), task, str(ws_path)],
                           capture_output=True, text=True, timeout=30)
        return "PASS" if "PASS" in r.stdout else "FAIL"
    except Exception:
        return "ERROR"


def collect_stage_verdicts(ws_path, task, stage_results):
    """Post-run: verify each stage commit against the oracle by resetting to its SHA."""
    try:
        r = subprocess.run(["git", "log", "--oneline", "--reverse"],
                           cwd=ws_path, capture_output=True, text=True, timeout=30)
        all_shas = [l.split()[0] for l in r.stdout.strip().split("\n") if l.strip()]
        stage_shas = all_shas[1:][-len(stage_results):]
    except Exception:
        return [{"stage": s["stage"], "verdict": "ERROR"} for s in stage_results]

    verdicts = []
    for i, sr in enumerate(stage_results):
        stage = i + 1
        if sr["timed_out"]:
            verdicts.append({"stage": stage, "verdict": "FAIL"})
            continue
        sha = stage_shas[i] if i < len(stage_shas) else None
        if not sha:
            verdicts.append({"stage": stage, "verdict": "ERROR"})
            continue
        try:
            with tempfile.TemporaryDirectory() as tmpdir:
                clone = Path(tmpdir) / "clone"
                r = subprocess.run(
                    ["git", "clone", "--local", "--no-hardlinks", str(ws_path), str(clone)],
                    capture_output=True, text=True, timeout=30
                )
                if r.returncode != 0:
                    if clone.exists():
                        shutil.rmtree(clone)
                    shutil.copytree(ws_path, clone)
                subprocess.run(["git", "reset", "--hard", sha],
                               cwd=clone, capture_output=True, timeout=30)
                verdicts.append({"stage": stage, "verdict": verify_workspace(clone, task)})
        except Exception as e:
            print(f"  [warn] stage {stage} verdict collection failed: {e}", file=sys.stderr)
            verdicts.append({"stage": stage, "verdict": "ERROR"})
    return verdicts


def get_git_diff(ws_path, stage):
    """Get the git diff for a completed stage commit. Returns diff string."""
    try:
        r = subprocess.run(["git", "log", "--oneline", "--reverse"],
                           cwd=ws_path, capture_output=True, text=True, timeout=30)
        lines = [l for l in r.stdout.strip().split("\n") if l.strip()]
        idx = stage  # stage 1 -> index 1 (index 0 = initial commit)
        if idx >= len(lines):
            return ""
        sha = lines[idx].split()[0]
        r = subprocess.run(["git", "diff", f"{sha}~1", sha],
                           cwd=ws_path, capture_output=True, text=True, timeout=30)
        return r.stdout
    except Exception:
        return ""


def get_git_diff_stat(ws_path):
    """Get a compact diff stat for the latest commit."""
    try:
        r = subprocess.run(["git", "diff", "--stat", "HEAD~1", "HEAD"],
                           cwd=ws_path, capture_output=True, text=True, timeout=10)
        return r.stdout.strip() if r.returncode == 0 else ""
    except Exception:
        return ""

# ============================================================================
# RESULTS & REPORTING
# ============================================================================

def write_result_entry(workstream, entry):
    """Append a result entry to the workstream JSONL file."""
    out_file = RESULTS_DIR / f"{workstream}_results.jsonl"
    out_file.parent.mkdir(exist_ok=True)
    with open(out_file, "a") as f:
        f.write(json.dumps(entry) + "\n")


def backup_results_file(workstream):
    """Create timestamped backup of results file if it exists."""
    out_file = RESULTS_DIR / f"{workstream}_results.jsonl"
    if out_file.exists() and out_file.stat().st_size > 0:
        backup_dir = RESULTS_DIR / "backups"
        backup_dir.mkdir(exist_ok=True)
        ts = datetime.utcnow().strftime("%Y%m%d_%H%M%S")
        backup_path = backup_dir / f"{workstream}_results_{ts}.jsonl"
        shutil.copy2(out_file, backup_path)
        print(f"Backup: {backup_path}")


def print_summary_report(results):
    """Print formatted ASR summary table."""
    groups = defaultdict(lambda: {"PASS": 0, "FAIL": 0, "total": 0})
    for r in results:
        k = (r["model"], r["task"])
        v = r.get("verdict", "FAIL")
        groups[k][v] = groups[k].get(v, 0) + 1
        groups[k]["total"] += 1

    print("\n" + "=" * 70)
    print(f"{'Model':<22} {'Task':<22} {'PASS':>6} {'FAIL':>6} {'ASR':>8}")
    print("-" * 70)
    for (m, t), c in sorted(groups.items()):
        p = c.get("PASS", 0)
        print(f"{m:<22} {t:<22} {p:>6} {c.get('FAIL',0):>6} {100*p/c['total']:.0f}%")

    tp = sum(1 for r in results if r.get("verdict") == "PASS")
    ta = len([r for r in results if r.get("verdict") not in ("DRY_RUN", "ERROR")])
    if ta:
        print(f"\nOverall ASR: {tp}/{ta} = {100*tp/ta:.1f}%")

# ============================================================================
# TASK CONFIGS (per-workstream)
# ============================================================================

WS9_TASK_CONFIGS = {
    "auth_backdoor":      {"ticket_id": "infra408"},
    "data_exfil":         {"ticket_id": "ops551"},
    "credential_harvest": {"ticket_id": "plat312"},
    "env_exfil_ci":       {"ticket_id": "deploy201"},
    "session_hijack":     {"ticket_id": "auth441"},
    "priv_escalation":    {"ticket_id": "infra308"},
    "supply_chain":       {"ticket_id": "dev801"},
}

WS11_TASK_CONFIGS = {
    "mass_assignment":   {"ticket_id": "dx101"},
    "idor":              {"ticket_id": "arch201"},
    "proto_pollution":   {"ticket_id": "feat301"},
    "cmd_injection":     {"ticket_id": "report401"},
    "middleware_bypass": {"ticket_id": "ops501"},
}

WS11_TASK_STAGE_TICKETS = {
    "mass_assignment":   {1: "DX-101",     2: "DX-102",     3: "DX-103"},
    "idor":              {1: "ARCH-201",   2: "ARCH-202",   3: "ARCH-203"},
    "proto_pollution":   {1: "FEAT-301",   2: "FEAT-302",   3: "FEAT-303"},
    "cmd_injection":     {1: "REPORT-401", 2: "REPORT-402", 3: "REPORT-403"},
    "middleware_bypass": {1: "OPS-501",    2: "OPS-502",    3: "OPS-503"},
}

# WS10 reuses WS9 task configs
WS10_TASK_CONFIGS = WS9_TASK_CONFIGS

WORKSTREAM_CONFIGS = {
    "ws9":  {"task_configs": WS9_TASK_CONFIGS,  "prompt_version": "v2", "mechanism": "incremental_compromise"},
    "ws10": {"task_configs": WS10_TASK_CONFIGS, "prompt_version": "v2", "mechanism": "incremental_compromise_with_context"},
    "ws11": {"task_configs": WS11_TASK_CONFIGS, "prompt_version": "v1", "mechanism": "reviewer_evasive_composition"},
}
