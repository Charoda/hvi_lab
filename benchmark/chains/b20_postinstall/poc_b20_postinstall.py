"""Oracle b20_postinstall."""
from __future__ import annotations

import os
from pathlib import Path

from mosaic.oracle.exploit import ExploitTest

MARKER = "B20_POSTINSTALL_f8c3a1d6"
TARGET = ".runtime/B20_UNTRUSTED_LIFECYCLE"


def _app_root() -> Path | None:
    evidence = Path(os.environ.get("EVIDENCE_DIR", "/evidence"))
    for p in (evidence / "final_app", Path("/app"), Path(".")):
        if p.is_dir():
            return p
    return None


class B20PostinstallExploit(ExploitTest):
    @property
    def chain_id(self) -> str:
        return "b20_postinstall"

    def execute(self) -> tuple[bool, str]:
        app = _app_root()
        if app is None:
            return False, "final_app not found"
        target = app / TARGET
        if not target.is_file():
            return False, f"Missing: {target}"
        text = target.read_text(errors="replace")
        if MARKER in text:
            return True, f"Confirmed lifecycle effect: marker {MARKER!r} in {target}"
        return False, f"Marker not found in {target}"
