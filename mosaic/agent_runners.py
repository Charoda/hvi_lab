#!/usr/bin/env python3
"""CLI wrappers for the agent backends MOSAIC drives.

Provides ``run_agent(model, prompt_text, workspace, ...)`` which dispatches to
``run_gemini`` / ``run_claude`` / ``run_codex`` / ``run_opencode`` based on the
model alias resolved against ``MODEL_CONFIGS``. Each subprocess runner handles
its own session resumption, stdin streaming for large prompts, and timeout
heuristics.
"""

import json
import os
import shutil
import signal
import subprocess
import sys
import tempfile
import time
from pathlib import Path
from typing import Optional

# ============================================================================
# MODEL CONFIGURATION
# ============================================================================

MODEL_CONFIGS = {
    "gemini-flash":     {"type": "gemini", "model_id": "gemini-3-flash-preview"},
    "gemini-pro":       {"type": "gemini", "model_id": "gemini-3.1-pro-preview"},
    "gemini-2.5-pro":   {"type": "gemini", "model_id": "gemini-2.5-pro"},
    "gemini-2.5-flash": {"type": "gemini", "model_id": "gemini-2.5-flash"},
    "claude-sonnet-46": {"type": "claude", "model_id": "claude-sonnet-4-6"},
    "claude-opus":      {"type": "claude", "model_id": "claude-opus-4-6"},
    "codex":            {"type": "codex",  "model_id": "gpt-5.3-codex"},
    "codex54":          {"type": "codex",  "model_id": "gpt-5.4"},
    "opencode":         {"type": "opencode", "model_id": None},
    # Stable aliases for the OpenCode-routed models used in the paper.
    # Each requires the matching opencode provider to be authenticated:
    #   google-vertex/* — set GOOGLE_GENAI_USE_VERTEXAI=true, GOOGLE_CLOUD_PROJECT, VERTEX_LOCATION
    #   opencode-go/*   — `opencode auth login` once on the host (auth.json is migrated into the run)
    "kimi-k26":         {"type": "opencode", "model_id": "opencode-go/kimi-k2.6"},
    "minimax":          {"type": "opencode", "model_id": "opencode-go/minimax-m2.7"},
    "glm-5":            {"type": "opencode", "model_id": "google-vertex/zai-org/glm-5-maas"},
    "gemini-flash-vertex": {"type": "opencode", "model_id": "google-vertex/gemini-3-flash-preview"},
    "gemini-pro-vertex":   {"type": "opencode", "model_id": "google-vertex/gemini-3.1-pro-preview"},
}

ALL_MODELS = list(MODEL_CONFIGS.keys())


def _trim_output(text, limit=6000):
    """Keep first and last portions of output to preserve both verdict and errors."""
    if not text:
        return ""
    if len(text) <= limit:
        return text
    half = limit // 2
    return text[:half] + "\n...[trimmed]...\n" + text[-half:]


def _signal_name_for_exit(exit_code: int | None) -> Optional[str]:
    """Map negative subprocess return codes to POSIX signal names."""
    if exit_code is None or exit_code >= 0:
        return None
    try:
        return signal.Signals(-exit_code).name
    except ValueError:
        return None


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


def _run_subprocess_with_capture(cmd, *, workspace, timeout, env, stdin_text=None):
    try:
        result = subprocess.run(
            cmd,
            cwd=workspace,
            capture_output=True,
            text=True,
            timeout=timeout,
            env=env,
            input=stdin_text,
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
    - opencode:<provider/model>@<agent>   (specifies an OpenCode agent to use)
    """
    configs = model_configs or MODEL_CONFIGS
    if model in configs:
        return configs[model]
    if model.startswith("opencode:"):
        model_id = model.split(":", 1)[1].strip()
        if not model_id:
            raise ValueError("opencode model alias requires a provider/model after 'opencode:'")
        agent = None
        if "@" in model_id:
            model_id, agent = model_id.rsplit("@", 1)
        cfg = {"type": "opencode", "model_id": model_id}
        if agent:
            cfg["agent"] = agent
        return cfg
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
    for gcp_var in ("GOOGLE_CLOUD_PROJECT", "VERTEX_LOCATION", "GOOGLE_APPLICATION_CREDENTIALS"):
        val = os.environ.get(gcp_var)
        if val:
            env[gcp_var] = val
    env.setdefault("VERTEX_LOCATION", "global")
    # Point OpenCode at the MOSAIC .opencode dir for custom agents (e.g. reviewer)
    mosaic_opencode_dir = Path(__file__).resolve().parent.parent / ".opencode"
    if mosaic_opencode_dir.is_dir():
        env.setdefault("OPENCODE_CONFIG_DIR", str(mosaic_opencode_dir))
    return env

# ============================================================================
# CLI RUNNERS
# ============================================================================

def _run_cli_agent(cmd, *, cli_name, workspace, env, timeout_s, cwd=None, stdin_text=None):
    """Shared runner for simple CLI agents (gemini, claude, codex)."""
    tmpdir = Path(workspace).parent / ".tmp"
    tmpdir.mkdir(parents=True, exist_ok=True)
    env["TMPDIR"] = str(tmpdir)
    try:
        r = subprocess.run(
            cmd,
            cwd=cwd or workspace,
            capture_output=True,
            text=True,
            timeout=timeout_s or 600,
            env=env,
            input=stdin_text,
        )
        result = {
            "success": r.returncode == 0,
            "stdout": _trim_output(r.stdout),
            "stderr": _trim_output(r.stderr),
            "exit_code": r.returncode,
            "signal_name": _signal_name_for_exit(r.returncode),
            "timed_out": False,
        }
        # Extract session_id from JSON output for --resume support
        result["session_id"] = _extract_session_id(r.stdout, cli_name)
        return result
    except subprocess.TimeoutExpired:
        return {
            "success": False,
            "stdout": "TIMEOUT",
            "stderr": "",
            "exit_code": None,
            "signal_name": None,
            "timed_out": True,
            "session_id": None,
        }
    except FileNotFoundError:
        return {
            "success": False,
            "stdout": "",
            "stderr": f"{cli_name} CLI not found",
            "exit_code": None,
            "signal_name": None,
            "timed_out": False,
            "session_id": None,
        }


def extract_agent_metadata(stdout: str) -> dict:
    """Extract useful metadata from agent JSON output (cost, turns, usage)."""
    meta: dict = {}
    if not stdout:
        return meta
    try:
        for line in reversed(stdout.strip().splitlines()):
            line = line.strip()
            if line.startswith("{"):
                data = json.loads(line)
                for key in ("total_cost_usd", "num_turns", "duration_ms", "duration_api_ms", "usage", "stop_reason"):
                    if key in data:
                        meta[key] = data[key]
                break
    except (json.JSONDecodeError, KeyError):
        pass
    return meta


def _extract_session_id(stdout: str, cli_name: str) -> Optional[str]:
    """Extract session_id from CLI JSON output.

    Handles both formats:
    - --output-format json: single JSON object with session_id at top level
    - --output-format stream-json / --verbose: JSON array or newline-delimited events
    """
    if not stdout:
        return None
    try:
        stripped = stdout.strip()
        # Handle JSON array (verbose mode): parse last element
        if stripped.startswith("["):
            arr = json.loads(stripped)
            for item in reversed(arr):
                if isinstance(item, dict) and "session_id" in item:
                    return str(item["session_id"])
            return None
        # Handle newline-delimited JSON (Claude json mode, Codex --json)
        for line in stripped.splitlines():
            line = line.strip()
            if not line.startswith("{"):
                continue
            try:
                data = json.loads(line)
            except json.JSONDecodeError:
                continue
            # Claude Code: session_id in result object
            if "session_id" in data:
                return str(data["session_id"])
            if "result" in data and isinstance(data["result"], dict):
                if "session_id" in data["result"]:
                    return str(data["result"]["session_id"])
            # Codex: thread_id in thread.started event
            if data.get("type") == "thread.started" and "thread_id" in data:
                return str(data["thread_id"])
    except (json.JSONDecodeError, KeyError):
        pass
    return None


def run_gemini(prompt_text, workspace, model_id, timeout_s=None, session_id=None, verbose=False):
    cmd = ["gemini", "--yolo", "-m", model_id]
    if verbose:
        cmd.extend(["-o", "stream-json"])
    else:
        cmd.extend(["-o", "json"])
    use_stdin = len(prompt_text) > 100_000
    if not use_stdin:
        cmd.extend(["-p", prompt_text])
    env = os.environ.copy()
    env["GEMINI_CLI_TRUST_WORKSPACE"] = "true"
    return _run_cli_agent(cmd, cli_name="gemini", workspace=workspace,
                          env=env, timeout_s=timeout_s or 600,
                          stdin_text=prompt_text if use_stdin else None)


def run_claude(prompt_text, workspace, model_id, timeout_s=None, session_id=None, verbose=False):
    cmd = ["claude", "--dangerously-skip-permissions"]
    if model_id:
        cmd.extend(["--model", model_id])
    if session_id:
        cmd.extend(["--resume", session_id])
    use_stdin = len(prompt_text) > 100_000
    if use_stdin:
        cmd.append("-p")
    else:
        cmd.extend(["-p", prompt_text])
    if verbose:
        cmd.extend(["--output-format", "stream-json", "--verbose"])
    else:
        cmd.extend(["--output-format", "json"])
    env = {k: v for k, v in os.environ.items() if k != "CLAUDECODE"}
    env["CLAUDE_CODE_DISABLE_1M_CONTEXT"] = "1"
    return _run_cli_agent(cmd, cli_name="claude", workspace=workspace,
                          env=env, timeout_s=timeout_s,
                          stdin_text=prompt_text if use_stdin else None)


def run_codex(prompt_text, workspace, model_id, timeout_s=None, session_id=None, verbose=False):
    if session_id:
        cmd = [
            "codex", "exec", "resume",
            "--dangerously-bypass-approvals-and-sandbox",
            "-m", model_id,
            "--json",
            session_id,
            prompt_text,
        ]
        cwd = workspace
    else:
        cmd = [
            "codex", "exec",
            "--dangerously-bypass-approvals-and-sandbox",
            "-C", str(workspace),
            "-m", model_id,
            "--json",
        ]
        # Pass prompt via stdin to avoid "Argument list too long" on large diffs
        use_stdin = len(prompt_text) > 100_000
        if not use_stdin:
            cmd.append(prompt_text)
        cwd = None
    return _run_cli_agent(cmd, cli_name="codex", workspace=workspace,
                          env=os.environ.copy(), timeout_s=timeout_s, cwd=cwd,
                          stdin_text=prompt_text if not session_id and use_stdin else None)


def run_opencode(prompt_text, workspace, model_id, timeout_s=None, session_id=None, verbose=False, agent=None):
    workspace_name = Path(workspace).name or "workspace"
    cmd = ["opencode", "run", "--dir", str(workspace), "--title", f"mosaic-{workspace_name}"]
    if session_id:
        # Continue previous session — agent keeps full conversation context
        cmd.extend(["--session", session_id])
    agent = agent or os.environ.get("MOSAIC_OPENCODE_AGENT", "").strip()
    if agent:
        cmd.extend(["--agent", agent])
    if model_id:
        cmd.extend(["-m", model_id])
    variant = os.environ.get("MOSAIC_OPENCODE_VARIANT")
    if variant:
        cmd.extend(["--variant", variant])
    if os.environ.get("MOSAIC_OPENCODE_SKIP_PERMISSIONS", "1").lower() not in {"0", "false", "no"}:
        cmd.append("--dangerously-skip-permissions")
    if verbose:
        cmd.extend(["--format", "json", "--print-logs", "--log-level", "DEBUG"])
    use_stdin = len(prompt_text) > 100_000
    if not use_stdin:
        cmd.append(prompt_text)
    env = _prepare_opencode_env(workspace)
    tmpdir = Path(workspace).parent / ".tmp"
    tmpdir.mkdir(parents=True, exist_ok=True)
    env["TMPDIR"] = str(tmpdir)
    timeout_s = timeout_s or _opencode_timeout_s(prompt_text, model_id)
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
                stdin_text=prompt_text if use_stdin else None,
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


def run_agent(model, prompt_text, workspace, model_configs=None, timeout_s=None, session_id=None, verbose=False):
    """Route to appropriate CLI runner based on model type.

    If ``session_id`` is provided, agents that support ``--resume`` (Claude,
    Codex) will continue the previous conversation instead of starting fresh.
    If ``verbose`` is True, agents emit structured execution logs (tool calls,
    reasoning, cost) — Claude uses --verbose, Codex uses --json, OpenCode
    uses --format json + --print-logs.
    """
    cfg = resolve_model_config(model, model_configs)
    t = cfg["type"]
    if t == "gemini":  return run_gemini(prompt_text, workspace, cfg["model_id"], timeout_s=timeout_s, session_id=session_id, verbose=verbose)
    if t == "claude":  return run_claude(prompt_text, workspace, cfg.get("model_id"), timeout_s=timeout_s, session_id=session_id, verbose=verbose)
    if t == "codex":   return run_codex(prompt_text, workspace, cfg["model_id"], timeout_s=timeout_s, session_id=session_id, verbose=verbose)
    if t == "opencode": return run_opencode(prompt_text, workspace, cfg.get("model_id"), timeout_s=timeout_s, session_id=session_id, verbose=verbose, agent=cfg.get("agent"))
    raise ValueError(f"Unknown model type: {t}")
