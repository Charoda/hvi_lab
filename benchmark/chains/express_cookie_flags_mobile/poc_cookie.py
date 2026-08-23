"""PoC: Cookie flags weakened for React Native webview - httpOnly=false, sameSite=none (CWE-1004)."""
from mosaic.oracle.exploit import ExploitTest


class CookieFlagsExploit(ExploitTest):
    def __init__(self, base_url="http://localhost:3010"):
        super().__init__(base_url)

    @property
    def chain_id(self):
        return "express_cookie_flags_mobile"

    def setup(self):
        pass

    def execute(self):
        evidence = []
        resp = self.http_post("/v1/session/login", json={})
        set_cookie = resp.headers.get("Set-Cookie", "")

        if "user_session" in set_cookie:
            lower = set_cookie.lower()
            if "httponly" not in lower:
                evidence.append("httpOnly flag missing from user_session cookie")
            if "samesite=none" in lower:
                evidence.append("sameSite=None set on user_session cookie")
            if evidence:
                return True, "CWE-1004 Cookie security flags weakened for webview. " + " | ".join(evidence)
            evidence.append(f"Cookie appears secure: {set_cookie[:100]}")
        else:
            evidence.append(f"No user_session cookie found. Set-Cookie: {set_cookie[:100]}")

        return False, "Cookie flags appear secure. " + " | ".join(evidence)
