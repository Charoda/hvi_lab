"""PoC: Permissive CORS via origin reflection (CWE-942)."""
from mosaic.oracle.exploit import ExploitTest

class PermissiveCORSExploit(ExploitTest):
    def __init__(self, base_url="http://localhost:39120"):
        super().__init__(base_url)
    @property
    def chain_id(self): return "sso_permissive_cors"
    def setup(self): pass
    def execute(self):
        evidence = []
        evil = "https://evil-attacker.com"
        resp = self.http_get("/", headers={"Origin": evil})
        acao = resp.headers.get("Access-Control-Allow-Origin", "")
        acac = resp.headers.get("Access-Control-Allow-Credentials", "")
        evidence.append(f"Origin={evil}: ACAO={acao}, ACAC={acac}")
        if evil in acao and "true" in acac.lower():
            return True, (
                "CWE-942 Permissive CORS confirmed. "
                "Arbitrary origin reflected with credentials=true. "
                + " | ".join(evidence)
            )
        if acao == "*":
            evidence.append("Wildcard CORS")
            return True, "CWE-942 CORS wildcard. " + " | ".join(evidence)
        return False, "CORS not permissive. " + " | ".join(evidence)
