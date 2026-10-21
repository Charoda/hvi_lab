#!/usr/bin/env python3
"""Inspect the suspicious run subsets individually (Task 1 evidence gathering)."""
from __future__ import annotations
import csv
from pathlib import Path

REPO = Path("/home/user/mosaic-benchmark")
LOGS = REPO / "logs"
AUDIT = REPO / "audit"

rows = list(csv.DictReader((AUDIT / "task1_runs.tsv").open(newline="", encoding="utf-8"), delimiter="\t"))


def dump(rid: str, actor: str, n: int = 12) -> None:
    rd = LOGS / rid
    names = ["cursor_agent.log"] if actor == "cursor" else ["actor_stdout.log", "actor_stderr.log"]
    for nm in names:
        p = rd / nm
        if not p.is_file():
            print(f"    [{nm}] ОТСУТСТВУЕТ")
            continue
        txt = p.read_text(encoding="utf-8", errors="replace")
        lines = txt.splitlines()
        print(f"    [{nm}] bytes={len(txt)} lines={len(lines)}")
        head = lines[:n] if nm != "actor_stderr.log" else lines[:n]
        tail = lines[-n:] if len(lines) > 2 * n else []
        for ln in head:
            print("      | " + ln.strip()[:180])
        if tail:
            print("      ...")
            for ln in tail:
                print("      | " + ln.strip()[:180])


print("###### A. cursor: agent_log_lines < 3 ######")
a = [r for r in rows if r["actor"] == "cursor" and int(r["agent_log_lines"]) < 3]
print(f"count={len(a)}")
for r in a:
    print(f"\n--- {r['run_id']} dur={r['duration_s']}s lines={r['agent_log_lines']} "
          f"verdict={r['tsv_verdict']} valid={r['tsv_valid']} stopped_by={r['tsv_stopped_by']!r} "
          f"attack_success={r['tsv_attack_success']} utility={r['tsv_utility_success']} "
          f"class={r['failure_class']}")
    dump(r["run_id"], "cursor", 8)

print("\n\n###### B. opencode: failure_class == short_no_error ######")
b = [r for r in rows if r["actor"] == "opencode" and r["failure_class"] == "short_no_error"]
print(f"count={len(b)}")
for r in b[:8]:
    print(f"\n--- {r['run_id']} dur={r['duration_s']}s (median {r['batch_median_dur']}s) "
          f"lines={r['agent_log_lines']} tools={r['n_tool_markers']} exit={r['exit_code_file']} "
          f"verdict={r['tsv_verdict']} valid={r['tsv_valid']} stopped_by={r['tsv_stopped_by']!r} "
          f"attack_attempted={r['tsv_attack_attempted']}")
    dump(r["run_id"], "opencode", 10)

print("\n\n###### C. cursor: duration >= 2000s (timeout) ######")
c = [r for r in rows if r["actor"] == "cursor" and float(r["duration_s"] or 0) >= 2000]
for r in c:
    print(f"\n--- {r['run_id']} dur={r['duration_s']}s lines={r['agent_log_lines']} "
          f"verdict={r['tsv_verdict']} valid={r['tsv_valid']} stopped_by={r['tsv_stopped_by']!r}")
    dump(r["run_id"], "cursor", 10)

print("\n\n###### D. opencode: duration >= 2000s (timeout) ######")
d = [r for r in rows if r["actor"] == "opencode" and float(r["duration_s"] or 0) >= 2000]
print(f"count={len(d)}")
for r in d:
    print(f"  {r['run_id']} dur={r['duration_s']}s verdict={r['tsv_verdict']} "
          f"valid={r['tsv_valid']} stopped_by={r['tsv_stopped_by']!r} class={r['failure_class']}")
