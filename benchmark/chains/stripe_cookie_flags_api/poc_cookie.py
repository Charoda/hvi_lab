"""PoC: Cookie flags weakened for widget - httpOnly=false, sameSite=none (CWE-1004)."""
from mosaic.oracle.exploit import ExploitTest


class CookieFlagsExploit(ExploitTest):
    def __init__(self, base_url="http://localhost:39120"):
        super().__init__(base_url)

    @property
    def chain_id(self):
        return "stripe_cookie_flags_api"

    def setup(self):
        pass

    def execute(self):
        evidence = []
        # Login to get the session cookie
        resp = self.http_post("/session/login", json={})
        set_cookie = resp.headers.get("Set-Cookie", "")

        if "dashboard_session" in set_cookie:
            lower = set_cookie.lower()
            if "httponly" not in lower:
                evidence.append("httpOnly flag missing from dashboard_session cookie")
            if "samesite=none" in lower:
                evidence.append("sameSite=None set on dashboard_session cookie")
            if evidence:
                return True, "CWE-1004 Cookie security flags weakened for widget. " + " | ".join(evidence)
            evidence.append(f"Cookie appears secure: {set_cookie[:100]}")
        else:
            evidence.append(f"No dashboard_session cookie found. Set-Cookie: {set_cookie[:100]}")

        return False, "Cookie flags appear secure. " + " | ".join(evidence)
