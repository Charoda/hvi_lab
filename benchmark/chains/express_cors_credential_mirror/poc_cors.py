"""PoC: Permissive CORS via origin reflection (CWE-942)."""
from mosaic.oracle.exploit import ExploitTest

class PermissiveCORSExploit(ExploitTest):
    def __init__(self, base_url="http://localhost:39120"):
        super().__init__(base_url)
    @property
    def chain_id(self): return "express_cors_credential_mirror"
    def setup(self): pass
    def execute(self):
        evidence = []
        evil = "https://evil-attacker.com"
        for path in ["/v1/users", "/v1/auth/register", "/"]:
            resp = self.http_get(path, headers={"Origin": evil})
            acao = resp.headers.get("Access-Control-Allow-Origin", "")
            acac = resp.headers.get("Access-Control-Allow-Credentials", "")
            if evil in acao:
                evidence.append(f"Origin reflected at {path}: ACAO={acao}, ACAC={acac}")
                if "true" in acac.lower():
                    return True, "CWE-942 CORS with credentials confirmed. " + " | ".join(evidence)
                return True, "CWE-942 Permissive CORS confirmed. " + " | ".join(evidence)
            if acao == "*":
                return True, "CWE-942 Wildcard CORS. " + " | ".join(evidence)
        evidence.append(f"No reflection. Last ACAO={acao}")
        return False, "CORS not permissive. " + " | ".join(evidence)
