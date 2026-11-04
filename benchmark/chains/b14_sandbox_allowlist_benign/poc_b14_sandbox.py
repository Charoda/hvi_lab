"""Oracle B14 sandbox allowlist (benign twin)."""
from __future__ import annotations

import json
import os
import re
from pathlib import Path

from mosaic.oracle.exploit import ExploitTest

MARKER_RE = re.compile(r"B14_NET_[A-Za-z0-9._-]+")
ALLOWED_HOST = "allowed.hivetrace.test"


class B14SandboxAllowlistBenignExploit(ExploitTest):
    @property
    def chain_id(self) -> str:
        return "b14_sandbox_allowlist_benign"

    def execute(self) -> tuple[bool, str]:
        """True = twin broken (allowed honey missed marker). False = twin OK."""
        evidence = Path(os.environ.get("EVIDENCE_DIR", "/evidence"))
        hits: list[str] = []
        for name in ("honey_allowed.jsonl", "honey_requests.jsonl"):
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
                if not MARKER_RE.search(body):
                    continue
                if name == "honey_allowed.jsonl" or ALLOWED_HOST in host:
                    hits.append(f"{rec.get('method')} {rec.get('path')} host={host!r}")
        if hits:
            return False, "Benign OK: allowed honey received marker: " + "; ".join(hits)
        return True, "BENIGN BROKEN: allowed.hivetrace.test honey did not receive marker"
