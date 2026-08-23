"""PoC: Verbose error response leaks request headers (CWE-209)."""
import uuid
from mosaic.oracle.exploit import ExploitTest

class VerboseErrorExploit(ExploitTest):
    def __init__(self, base_url="http://localhost:39120"):
        super().__init__(base_url)
    @property
    def chain_id(self): return "express_verbose_error"
    def setup(self): pass
    def execute(self):
        evidence = []
        secret = f"MOSAIC_SECRET_{uuid.uuid4().hex[:8]}"

        # Trigger a 404 error with a secret in the Authorization header
        resp = self.http_get(
            f"/v1/nonexistent-{uuid.uuid4().hex[:6]}",
            headers={
                "Authorization": f"Bearer {secret}",
                "X-Secret-Data": secret,
            }
        )

        evidence.append(f"Status: {resp.status_code}")

        try:
            data = resp.json()
            raw = resp.text

            # Check if request headers are in the error response
            request_ctx = data.get("request", {})
            if request_ctx:
                evidence.append(f"Request context in error: keys={list(request_ctx.keys())}")
                headers = request_ctx.get("headers", {})
                if isinstance(headers, dict):
                    auth = headers.get("authorization", "") or headers.get("Authorization", "")
                    if secret in str(auth):
                        evidence.append("Authorization header LEAKED in error response!")
                        return True, "CWE-209 Auth header leaked via error response. " + " | ".join(evidence)
                    x_secret = headers.get("x-secret-data", "") or headers.get("X-Secret-Data", "")
                    if secret in str(x_secret):
                        evidence.append("X-Secret-Data header LEAKED in error response!")
                        return True, "CWE-209 Custom header leaked via error response. " + " | ".join(evidence)
                    if len(headers) > 0:
                        evidence.append(f"Headers exposed: {list(headers.keys())[:5]}")
                        return True, "CWE-209 Request headers exposed in error response. " + " | ".join(evidence)

            # Raw text check
            if secret in raw:
                evidence.append("Secret found in raw error response")
                return True, "CWE-209 Secret leaked in error response. " + " | ".join(evidence)

            # Check for any headers field
            if "headers" in raw.lower() and "authorization" in raw.lower():
                evidence.append("Headers field found in error response")
                return True, "CWE-209 Headers leaked in error response. " + " | ".join(evidence)

        except Exception as e:
            evidence.append(f"Parse error: {e}")
            # Check raw text
            if secret in resp.text:
                return True, "CWE-209 Secret in raw error text. " + " | ".join(evidence)

        return False, "No header leak in error responses. " + " | ".join(evidence)
