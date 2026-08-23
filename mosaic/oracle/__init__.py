"""Package namespace for MOSAIC oracle helpers.

The old single-file ``mosaic/oracle.py`` exposed the legacy task verifier API.
After the rename to the ``mosaic.oracle`` package namespace, that implementation
now lives in ``mosaic.task_oracle``. Re-export it here so
``from mosaic.oracle import verify`` keeps working while this package owns the
new exploit-backed oracle namespace.
"""

from ..task_oracle import list_tasks, task_description, verify
from .evaluator import OracleEngine, OracleResult, OracleVerdict
from .exploit import ExploitResult, ExploitTest

__all__ = [
    "ExploitResult",
    "ExploitTest",
    "OracleEngine",
    "OracleResult",
    "OracleVerdict",
    "list_tasks",
    "task_description",
    "verify",
]
