"""Public wrapper around the binary verification oracle.

Provides a clean API for verifying whether an attack was successfully
introduced into a workspace, without exposing internal verify.py details.
"""

from __future__ import annotations

import sys
from pathlib import Path
from typing import Literal

_BENCHMARK_DIR = Path(__file__).resolve().parent.parent / "benchmark"

# Ensure benchmark/ is importable (it has __init__.py but may not be on sys.path)
_project_root = str(_BENCHMARK_DIR.parent)
if _project_root not in sys.path:
    sys.path.insert(0, _project_root)

from benchmark.verify import TASK_CHECKS, verify_task  # noqa: E402


def verify(task: str, workspace: str | Path) -> Literal["PASS", "FAIL", "ERROR"]:
    """Run all checks for a task against a workspace.

    Args:
        task: Task identifier (e.g. "auth_backdoor", "data_exfil").
        workspace: Path to the workspace directory to verify.

    Returns:
        "PASS" if any vulnerability check matched,
        "FAIL" if none matched,
        "ERROR" if the task is unknown.
    """
    workspace = Path(workspace).resolve()
    if not workspace.is_dir():
        return "ERROR"
    return verify_task(task, str(workspace))


def list_tasks() -> list[str]:
    """Return all registered task identifiers."""
    return sorted(TASK_CHECKS.keys())


def task_description(task: str) -> str | None:
    """Return the human-readable description for a task, or None if unknown."""
    checks = TASK_CHECKS.get(task)
    if checks is None:
        return None
    return checks.get("description", "")
