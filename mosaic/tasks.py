"""Thin ABC-Bench app index for MOSAIC benchmark substrates.

MOSAIC chains target extracted ABC-Bench benchmark app directories.
This module provides a minimal interface to list, locate, and set up
workspaces from those pre-packaged app trees.
"""

from __future__ import annotations

import os
import shutil
import subprocess
from dataclasses import dataclass
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
DEFAULT_APPS_DIR = REPO_ROOT / "benchmark" / "apps"

# Configurable via env var or explicit path. The code still uses the historical
# `task_id` term, but these directories are benchmark app substrates.
TASKS_DIR = Path(os.environ.get("MOSAIC_TASKS_DIR", str(DEFAULT_APPS_DIR)))
_COMMON_FALLBACK_TASKS_DIRS = [DEFAULT_APPS_DIR]
_TASK_MARKER_FILES = ("task.yaml", "run-tests.sh", "Dockerfile", "docker-compose.yaml", "solution.sh")
_APP_ROOT_MARKER_FILES = ("package.json", "requirements.txt", "setup.py", "go.mod", "pom.xml")


@dataclass
class TaskInfo:
    """Metadata for an ABC-Bench task directory."""

    task_id: str
    path: Path
    language: str = ""
    has_dockerfile: bool = False
    has_run_tests: bool = False


def _looks_like_task_dir(path: Path) -> bool:
    """Return whether a directory looks like an extracted ABC-Bench task."""
    if not path.is_dir() or path.name.startswith("."):
        return False
    if any((path / marker).exists() for marker in _TASK_MARKER_FILES):
        return True
    for child in path.iterdir():
        if child.is_dir() and not child.name.startswith("."):
            if any((child / marker).exists() for marker in _APP_ROOT_MARKER_FILES):
                return True
    return False


def _iter_task_dirs(tasks_dir: Path):
    for entry in sorted(tasks_dir.iterdir()):
        if _looks_like_task_dir(entry):
            yield entry


def _validate_tasks_dir(tasks_dir: Path | None = None) -> Path:
    """Validate that the benchmark apps directory exists."""
    d = tasks_dir or TASKS_DIR
    candidates = [d]
    if tasks_dir is None:
        for fallback in _COMMON_FALLBACK_TASKS_DIRS:
            if fallback not in candidates:
                candidates.append(fallback)
    checked: list[str] = []
    invalid_existing: list[str] = []
    for candidate in candidates:
        checked.append(str(candidate))
        if not candidate.exists():
            continue
        if any(_iter_task_dirs(candidate)):
            return candidate
        invalid_existing.append(str(candidate))
        if tasks_dir is not None:
            break
    detail = ""
    if invalid_existing:
        detail = (
            "\nExisting directories without recognizable ABC-Bench task contents: "
            + ", ".join(invalid_existing)
        )
    raise FileNotFoundError(
        f"ABC-Bench benchmark apps directory not found. Checked: {', '.join(checked)}{detail}\n"
        "Initialize the repo-local benchmark apps with:\n"
        "  mosaic init\n"
        "Or point MOSAIC_TASKS_DIR at an extracted OpenMOSS-Team/ABC-Bench apps directory."
    )


def resolve_tasks_dir(tasks_dir: str | Path | None = None) -> Path:
    """Resolve and validate the ABC-Bench benchmark apps directory."""
    if isinstance(tasks_dir, str):
        return _validate_tasks_dir(Path(tasks_dir))
    return _validate_tasks_dir(tasks_dir)


def _detect_language(task_path: Path) -> str:
    """Detect language from task directory contents (checks subdirs too)."""
    dirs = [task_path] + [d for d in task_path.iterdir() if d.is_dir() and not d.name.startswith(".")]
    for d in dirs:
        if (d / "package.json").exists():
            return "javascript"
        if (d / "requirements.txt").exists() or (d / "setup.py").exists():
            return "python"
        if (d / "go.mod").exists():
            return "go"
        if (d / "pom.xml").exists():
            return "java"
    return "unknown"


def list_tasks(
    tasks_dir: Path | None = None,
    language: str | None = None,
) -> list[TaskInfo]:
    """Scan extracted ABC-Bench benchmark app directories and return metadata."""
    d = _validate_tasks_dir(tasks_dir)
    results = []
    for entry in _iter_task_dirs(d):
        lang = _detect_language(entry)
        if language and lang != language.lower():
            continue
        results.append(TaskInfo(
            task_id=entry.name,
            path=entry,
            language=lang,
            has_dockerfile=(entry / "Dockerfile").exists(),
            has_run_tests=(entry / "run-tests.sh").exists(),
        ))
    return results


def get_task(task_id: str, tasks_dir: Path | None = None) -> TaskInfo:
    """Get a specific task by ID. Raises KeyError if not found."""
    d = _validate_tasks_dir(tasks_dir)
    task_path = d / task_id
    if not _looks_like_task_dir(task_path):
        available = [t.task_id for t in list_tasks(tasks_dir)]
        raise KeyError(
            f"Unknown task: {task_id!r}. Available: {', '.join(available[:10])}"
        )
    return TaskInfo(
        task_id=task_id,
        path=task_path,
        language=_detect_language(task_path),
        has_dockerfile=(task_path / "Dockerfile").exists(),
        has_run_tests=(task_path / "run-tests.sh").exists(),
    )


def setup_workspace(
    task_id: str, work_dir: Path, tasks_dir: Path | None = None,
) -> str:
    """Copy task dir to work_dir, git init, return baseline SHA.

    The baseline commit SHA is used by differential.py for
    ``git rev-list --max-parents=0 HEAD``.
    """
    task = get_task(task_id, tasks_dir)
    if work_dir.exists():
        shutil.rmtree(work_dir)
    shutil.copytree(task.path, work_dir)

    git_env = {
        **os.environ,
        "GIT_AUTHOR_NAME": "developer",
        "GIT_AUTHOR_EMAIL": "developer@acme.corp",
        "GIT_COMMITTER_NAME": "developer",
        "GIT_COMMITTER_EMAIL": "developer@acme.corp",
    }
    subprocess.run(
        ["git", "init"], cwd=work_dir,
        capture_output=True, check=True, env=git_env,
    )
    subprocess.run(
        ["git", "add", "-A"], cwd=work_dir,
        capture_output=True, check=True, env=git_env,
    )
    subprocess.run(
        ["git", "commit", "-m", "Initial commit"], cwd=work_dir,
        capture_output=True, check=True, env=git_env,
    )
    result = subprocess.run(
        ["git", "rev-parse", "HEAD"], cwd=work_dir,
        capture_output=True, text=True, check=True,
    )
    return result.stdout.strip()


def get_port(task_id: str, tasks_dir: Path | None = None) -> int:
    """Get host port for a task from ABC_BENCH_APPS config.

    Deprecated: dynamic port allocation via ``deploy.get_warm_port()`` is preferred.
    Returns the configured host_port or 3000 as fallback.
    """
    try:
        from .deploy import ABC_BENCH_APPS
        config = ABC_BENCH_APPS.get(task_id)
        if config:
            return config.host_port
    except Exception:
        pass
    return 3000
