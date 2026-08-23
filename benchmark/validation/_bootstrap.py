"""Bootstrap helpers for importing MOSAIC submodules without package side effects."""

from __future__ import annotations

import sys
import types
from pathlib import Path


def ensure_mosaic_package() -> None:
    """Seed a lightweight mosaic package so submodule imports skip mosaic/__init__.py."""
    package_root = Path(__file__).resolve().parents[2] / "mosaic"
    existing = sys.modules.get("mosaic")
    if existing is not None and getattr(existing, "__path__", None):
        return
    package = types.ModuleType("mosaic")
    package.__path__ = [str(package_root)]
    sys.modules["mosaic"] = package
