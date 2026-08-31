#!/usr/bin/env python3
"""Парный прогон сценария «Вредоносный пакет через .cursorrules» (вектор B2).

Прогоняет малус-цепочку и benign-твин, печатает матрицу сравнения.
Для npm install express нужен режим сети allowlist (см. chain.json).

Использование:
    python3 isolated/agent_rules_twin_report.py [--network allowlist]
"""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
MALICIOUS_CHAIN = "agent_rules_malicious_package"
BENIGN_CHAIN = "agent_rules_malicious_package_benign"


def run_chain(chain_id: str, network: str) -> dict | None:
    print(f"[twin] прогон: {chain_id} (сеть: {network})")
    subprocess.run(
        ["./run_isolated.sh", chain_id, "--network", network],
        cwd=REPO_ROOT,
        check=False,
    )
    runs = sorted((REPO_ROOT / "logs").glob(f"{chain_id}-*"))
    for run_dir in reversed(runs):
        result = run_dir / "result.json"
        if result.is_file():
            data = json.loads(result.read_text())
            data["_log_dir"] = str(run_dir)
            return data
    print(f"[twin] не найден result.json для {chain_id}")
    return None


def verdict_of(manifest: dict | None) -> str:
    if manifest is None:
        return "NO_RESULT"
    return manifest.get("verdict", "NO_RESULT")


def main() -> int:
    ap = argparse.ArgumentParser(
        description="Парный прогон: малус + benign-твин (вектор B2, .cursorrules)")
    ap.add_argument("--network", choices=["blocked", "allowlist", "open"],
                    default="allowlist",
                    help="режим сети (allowlist нужен для npm install express)")
    args = ap.parse_args()

    mal = run_chain(MALICIOUS_CHAIN, args.network)
    ben = run_chain(BENIGN_CHAIN, args.network)
    mal_v, ben_v = verdict_of(mal), verdict_of(ben)

    print()
    print("=" * 64)
    print("  Матрица парного теста (вектор B2, .cursorrules)")
    print("=" * 64)
    print(f"  Малус  ({MALICIOUS_CHAIN:32}): {mal_v}")
    print(f"  Твин   ({BENIGN_CHAIN:32}): {ben_v}")
    print("=" * 64)

    ok = mal_v == "VULNERABLE" and ben_v == "SECURE"
    if ok:
        print("  Оракул валиден: малус=VULNERABLE, твин=SECURE")
        return 0
    print("  ОШИБКА: ожидалось малус=VULNERABLE и твин=SECURE")
    if mal:
        print(f"  Малус артефакты: {mal.get('_log_dir')}")
    if ben:
        print(f"  Твин артефакты: {ben.get('_log_dir')}")
    return 1


if __name__ == "__main__":
    sys.exit(main())
