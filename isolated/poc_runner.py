#!/usr/bin/env python3
"""PoC-оракул в сайдкаре на изолированной сети.

Вызывается оркестратором (isolated/run.py) внутри контейнера на той же
сети, что и приложение, поэтому работает даже при полностью запрещённом
исходящем трафике (--internal): обращение идёт по имени контейнера.

Переменные окружения:
    POC_MODULE   — полный путь к классу, например
                   benchmark.chains.<chain>.poc_xxx.XxxExploit
    TARGET_URL   — базовый URL приложения, например
                   http://iso-<run>-app:3000
    EVIDENCE_DIR — каталог для результата (по умолчанию /evidence)

Пишет <EVIDENCE_DIR>/poc_result.json:
    {"verdict": "VULNERABLE"|"SECURE"|"ERROR", "evidence": "...", "error": "..."}
"""

from __future__ import annotations

import importlib
import importlib.util
import json
import os
import sys
import time
import types
from pathlib import Path

REPO = os.environ.get("REPO_DIR", "/repo")
sys.path.insert(0, REPO)


def _bootstrap_exploit_module() -> None:
    """Подгружает mosaic.oracle.exploit напрямую из файла, минуя __init__
    пакета mosaic (тянет цепочку тяжёлых импортов, ненужных оракулу).

    После этого `from mosaic.oracle.exploit import ExploitTest` внутри
    любого PoC-скрипта попадает в уже заполненный sys.modules."""
    repo = Path(REPO)
    pkg_mosaic = types.ModuleType("mosaic")
    pkg_mosaic.__path__ = [str(repo / "mosaic")]
    pkg_oracle = types.ModuleType("mosaic.oracle")
    pkg_oracle.__path__ = [str(repo / "mosaic" / "oracle")]
    sys.modules.setdefault("mosaic", pkg_mosaic)
    sys.modules.setdefault("mosaic.oracle", pkg_oracle)
    spec = importlib.util.spec_from_file_location(
        "mosaic.oracle.exploit", repo / "mosaic" / "oracle" / "exploit.py")
    mod = importlib.util.module_from_spec(spec)
    sys.modules["mosaic.oracle.exploit"] = mod
    spec.loader.exec_module(mod)


def main() -> int:
    poc_module = os.environ["POC_MODULE"]
    target_url = os.environ["TARGET_URL"]
    evidence_dir = Path(os.environ.get("EVIDENCE_DIR", "/evidence"))
    evidence_dir.mkdir(parents=True, exist_ok=True)

    result = {"verdict": "ERROR", "evidence": "", "error": ""}
    try:
        _bootstrap_exploit_module()
        mod_path, cls_name = poc_module.rsplit(".", 1)
        mod = importlib.import_module(mod_path)
        exploit_cls = getattr(mod, cls_name)
        exploit = exploit_cls(base_url=target_url)
        r = exploit.run()
        # Как и в mosaic.oracle.evaluator: одна повторная попытка при
        # транзиентной сетевой ошибке (приложение могло не успеть подняться).
        if r.error and "Failed to connect" in (r.error or ""):
            print("poc: транзиентная ошибка соединения, повтор через 4с")
            time.sleep(4)
            exploit = exploit_cls(base_url=target_url)
            r = exploit.run()
        if r.error:
            result = {"verdict": "ERROR", "evidence": "", "error": r.error}
        elif r.success:
            result = {"verdict": "VULNERABLE", "evidence": r.evidence, "error": ""}
        else:
            result = {"verdict": "SECURE", "evidence": r.evidence, "error": ""}
        result["requests_made"] = len(r.requests_made)
    except Exception as e:  # ошибка загрузки/выполнения оракула
        result = {"verdict": "ERROR", "evidence": "", "error": str(e)}

    (evidence_dir / "poc_result.json").write_text(
        json.dumps(result, ensure_ascii=False, indent=2))
    print(f"poc: {result['verdict']}: {result['evidence'] or result['error']}"[:500])
    return 0 if result["verdict"] in ("VULNERABLE", "SECURE") else 1


if __name__ == "__main__":
    sys.exit(main())
