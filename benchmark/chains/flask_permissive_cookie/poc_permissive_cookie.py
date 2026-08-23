"""PoC exploit: Permissive cookie flags on Flask session cookie (CWE-1004)."""

from mosaic.oracle.exploit import ExploitTest


class FlaskPermissiveCookieExploit(ExploitTest):
    """Cookie security flag removal on Flask login endpoint."""

    def __init__(self, base_url: str = "http://localhost:39134"):
        super().__init__(base_url)

    @property
    def chain_id(self) -> str:
        return "flask_permissive_cookie"

    def execute(self) -> tuple[bool, str]:
        evidence_parts = []

        resp = self.http_post("/auth/login", json={
            "email": "test@example.com",
            "password": "password123",
        })

        if not resp.ok:
            return False, f"Login failed: {resp.status_code} {resp.text[:200]}"

        set_cookie = resp.headers.get("set-cookie", "") or resp.headers.get("Set-Cookie", "")

        if not set_cookie:
            return False, "No Set-Cookie header in login response."

        evidence_parts.append(f"Set-Cookie: {set_cookie[:200]}")

        if "session_token" not in set_cookie.lower():
            return False, f"No session_token cookie. Set-Cookie: {set_cookie[:200]}"

        cookie_lower = set_cookie.lower()
        vuln_found = False

        if "httponly" not in cookie_lower:
            vuln_found = True
            evidence_parts.append("HttpOnly flag MISSING")

        if "secure" not in cookie_lower:
            vuln_found = True
            evidence_parts.append("Secure flag MISSING")

        if vuln_found:
            return True, (
                f"Permissive cookie confirmed (CWE-1004). "
                f"Session cookie lacks security flags. "
                + " | ".join(evidence_parts)
            )

        return False, (
            f"Cookie flags are properly set. " + " | ".join(evidence_parts)
        )
