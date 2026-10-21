#!/usr/bin/env python3
"""Audit Task 4 sampling: pick exactly 10 OpenCode malicious runs with
stopped_by=model and no hard failure, balanced across profiles (4 off / 3 normal / 3 strict).

Deterministic: random.seed(20261020). Writes audit/task4_sample.json.
"""
from __future__ import annotations
import csv, json, random
from collections import Counter
from pathlib import Path

AUD = Path("/home/user/mosaic-benchmark/audit")
QUOTA = {"off": 4, "normal": 3, "strict": 3}

rows = list(csv.DictReader((AUD / "task1_final.tsv").open(newline="", encoding="utf-8"), delimiter="\t"))
cand = [r for r in rows if r["actor"] == "opencode" and r["variant"] == "malicious"
        and r["tsv_stopped_by"] == "model" and r["exclude_from_metrics"] == "False"]
print(f"кандидатов: {len(cand)}  по профилям: {dict(Counter(r['profile'] for r in cand))}")

random.seed(20261020)
pick = []
for p, k in QUOTA.items():
    sub = [r for r in cand if r["profile"] == p]
    pick += random.sample(sub, min(k, len(sub)))
pick.sort(key=lambda r: (r["profile"], r["scenario"], r["repeat_idx"]))

KEYS = ("profile", "scenario", "variant", "repeat_idx", "run_id", "duration_s",
        "tsv_verdict", "tsv_attack_attempted", "tsv_attack_success",
        "exit_code_file", "agent_log_lines", "n_tool_markers", "batch")
out = [{k: r[k] for k in KEYS} for r in pick]
(AUD / "task4_sample.json").write_text(json.dumps(out, ensure_ascii=False, indent=1), encoding="utf-8")
print(f"\nвыбрано {len(out)} прогонов -> audit/task4_sample.json")
for i, r in enumerate(out, 1):
    print(f"{i:2d}. {r['profile']:7s} {r['scenario']:24s} idx={r['repeat_idx']} "
          f"dur={r['duration_s']:>7s}s exit={r['exit_code_file']:2s} {r['run_id']}")
