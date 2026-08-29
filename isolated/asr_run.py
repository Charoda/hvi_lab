#!/usr/bin/env python3
"""Расчёт ASR (Attack Success Rate) по серии изолированных прогонов.

Каждый триал — свежее окружение (контейнеры + сеть + снос подчистую).
Вердикты собираются из logs/<chain>-<ts>/result.json:

    ASR = VULNERABLE / (VULNERABLE + SECURE)

BROKEN/ERROR считаются невалидными триалами: не входят в знаменатель,
но печатаются отдельно (много BROKEN — сломано окружение/субстрат,
много ERROR — сломан оракул). Интервал — Уилсон, 95%.

Использование:
    python3 isolated/asr_run.py readme_setup_exfil --trials 10 \
        --actor qwen --network allowlist

Результат: logs/asr-<chain>-<ts>/summary.json (+ trials.csv).
"""

from __future__ import annotations

import argparse
import csv
import json
import math
import re
import subprocess
import sys
from datetime import datetime
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
LOG_ROOT = REPO_ROOT / "logs"
RUN_DIR_RE = r"^{chain}-\d{{8}}-\d{{6}}$"


def wilson_ci(k: int, n: int, z: float = 1.959964) -> tuple[float, float] | None:
    if n == 0:
        return None
    p = k / n
    denom = 1 + z * z / n
    center = (p + z * z / (2 * n)) / denom
    half = z * math.sqrt(p * (1 - p) / n + z * z / (4 * n * n)) / denom
    return max(0.0, center - half), min(1.0, center + half)


def latest_result(chain_id: str, since: float) -> dict | None:
    """Свежайший result.json цепочки, созданный не раньше `since`."""
    pat = re.compile(RUN_DIR_RE.format(chain=re.escape(chain_id)))
    best: tuple[float, Path] | None = None
    for d in LOG_ROOT.glob(f"{chain_id}-*"):
        if not pat.fullmatch(d.name):
            continue  # не путать цепочку с её бенин-твином (общий префикс)
        r = d / "result.json"
        if r.is_file() and r.stat().st_mtime >= since:
            if best is None or r.stat().st_mtime > best[0]:
                best = (r.stat().st_mtime, r)
    if best is None:
        return None
    return json.loads(best[1].read_text())


def main() -> int:
    ap = argparse.ArgumentParser(description="ASR по серии изолированных прогонов")
    ap.add_argument("chain_id", help="идентификатор цепочки")
    ap.add_argument("--trials", type=int, default=5, help="число триалов (по умолчанию 5)")
    ap.add_argument("--network", choices=["blocked", "allowlist", "open"],
                    default="allowlist",
                    help="режим сети (по умолчанию allowlist; с локальным LLM "
                         "в песочнице агенту доступен и blocked)")
    ap.add_argument("--actor", choices=["golden", "qwen"], default="qwen",
                    help="исполнитель сценария (по умолчанию qwen)")
    ap.add_argument("--llm", choices=["llama", "api"], default="llama",
                    help="бэкенд модели для агента (по умолчанию llama — сервер "
                         "и веса модели GGUF запечены в образ песочницы)")
    ap.add_argument("--llama-model", default=None,
                    help="URL .gguf, запекаемого в образ (по умолчанию тот, что задан в run.py)")
    ap.add_argument("--timeout", type=int, default=900, help="лимит времени актора, сек")
    args = ap.parse_args()

    trials: list[dict] = []
    counts = {"VULNERABLE": 0, "SECURE": 0, "BROKEN": 0, "ERROR": 0}

    for i in range(1, args.trials + 1):
        started = datetime.now().timestamp()
        print(f"\n[asr] триал {i}/{args.trials}: {args.chain_id} "
              f"(актор: {args.actor}, llm: {args.llm}, сеть: {args.network})", flush=True)
        cmd = ["./run_isolated.sh", args.chain_id,
               "--network", args.network,
               "--actor", args.actor,
               "--llm", args.llm,
               "--timeout", str(args.timeout)]
        if args.llama_model:
            cmd += ["--llama-model", args.llama_model]
        subprocess.run(cmd, cwd=REPO_ROOT, check=False)
        data = latest_result(args.chain_id, started)
        if data is None:
            counts["ERROR"] += 1
            trials.append({"trial": i, "verdict": "ERROR", "error": "нет result.json"})
            continue
        verdict = data.get("verdict", "ERROR")
        counts[verdict] = counts.get(verdict, 0) + 1
        trials.append({"trial": i, "verdict": verdict,
                       "duration_s": data.get("duration_s"),
                       "evidence": (data.get("evidence") or data.get("detail") or "")[:300],
                       "log_dir": str(LOG_ROOT / data.get("run_id", "?"))})
        print(f"[asr] триал {i}: {verdict}", flush=True)

    valid = counts["VULNERABLE"] + counts["SECURE"]
    asr = counts["VULNERABLE"] / valid if valid else None
    ci = wilson_ci(counts["VULNERABLE"], valid) if valid else None

    summary = {
        "chain_id": args.chain_id,
        "actor": args.actor,
        "llm_backend": args.llm,
        "llama_model": args.llama_model,
        "network_mode": args.network,
        "trials": args.trials,
        "counts": counts,
        "valid_trials": valid,
        "asr": asr,
        "asr_wilson95": list(ci) if ci else None,
        "finished_at": datetime.now().isoformat(timespec="seconds"),
    }

    ts = datetime.now().strftime("%Y%m%d-%H%M%S")
    out_dir = LOG_ROOT / f"asr-{args.chain_id}-{ts}"
    out_dir.mkdir(parents=True, exist_ok=True)
    (out_dir / "summary.json").write_text(json.dumps(summary, ensure_ascii=False, indent=2))
    with (out_dir / "trials.csv").open("w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=["trial", "verdict", "duration_s", "log_dir", "evidence"])
        w.writeheader()
        w.writerows(trials)

    print()
    print("=" * 62)
    print(f"  ASR: {args.chain_id} × актор={args.actor} × сеть={args.network}")
    print(f"  Триалов: {args.trials} (валидных: {valid}; "
          f"BROKEN: {counts['BROKEN']}, ERROR: {counts['ERROR']})")
    if asr is None:
        print("  ASR: н/д — нет валидных триалов (см. BROKEN/ERROR)")
    else:
        lo, hi = ci
        print(f"  VULNERABLE: {counts['VULNERABLE']} | SECURE: {counts['SECURE']}")
        print(f"  ASR = {asr:.1%} (95% CI Уилсона: {lo:.1%}–{hi:.1%})")
    print(f"  Сводка: {out_dir / 'summary.json'}")
    print("=" * 62)
    return 0 if valid else 1


if __name__ == "__main__":
    sys.exit(main())
