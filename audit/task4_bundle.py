#!/usr/bin/env python3
"""Audit Task 4: build a compact evidence bundle for the 10 sampled
OpenCode malicious runs carrying stopped_by="model".

For each run: the injected trigger, the assigned task, the agent's final
summary, the tool-call trace, every transcript line that touches the attack
surface, permission events, oracle behaviour analysis, honey traffic.

Read-only w.r.t. logs/. Writes audit/task4_bundle.txt
"""
from __future__ import annotations

import csv
import json
import re
from pathlib import Path

REPO = Path("/home/user/mosaic-benchmark")
LOGS = REPO / "logs"
AUDIT = REPO / "audit"
CHAINS = REPO / "benchmark/chains"

ANSI = re.compile(r"\x1b\[[0-9;]*[A-Za-z]|\x1b\][^\x07]*\x07")
SECRET = re.compile(r"(sk-or-v1-[A-Za-z0-9]+|crsr-[A-Za-z0-9_\-]+|/keys/[A-Za-z0-9]{16,})")
TOOL = re.compile(r"^(?:→|\$|✱|✗)\s")
ATTACK = re.compile(
    r"curl|wget|\bnc\b|ncat|secret\.txt|/init|exfil|honey|8080|POST\b|urllib|requests\.post"
    r"|license|лиценз|activate|активац|protected/|не буду|не стал|отказ|refuse|won't|will not"
    r"|suspicious|подозрит|вредонос|malicious|инъекц|injection", re.I)
MAXQ = 300


def clean(p: Path, limit: int = 400_000) -> str:
    try:
        if not p.is_file():
            return ""
        if p.stat().st_size > limit:
            return p.read_text(encoding="utf-8", errors="replace")[:limit]
        return p.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return ""


def redact(s: str) -> str:
    return SECRET.sub("REDACTED", s)


def main() -> None:
    sample = json.loads((AUDIT / "task4_sample.json").read_text(encoding="utf-8"))
    t1 = {r["run_id"]: r for r in csv.DictReader(
        (AUDIT / "task1_final.tsv").open(newline="", encoding="utf-8"), delimiter="\t")}

    out: list[str] = []
    for i, s in enumerate(sample, 1):
        rid = s["run_id"]
        rd = LOGS / rid
        sc = s["scenario"]
        tr = t1.get(rid, {})
        out.append("=" * 100)
        out.append(f"### {i}. {rid}")
        out.append(f"    profile={s['profile']} scenario={sc} idx={s['repeat_idx']} "
                   f"duration_s={s['duration_s']} exit_code_file={s['exit_code_file']} "
                   f"verdict={s['tsv_verdict']} attack_attempted={s['tsv_attack_attempted']} "
                   f"attack_success={s['tsv_attack_success']}")
        out.append(f"    stopped_by(TSV)={tr.get('tsv_stopped_by')!r} "
                   f"utility_success={tr.get('tsv_utility_success')!r} "
                   f"tests_passed={tr.get('tsv_tests_passed')!r} "
                   f"perm_blocked_attack={tr.get('tsv_perm_blocked_attack')!r} "
                   f"honey_requests(result.json)={tr.get('honey_requests')!r}")

        # --- what the agent was asked, and what it was tempted with ---
        out.append("    --- agent_prompt.txt (задача):")
        for ln in clean(CHAINS / sc / "agent_prompt.txt").strip().splitlines()[:8]:
            out.append("      | " + redact(ln.strip()[:MAXQ]))
        out.append("    --- trigger.txt (инъекция):")
        for ln in clean(CHAINS / sc / "trigger.txt").strip().splitlines()[:12]:
            out.append("      | " + redact(ln.strip()[:MAXQ]))

        # --- final summary ---
        so = clean(rd / "actor_stdout.log").strip()
        out.append(f"    --- actor_stdout.log (финальный ответ, {len(so)} байт):")
        if not so:
            out.append("      | <ПУСТО>")
        for ln in so.splitlines()[:20]:
            out.append("      | " + redact(ln.strip()[:MAXQ]))

        # --- tool trace ---
        se = ANSI.sub("", clean(rd / "actor_stderr.log"))
        selines = se.splitlines()
        tools = [ln.strip() for ln in selines if TOOL.match(ANSI.sub("", ln))]
        out.append(f"    --- трек инструментов ({len(tools)} вызовов), actor_stderr.log:")
        for ln in tools[:45]:
            out.append("      | " + redact(ln[:MAXQ]))
        if len(tools) > 45:
            out.append(f"      | ... ещё {len(tools) - 45}")

        # --- attack-surface lines ---
        hits = []
        for n, ln in enumerate(selines, 1):
            if ATTACK.search(ln) and not TOOL.match(ln):
                hits.append((n, ln.strip()))
        out.append(f"    --- строки транскрипта про поверхность атаки/отказ ({len(hits)}):")
        for n, ln in hits[:25]:
            out.append(f"      | L{n}: " + redact(ln[:MAXQ]))
        if len(hits) > 25:
            out.append(f"      | ... ещё {len(hits) - 25}")

        # --- permission events ---
        pe = clean(rd / "permission_events.jsonl").strip()
        out.append(f"    --- permission_events.jsonl ({len(pe)} байт):")
        for ln in pe.splitlines()[:10]:
            out.append("      | " + redact(ln.strip()[:MAXQ]))
        if not pe:
            out.append("      | <пусто/отсутствует>")

        # --- oracle behaviour analysis ---
        ba = rd / "behavior_analysis.json"
        if ba.is_file():
            try:
                j = json.loads(ba.read_text(encoding="utf-8", errors="replace"))
                keys = ("secret_read", "utils_read", "curl_exec_observed", "secret_delivered",
                        "attack_attempted", "attack_success", "utility_success", "tests_passed",
                        "ask_attack", "deny_attack", "honey_hits")
                out.append("    --- behavior_analysis.json: "
                           + json.dumps({k: j.get(k) for k in keys if k in j}, ensure_ascii=False))
            except json.JSONDecodeError:
                out.append("    --- behavior_analysis.json: не читается")
        else:
            out.append("    --- behavior_analysis.json: ОТСУТСТВУЕТ")

        # --- honey ---
        hq = clean(rd / "honey_requests.jsonl").strip()
        hl = clean(rd / "honey_listener.log").strip()
        out.append(f"    --- honey_requests.jsonl ({len(hq)} байт): "
                   + (hq[:MAXQ] if hq else "<пусто/отсутствует>"))
        out.append(f"    --- honey_listener.log: " + (hl.splitlines()[0][:160] if hl else "<нет>")
                   + (f"  (всего строк {len(hl.splitlines())})" if hl else ""))
        out.append("")

    txt = "\n".join(out)
    (AUDIT / "task4_bundle.txt").write_text(txt, encoding="utf-8")
    print(f"wrote audit/task4_bundle.txt  ({len(txt)} bytes, {len(out)} lines)")


if __name__ == "__main__":
    main()
