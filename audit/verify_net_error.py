#!/usr/bin/env python3
"""Verify what the net_error signature actually matches (context lines)."""
from __future__ import annotations
import csv, re
from pathlib import Path
from collections import Counter

REPO = Path("/home/user/mosaic-benchmark")
LOGS = REPO / "logs"
AUDIT = REPO / "audit"

RX = re.compile(r"(ECONNRESET|ECONNREFUSED|ENOTFOUND|ETIMEDOUT|fetch failed|socket hang up|network error)", re.I)

with (AUDIT / "run_class.tsv").open(newline="", encoding="utf-8") as fh:
    rows = [r for r in csv.DictReader(fh, delimiter="\t") if "net_error" in r["infra_sigs"]]

print(f"runs flagged net_error: {len(rows)}")
ctx_counter: Counter[str] = Counter()
samples: dict[str, list[str]] = {}
for r in rows[:400]:
    p = LOGS / r["run_id"] / "actor_stderr.log"
    if not p.is_file():
        continue
    try:
        text = p.read_text(encoding="utf-8", errors="replace")
    except OSError:
        continue
    lines = text.splitlines()
    for i, ln in enumerate(lines):
        if RX.search(ln):
            # classify by surrounding shape
            low = ln.lower()
            if "curl:" in low:
                key = "curl: (6)/(7)/(28) — agent's own shell command failed"
            elif "npm error" in low or "npm err!" in low:
                key = "npm error — package install failure inside sandbox"
            elif "level=error" in low and "providerid" in low:
                key = "opencode provider stream error (LLM API)"
            elif "requests.exceptions" in low or "urllib3" in low or "httpx" in low:
                key = "python http client error in app/test code"
            elif "traceback" in low:
                key = "python traceback in app/test code"
            else:
                key = "other"
            ctx_counter[key] += 1
            samples.setdefault(key, [])
            if len(samples[key]) < 3:
                samples[key].append(f"{r['run_id']}:{i+1}: {ln.strip()[:200]}")

print()
for k, v in ctx_counter.most_common():
    print(f"  {v:6d}  {k}")
print()
for k, v in samples.items():
    print(f"--- {k}")
    for s in v:
        print(f"    {s}")
