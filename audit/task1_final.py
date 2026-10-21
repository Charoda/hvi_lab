#!/usr/bin/env python3
"""Audit Task 1 (definitive): content-based hard-failure detection.

Drops duration/line-count heuristics (verified to produce false positives:
short runs contain complete transcripts with passing tests).

A run is a HARD FAILURE only if the agent provably did not get to act:
  api_provider   - OpenRouter credits/AI_APICallError/stream error/5xx in the agent log
  cli_model_reject - Cursor CLI: "Cannot use this model"
  cli_no_output  - agent log empty/whitespace-only
  timed_out      - duration_s >= the batch timeout (2400)
  cli_error      - other explicit CLI fatal error line

Separately flagged (does NOT invalidate the run, but breaks comparability):
  profile_degraded - Cursor "Auto-review is unavailable ... Falling back to Allowlist"
                     => the `normal` profile was not actually applied
  substrate_env    - missing python/node dependency in the app substrate
  tool_degraded    - OpenCode Glob/ripgrep tool failure

Read-only w.r.t. logs/. Writes audit/task1_final.tsv + audit/task1_report.txt
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
TIMEOUT_S = 2400.0

ANSI = re.compile(r"\x1b\[[0-9;]*[A-Za-z]|\x1b\][^\x07]*\x07")
SECRET = re.compile(r"(sk-or-v1-[A-Za-z0-9]+|crsr-[A-Za-z0-9_\-]+|/keys/[A-Za-z0-9]{16,})")

HARD = {
    "api_provider": re.compile(
        r"requires more credits|only afford \d+ tokens|adjust the key's total limit"
        r"|AI_APICallError|Rate limit exceeded|free-models-per-day"
        r"|level=ERROR.*\"stream error\""
        r"|\b(500|502|503|504)\b(?=.*(error|Error|gateway|Gateway|unavailable))"),
    "cli_model_reject": re.compile(r"Cannot use this model"),
}
# NOT a hard failure: the agent's own shell command missing from the sandbox PATH.
# Degrades utility measurement (tests_passed / TCR), so tracked separately.
ENV_CMD_MISSING = re.compile(r"line \d+: (\S+): command not found|(?:bash|sh): \d+: (\S+): not found")
PROFILE_DEGRADED = re.compile(r"Auto-review is unavailable|Falling back to Allowlist")
SUBSTRATE = re.compile(r"ModuleNotFoundError: No module named '([A-Za-z0-9_.]+)'"
                       r"|Cannot find module '([A-Za-z0-9_.@/-]+)'"
                       r"|ERROR: Could not find a version|No matching distribution found")
TOOLFAIL = re.compile(r"ripgrep execution failed|Glob .* failed")


def clean(s: str) -> str:
    return ANSI.sub("", s)


def redact(s: str) -> str:
    return SECRET.sub("REDACTED", s)


def read(p: Path) -> str:
    try:
        if not p.is_file() or p.stat().st_size > 25_000_000:
            return ""
        return clean(p.read_text(encoding="utf-8", errors="replace"))
    except OSError:
        return ""


def first_quote(text: str, rx: re.Pattern, width: int = 300) -> str:
    for ln in text.splitlines():
        if rx.search(ln):
            return redact(ln.strip()[:width])
    return ""


def main() -> None:
    with (AUDIT / "index.tsv").open(newline="", encoding="utf-8") as fh:
        idx = list(csv.DictReader(fh, delimiter="\t"))

    recs = []
    for r in idx:
        rd = LOGS / r["run_id"]
        if r["actor"] == "opencode":
            agent = read(rd / "actor_stderr.log")
            final = read(rd / "actor_stdout.log")
            agent_name = "actor_stderr.log"
        else:
            agent = read(rd / "cursor_agent.log")
            final = agent
            agent_name = "cursor_agent.log"
        blob = agent + "\n" + final

        hard = [k for k, rx in HARD.items() if rx.search(blob)]
        try:
            dur = float(r["duration_s"])
        except ValueError:
            dur = float("nan")
        if dur == dur and dur >= TIMEOUT_S:
            hard.append("timed_out")
        if not blob.strip():
            hard.append("cli_no_output")

        # tool activity (ANSI-stripped)
        n_tool = len(re.findall(r"^(?:→|\$|✱) ", agent, re.M))

        ec = read(rd / "exit_code").strip()
        actor_exit = ask_barrier = rj_stopped = honey = ""
        rj = rd / "result.json"
        if rj.is_file():
            try:
                j = json.loads(rj.read_text(encoding="utf-8", errors="replace"))
                actor_exit = str(j.get("actor_exit_code", ""))
                pa = j.get("permission_analysis") or {}
                ask_barrier = str(pa.get("actor_exit_code_ask_barrier", ""))
                rj_stopped = str(pa.get("stopped_by", ""))
                honey = str(pa.get("honey_requests", ""))
            except json.JSONDecodeError:
                actor_exit = "JSON_ERROR"

        quote = ""
        for k in hard:
            if k == "timed_out":
                quote = f"duration_s={r['duration_s']} >= timeout {TIMEOUT_S:.0f}"
            elif k == "cli_no_output":
                quote = f"{agent_name} is empty (0 non-whitespace bytes)"
            else:
                quote = first_quote(blob, HARD[k])
                if quote:
                    break

        cls = hard[0] if hard else "ok"
        recs.append(dict(
            batch=r["batch"], actor=r["actor"], profile=r["profile"],
            scenario=r["scenario"], variant=r["variant"], repeat_idx=r["repeat_idx"],
            run_id=r["run_id"], duration_s=r["duration_s"],
            tsv_verdict=r["verdict"], tsv_valid=r["valid"],
            tsv_stopped_by=r["stopped_by"], tsv_attack_success=r["attack_success"],
            tsv_attack_attempted=r["attack_attempted"],
            tsv_utility_success=r["utility_success"], tsv_tests_passed=r["tests_passed"],
            tsv_defense_false_positive=r["defense_false_positive"],
            tsv_perm_blocked_attack=r["permission_blocked_attack"],
            tsv_perm_blocked_utility=r["permission_blocked_utility"],
            agent_log=agent_name, agent_log_lines=len(agent.splitlines()),
            agent_log_bytes=len(agent), n_tool_markers=n_tool,
            exit_code_file=ec, actor_exit_code=actor_exit, ask_barrier=ask_barrier,
            rj_stopped_by=rj_stopped, honey_requests=honey,
            hard_failure=cls, all_hard_sigs=",".join(hard), quote=quote,
            profile_degraded=str(bool(PROFILE_DEGRADED.search(blob))),
            profile_degraded_quote=first_quote(blob, PROFILE_DEGRADED, 200),
            substrate_env=str(bool(SUBSTRATE.search(blob))),
            substrate_detail=",".join(sorted(set(
                m.group(1) or m.group(2) or "pip" for m in SUBSTRATE.finditer(blob)))),
            env_cmd_missing=",".join(sorted(set(
                (m.group(1) or m.group(2)) for m in ENV_CMD_MISSING.finditer(blob)
                if (m.group(1) or m.group(2))))),
            tool_degraded=str(bool(TOOLFAIL.search(blob))),
            exclude_from_metrics=str(bool(hard)),
        ))

    FIELDS = list(recs[0].keys())
    with (AUDIT / "task1_final.tsv").open("w", newline="", encoding="utf-8") as fh:
        w = csv.DictWriter(fh, fieldnames=FIELDS, delimiter="\t")
        w.writeheader()
        w.writerows(recs)

    bad = [r for r in recs if r["exclude_from_metrics"] == "True"]
    with (AUDIT / "task1_hard_failures.tsv").open("w", newline="", encoding="utf-8") as fh:
        w = csv.DictWriter(fh, fieldnames=FIELDS, delimiter="\t")
        w.writeheader()
        w.writerows(bad)

    o: list[str] = []
    o.append(f"total runs scanned: {len(recs)}")
    o.append("")
    o.append(f"== HARD FAILURES (agent provably did not act): {len(bad)} ==")
    o.append("  by class: " + str(dict(Counter(r["hard_failure"] for r in bad))))
    o.append("  by actor/profile: " + str(dict(Counter((r["actor"], r["profile"]) for r in bad))))
    o.append("  by variant: " + str(dict(Counter(r["variant"] for r in bad))))
    o.append("  TSV valid: " + str(dict(Counter(r["tsv_valid"] for r in bad))))
    o.append("  TSV verdict: " + str(dict(Counter(r["tsv_verdict"] for r in bad))))
    o.append("  TSV stopped_by: " + str(dict(Counter(r["tsv_stopped_by"] for r in bad))))
    o.append("")
    o.append("== every hard failure, one line each ==")
    for r in sorted(bad, key=lambda x: (x["actor"], x["profile"], x["scenario"], x["variant"])):
        o.append(f"  {r['actor']:9s} {r['profile']:7s} {r['scenario']:24s} {r['variant']:10s} "
                 f"idx={r['repeat_idx']} dur={r['duration_s']:>7s}s class={r['hard_failure']:15s} "
                 f"verdict={r['tsv_verdict']:10s} valid={r['tsv_valid']:5s} "
                 f"stopped_by={r['tsv_stopped_by']!r:12s} {r['run_id']}")
    o.append("")
    o.append("== infra_api per scenario/variant (opencode strict) ==")
    for k, v in sorted(Counter((r["scenario"], r["variant"]) for r in bad
                               if r["hard_failure"] == "api_provider").items()):
        o.append(f"  {k[0]:26s} {k[1]:10s} {v}")
    o.append("")
    o.append("== duration_s of hard failures ==")
    ds = sorted(float(r["duration_s"]) for r in bad if r["hard_failure"] == "api_provider")
    if ds:
        o.append(f"  api_provider: n={len(ds)} min={ds[0]:.0f} med={statistics.median(ds):.0f} max={ds[-1]:.0f}")
    o.append("")
    o.append("== SECONDARY flags (do not invalidate, but break comparability) ==")
    pd = [r for r in recs if r["profile_degraded"] == "True"]
    o.append(f"  profile_degraded (Cursor auto-review unavailable): n={len(pd)}")
    o.append("    by profile: " + str(dict(Counter(r["profile"] for r in pd))))
    o.append("    by actor: " + str(dict(Counter(r["actor"] for r in pd))))
    se = [r for r in recs if r["substrate_env"] == "True"]
    o.append(f"  substrate_env (missing dependency): n={len(se)}")
    o.append("    by actor/profile: " + str(dict(Counter((r["actor"], r["profile"]) for r in se))))
    mods: Counter[str] = Counter()
    for r in se:
        for m in filter(None, r["substrate_detail"].split(",")):
            mods[m] += 1
    o.append("    modules: " + str(mods.most_common(12)))
    td = [r for r in recs if r["tool_degraded"] == "True"]
    o.append(f"  tool_degraded (Glob/ripgrep failed): n={len(td)}")
    o.append("    by actor: " + str(dict(Counter(r["actor"] for r in td))))
    ecm = [r for r in recs if r["env_cmd_missing"]]
    o.append(f"  env_cmd_missing (sandbox PATH): n={len(ecm)}")
    o.append("    by actor/profile: " + str(dict(Counter((r["actor"], r["profile"]) for r in ecm))))
    o.append("    by scenario: " + str(sorted(Counter(r["scenario"] for r in ecm).items(),
                                              key=lambda kv: -kv[1])[:12]))
    o.append("    commands: " + str(Counter(c for r in ecm
                                           for c in r["env_cmd_missing"].split(","))))
    o.append("    их TSV utility_success: " + str(dict(Counter(r["tsv_utility_success"] for r in ecm))))
    o.append("    их TSV tests_passed: " + str(dict(Counter(r["tsv_tests_passed"] for r in ecm))))
    o.append("")
    o.append("== exit_code_file distribution (opencode) ==")
    o.append("  " + str(dict(Counter((r["profile"], r["exit_code_file"]) for r in recs
                                     if r["actor"] == "opencode"))))
    o.append("")
    o.append("== stopped_by vs attack_success cross-tab (ALL runs) ==")
    ct: dict[tuple, int] = defaultdict(int)
    for r in recs:
        ct[(r["actor"], r["variant"], r["tsv_attack_success"], r["tsv_stopped_by"])] += 1
    for k in sorted(ct):
        o.append(f"  {k[0]:9s} {k[1]:10s} attack_success={k[2]:6s} stopped_by={k[3]!r:14s} n={ct[k]}")

    txt = "\n".join(o)
    (AUDIT / "task1_report.txt").write_text(txt, encoding="utf-8")
    print(txt)


if __name__ == "__main__":
    main()
