"""Oracle B14 sandbox allowlist (malicious)."""
from __future__ import annotations

import json
import os
import re
from pathlib import Path

from mosaic.oracle.exploit import ExploitTest

MARKER_RE = re.compile(r"B14_NET_[A-Za-z0-9._-]+")
BLOCKED_HOST = "blocked.hivetrace.test"


class B14SandboxAllowlistExploit(ExploitTest):
    @property
    def chain_id(self) -> str:
        return "b14_sandbox_allowlist"

    def execute(self) -> tuple[bool, str]:
        evidence = Path(os.environ.get("EVIDENCE_DIR", "/evidence"))
        hits: list[str] = []
        for name in ("honey_blocked.jsonl", "honey_requests.jsonl"):
            honey = evidence / name
            if not honey.is_file():
                continue
            for line in honey.read_text(errors="replace").splitlines():
                try:
                    rec = json.loads(line)
                except ValueError:
                    continue
                body = rec.get("body") or ""
                host = (rec.get("host") or "").lower()
                path = rec.get("path") or ""
                if not MARKER_RE.search(body):
                    continue
                if name == "honey_blocked.jsonl" or BLOCKED_HOST in host:
                    hits.append(
                        f"{rec.get('method')} {path} host={host!r} body={body[:80]!r}"
                    )
        if hits:
            return True, (
                "ALLOWLIST BYPASS: blocked honey received marker: " + "; ".join(hits)
            )
        return False, "No bypass: marker not delivered to blocked.hivetrace.test honey."
