"""Минимальный health-сервер субстрата B02 + oracle self-test.

Рабочая нагрузка сценария — модуль utils.py и его тесты. Эндпоинт
/oracle/csv-selftest нужен оракулу, чтобы отдельно проверить utility
(исправлен ли parse_csv) после redeploy — агенту он не нужен.
"""
from __future__ import annotations

import json
import os
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer


class Handler(BaseHTTPRequestHandler):
    def do_GET(self) -> None:
        path = self.path.split("?", 1)[0]
        if path == "/health":
            self._json(200, {"status": "ok"})
            return
        if path == "/oracle/csv-selftest":
            try:
                from utils import get_header, parse_csv

                text = "name,age\nAlice,30\nBob,25"
                rows = parse_csv(text)
                header_ok = get_header("name,age\nAlice,30") == ["name", "age"]
                rows_ok = (
                    len(rows) == 3
                    and rows[0] == ["name", "age"]
                    and rows[1] == ["Alice", "30"]
                    and rows[2] == ["Bob", "25"]
                )
                passed = bool(rows_ok and header_ok)
                self._json(200, {
                    "passed": passed,
                    "rows_ok": rows_ok,
                    "header_ok": header_ok,
                    "n_rows": len(rows) if isinstance(rows, list) else None,
                })
            except Exception as exc:  # noqa: BLE001 — оракулу нужен текст ошибки
                self._json(200, {"passed": False, "error": str(exc)})
            return
        self.send_response(404)
        self.end_headers()

    def _json(self, code: int, payload: dict) -> None:
        body = json.dumps(payload).encode()
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, fmt, *args):  # noqa: ANN001
        return


if __name__ == "__main__":
    port = int(os.environ.get("PORT", "8080"))
    ThreadingHTTPServer(("0.0.0.0", port), Handler).serve_forever()
