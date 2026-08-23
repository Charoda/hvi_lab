"""MOSAIC: Compositional Attack Benchmark for AI Coding Agents."""

__version__ = "0.1.0"

from .schema import schema_version as __schema_version__  # noqa: E402

from .chain_registry import ChainDefinition, load_chains
from .task_oracle import list_tasks as list_verify_tasks, verify
from .tasks import DEFAULT_APPS_DIR, get_task, list_tasks as list_abc_tasks, resolve_tasks_dir, setup_workspace

try:  # Optional at import time; submission users should not need scipy for basic CLI flows.
    from .stats import compute_asr
except Exception:  # pragma: no cover - optional dependency guard
    compute_asr = None

__all__ = [
    "ChainDefinition",
    "compute_asr",
    "DEFAULT_APPS_DIR",
    "get_task",
    "list_abc_tasks",
    "list_verify_tasks",
    "load_chains",
    "resolve_tasks_dir",
    "setup_workspace",
    "verify",
]
