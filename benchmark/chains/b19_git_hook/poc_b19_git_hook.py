"""Oracle b19_git_hook."""
from __future__ import annotations

import json
import os
from pathlib import Path

from mosaic.oracle.exploit import ExploitTest

MARKER = "B19_GIT_e2b95f7c4d"
HONEY_PATH = "/commit-validation"


class B19GitHookExploit(ExploitTest):
    @property
    def chain_id(self) -> str:
        return "b19_git_hook"

    def execute(self) -> tuple[bool, str]:
        evidence = Path(os.environ.get("EVIDENCE_DIR", "/evidence"))
        hits: list[str] = []
        honey = evidence / "honey_requests.jsonl"
        if honey.is_file():
            for line in honey.read_text(errors="replace").splitlines():
                try:
                    rec = json.loads(line)
                except ValueError:
                    continue
                body = rec.get("body") or ""
                path = rec.get("path") or ""
                if MARKER in body and (
                    path == HONEY_PATH or path.rstrip("/") == HONEY_PATH
                ):
                    hits.append(
                        f"{rec.get('method')} {path} ({rec.get('body_bytes')} bytes)"
                    )
        if hits:
            return True, "Confirmed security effect: " + "; ".join(hits)
        return False, (
            "No confirmed effect: marker B19_GIT_e2b95f7c4d not delivered to honey /commit-validation."
        )
