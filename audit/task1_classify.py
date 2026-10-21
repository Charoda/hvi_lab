#!/usr/bin/env python3
"""Audit Task 1 (final): definitive per-run failure classification.

Classes:
  infra_api        - LLM provider failure (credits/AI_APICallError/stream error/5xx).
                     The agent never did the work -> row must NOT count as valid.
  empty_transcript - agent log has <3 lines and no tool activity.
  short_no_error   - duration far below the batch median but no API error line.
  substrate_env    - missing dependency in the app substrate (flask/express/...).
                     Degrades utility (TCR), not necessarily the attack verdict.
  tool_degraded    - OpenCode Glob/ripgrep tool failed (agent continued).
  profile_ask      - actor exit 75 = permission ask barrier (INTENDED for normal/strict).
  nonzero_exit     - other non-zero actor exit.
  ok

Read-only w.r.t. logs/. Writes audit/task1_runs.tsv, audit/task1_failures.tsv.
"""
from __future__ import annotations

import csv
import json
import re
import statistics
from collections import Counter, defaultdict
from pathlib import Path

REPO = Path("/home/user/mosaic-benchmark")
LOGS = REPO / "logs"
AUDIT = REPO / "audit"

SECRET = re.compile(r"(sk-or-v1-[A-Za-z0-9]+|crsr-[A-Za-z0-9_\-]+|/keys/[A-Za-z0-9]{16,})")

INFRA_API = {
    "api_credits":  re.compile(r"requires more credits|only afford \d+ tokens|adjust the key's total limit"),
    "api_call_err": re.compile(r"AI_APICallError"),
    "stream_error": re.compile(r'level=ERROR.*"stream error"'),
    "http_5xx":     re.compile(r"\b(500|502|503|504)\b(?=.*(error|Error|gateway|Gateway|unavailable))"),
    "http_429":     re.compile(r"\b429\b(?=.*(rate|limit|many))|(?:rate.?limit|too many requests)(?=.*\b429\b)"),
    "rate_limit_txt": re.compile(r"Rate limit exceeded|free-models-per-day"),
}
SUBSTRATE = {
    "mod_not_found": re.compile(r"ModuleNotFoundError: No module named '([A-Za-z0-9_.]+)'"),
    "cannot_find_mod": re.compile(r"Cannot find module '([A-Za-z0-9_.@/-]+)'"),
    "pip_no_dist": re.compile(r"ERROR: Could not find a version|No matching distribution found"),
}
TOOLFAIL = {
    "ripgrep_failed": re.compile(r"ripgrep execution failed"),
    "glob_failed": re.compile(r"Glob .* failed"),
}
MAX_BYTES = 25_000_000


def redact(s: str) -> str:
    return SECRET.sub("REDACTED", s)


def read(p: Path) -> str:
    try:
        if not p.is_file() or p.stat().st_size > MAX_BYTES:
            return ""
        return p.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return ""


def quote(text: str, rx: re.Pattern, width: int = 300) -> str:
    for ln in text.splitlines():
        if rx.search(ln):
            return redact(ln.strip()[:width])
    return ""


def main() -> None:
    with (AUDIT / "index.tsv").open(newline="", encoding="utf-8") as fh:
        rows = list(csv.DictReader(fh, delimiter="\t"))

    recs = []
    for r in rows:
        rd = LOGS / r["run_id"]
        if r["actor"] == "opencode":
            agent_log = read(rd / "actor_stderr.log")
            extra = read(rd / "actor_stdout.log")
            agent_name = "actor_stderr.log"
        else:
            agent_log = read(rd / "cursor_agent.log")
            extra = ""
            agent_name = "cursor_agent.log"
        blob = agent_log + "\n" + extra

        api_hits = [k for k, rx in INFRA_API.items() if rx.search(blob)]
        sub_hits = [k for k, rx in SUBSTRATE.items() if rx.search(blob)]
        tool_hits = [k for k, rx in TOOLFAIL.items() if rx.search(blob)]

        ec = read(rd / "exit_code").strip()
        rj_path = rd / "result.json"
        actor_exit, ask_barrier, rj_stopped, honey = "", "", "", ""
        if rj_path.is_file():
            try:
                j = json.loads(rj_path.read_text(encoding="utf-8", errors="replace"))
                actor_exit = str(j.get("actor_exit_code", ""))
                pa = j.get("permission_analysis") or {}
                ask_barrier = str(pa.get("actor_exit_code_ask_barrier", ""))
                rj_stopped = str(pa.get("stopped_by", ""))
                honey = str(pa.get("honey_requests", ""))
            except json.JSONDecodeError:
                actor_exit = "JSON_ERROR"

        nlines = len(agent_log.splitlines())
        ntool = len(re.findall(r"^(?:→|\$) ", agent_log, re.M))
        try:
            dur = float(r["duration_s"])
        except ValueError:
            dur = float("nan")

        rec = dict(
            batch=r["batch"], actor=r["actor"], profile=r["profile"],
            scenario=r["scenario"], variant=r["variant"], repeat_idx=r["repeat_idx"],
            run_id=r["run_id"], duration_s=r["duration_s"], dur=dur,
            tsv_verdict=r["verdict"], tsv_valid=r["valid"],
            tsv_stopped_by=r["stopped_by"], tsv_attack_success=r["attack_success"],
            tsv_attack_attempted=r["attack_attempted"],
            tsv_utility_success=r["utility_success"], tsv_tests_passed=r["tests_passed"],
            tsv_defense_false_positive=r["defense_false_positive"],
            tsv_permission_blocked_attack=r["permission_blocked_attack"],
            tsv_permission_blocked_utility=r["permission_blocked_utility"],
            agent_log=agent_name, agent_log_lines=nlines, agent_log_bytes=len(agent_log),
            n_tool_markers=ntool, exit_code_file=ec, actor_exit_code=actor_exit,
            ask_barrier=ask_barrier, rj_stopped_by=rj_stopped, honey_requests=honey,
            api_sigs=",".join(api_hits), substrate_sigs=",".join(sub_hits),
            tool_sigs=",".join(tool_hits),
            api_quote=quote(blob, INFRA_API[api_hits[0]]) if api_hits else "",
        )
        recs.append(rec)

    # duration baselines per (actor, profile, variant)
    base: dict[tuple, float] = {}
    grp: dict[tuple, list[float]] = defaultdict(list)
    for rec in recs:
        if rec["dur"] == rec["dur"]:
            grp[(rec["actor"], rec["profile"], rec["variant"])].append(rec["dur"])
    for k, v in grp.items():
        base[k] = statistics.median(v)

    for rec in recs:
        b = base.get((rec["actor"], rec["profile"], rec["variant"]), float("nan"))
        rec["batch_median_dur"] = f"{b:.1f}" if b == b else ""
        short = (rec["dur"] == rec["dur"] and b == b and rec["dur"] < max(30.0, 0.25 * b))
        rec["dur_is_outlier_short"] = str(short)

        if rec["api_sigs"]:
            cls = "infra_api"
        elif rec["agent_log_lines"] < 3 and rec["n_tool_markers"] == 0:
            cls = "empty_transcript"
        elif short:
            cls = "short_no_error"
        elif rec["ask_barrier"] == "True" or rec["exit_code_file"] == "75":
            cls = "profile_ask"
        elif rec["exit_code_file"] not in ("", "0"):
            cls = f"nonzero_exit_{rec['exit_code_file']}"
        else:
            cls = "ok"
        rec["failure_class"] = cls
        # secondary flags (do not change failure_class)
        rec["substrate_env"] = str(bool(rec["substrate_sigs"]))
        rec["tool_degraded"] = str(bool(rec["tool_sigs"]))
        # is this a run that must be excluded from the denominator?
        rec["exclude_from_metrics"] = str(cls in ("infra_api", "empty_transcript", "short_no_error"))

    FIELDS = [k for k in recs[0].keys() if k != "dur"]
    with (AUDIT / "task1_runs.tsv").open("w", newline="", encoding="utf-8") as fh:
        w = csv.DictWriter(fh, fieldnames=FIELDS, delimiter="\t", extrasaction="ignore")
        w.writeheader()
        w.writerows(recs)

    bad = [r for r in recs if r["exclude_from_metrics"] == "True"]
    with (AUDIT / "task1_failures.tsv").open("w", newline="", encoding="utf-8") as fh:
        w = csv.DictWriter(fh, fieldnames=FIELDS, delimiter="\t", extrasaction="ignore")
        w.writeheader()
        w.writerows(bad)

    # ---- report ---------------------------------------------------------
    out: list[str] = []
    out.append(f"total runs: {len(recs)}")
    out.append("")
    out.append("== failure_class by actor/profile ==")
    tab: dict[tuple, Counter] = defaultdict(Counter)
    for r in recs:
        tab[(r["actor"], r["profile"])][r["failure_class"]] += 1
    for k in sorted(tab):
        out.append(f"  {k[0]:9s} {k[1]:7s} n={sum(tab[k].values()):4d}  {dict(tab[k])}")
    out.append("")
    out.append(f"== EXCLUDE-FROM-METRICS runs: {len(bad)} ==")
    out.append("  by class: " + str(dict(Counter(r["failure_class"] for r in bad))))
    out.append("  by actor/profile: " + str(dict(Counter((r["actor"], r["profile"]) for r in bad))))
    out.append("  by variant: " + str(dict(Counter(r["variant"] for r in bad))))
    out.append("  TSV valid among them: " + str(dict(Counter(r["tsv_valid"] for r in bad))))
    out.append("  TSV verdict among them: " + str(dict(Counter(r["tsv_verdict"] for r in bad))))
    out.append("  TSV stopped_by among them: " + str(dict(Counter(r["tsv_stopped_by"] for r in bad))))
    out.append("")
    out.append("== infra_api detail ==")
    ia = [r for r in recs if r["failure_class"] == "infra_api"]
    out.append("  api_sigs combos: " + str(dict(Counter(r["api_sigs"] for r in ia))))
    ds = sorted(r["dur"] for r in ia if r["dur"] == r["dur"])
    if ds:
        out.append(f"  duration_s: min={ds[0]:.0f} med={statistics.median(ds):.0f} max={ds[-1]:.0f}")
    out.append("  per scenario/variant (infra_api):")
    cs = Counter((r["scenario"], r["variant"]) for r in ia)
    for k in sorted(cs):
        out.append(f"    {k[0]:26s} {k[1]:10s} {cs[k]}")
    out.append("")
    out.append("== empty_transcript / short_no_error detail ==")
    for c in ("empty_transcript", "short_no_error"):
        sub = [r for r in recs if r["failure_class"] == c]
        out.append(f"  {c}: n={len(sub)}")
        for r in sub[:40]:
            out.append(f"    {r['actor']:9s} {r['profile']:7s} {r['scenario']:26s} {r['variant']:10s} "
                       f"idx={r['repeat_idx']} dur={r['duration_s']:>7s}s lines={r['agent_log_lines']:>4} "
                       f"tools={r['n_tool_markers']:>3} verdict={r['tsv_verdict']} "
                       f"valid={r['tsv_valid']} stopped_by={r['tsv_stopped_by']!r} {r['run_id']}")
    out.append("")
    out.append("== secondary flags (do not invalidate the run) ==")
    out.append("  substrate_env runs: " + str(sum(1 for r in recs if r["substrate_env"] == "True")))
    out.append("    by actor: " + str(dict(Counter(r["actor"] for r in recs if r["substrate_env"] == "True"))))
    out.append("    by sig: " + str(dict(Counter(r["substrate_sigs"] for r in recs if r["substrate_env"] == "True"))))
    out.append("  tool_degraded runs: " + str(sum(1 for r in recs if r["tool_degraded"] == "True")))
    out.append("    by actor: " + str(dict(Counter(r["actor"] for r in recs if r["tool_degraded"] == "True"))))
    out.append("")
    out.append("== duration medians per actor/profile/variant ==")
    for k in sorted(base):
        out.append(f"  {k[0]:9s} {k[1]:7s} {k[2]:10s} median={base[k]:7.1f}s n={len(grp[k])}")

    txt = "\n".join(out)
    (AUDIT / "task1_report.txt").write_text(txt, encoding="utf-8")
    print(txt)


if __name__ == "__main__":
    main()
