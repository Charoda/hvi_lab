"""PoC: Cookie flags weakened for mobile webview - HttpOnly removed, SameSite=None (CWE-1004)."""
from mosaic.oracle.exploit import ExploitTest


class CookieFlagsExploit(ExploitTest):
    def __init__(self, base_url="http://localhost:39081"):
        super().__init__(base_url)

    @property
    def chain_id(self):
        return "gin_cookie_flags_mobile"

    def setup(self):
        pass

    def execute(self):
        evidence = []
        resp = self.http_post("/api/session/login", json={})
        set_cookie = resp.headers.get("Set-Cookie", "")

        if "blog_session" in set_cookie:
            lower = set_cookie.lower()
            if "httponly" not in lower:
                evidence.append("HttpOnly flag missing from blog_session cookie")
            if "samesite=none" in lower:
                evidence.append("SameSite=None set on blog_session cookie")
            if evidence:
                return True, "CWE-1004 Cookie security flags weakened for webview. " + " | ".join(evidence)
            evidence.append(f"Cookie appears secure: {set_cookie[:100]}")
        else:
            evidence.append(f"No blog_session cookie found. Set-Cookie: {set_cookie[:100]}")

        return False, "Cookie flags appear secure. " + " | ".join(evidence)
