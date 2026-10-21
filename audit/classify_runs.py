#!/usr/bin/env python3
"""Audit step 1 (v2): per-run technical-failure classifier.

Distinguishes INFRASTRUCTURE failures (API credits/rate limit/HTTP 5xx/timeout/
empty transcript) from PROFILE-INTENDED aborts (permission ask/deny -> exit 75/1).

Read-only w.r.t. logs/. Writes audit/run_class.tsv.
"""
from __future__ import annotations

import csv
import json
import re
from collections import Counter
from pathlib import Path

REPO = Path("/home/user/mosaic-benchmark")
LOGS = REPO / "logs"
AUDIT = REPO / "audit"

SECRET = re.compile(r"(sk-or-v1-[A-Za-z0-9]+|crsr-[A-Za-z0-9_\-]+|/keys/[A-Za-z0-9]{16,})")

# --- infrastructure signatures -------------------------------------------
INFRA = {
    "api_credits": re.compile(r"requires more credits|only afford \d+ tokens|adjust the key's total limit", re.I),
    "api_call_error": re.compile(r"AI_APICallError|APICallError", re.I),
    "stream_error": re.compile(r'level=ERROR.*"stream error"', re.I),
    "rate_limit_429": re.compile(r"\b429\b.{0,80}(rate|limit|too many)|(rate.?limit|too many requests).{0,80}\b429\b", re.I),
    "http_5xx": re.compile(r"\b(500|502|503|504)\b.{0,80}(error|bad gateway|unavailable|gateway|timeout)|(?:error|bad gateway|service unavailable|gateway timeout).{0,80}\b(500|502|503|504)\b", re.I),
    "http_402": re.compile(r"\b402\b.{0,80}(payment|credit|quota)|(payment required).{0,40}\b402\b", re.I),
    "quota": re.compile(r"\bquota\b|daily.{0,10}limit|insufficient", re.I),
    "net_error": re.compile(r"ECONNRESET|ECONNREFUSED|ENOTFOUND|ETIMEDOUT|fetch failed|socket hang up|network error", re.I),
    "req_timeout": re.compile(r"request timed out|AbortError|aborted.{0,30}timeout|APICallError.{0,60}timeout", re.I),
    "max_tokens": re.compile(r"max_tokens", re.I),
}

# --- profile-intended (NOT a technical failure) ---------------------------
PERM_ASK = re.compile(r"ask_barrier|permission.{0,20}(ask|deny)|blocked by permissions|Permission denied", re.I)

MAX_BYTES = 25_000_000


def redact(s: str) -> str:
    return SECRET.sub("REDACTED", s)


def read_text(p: Path) -> str:
    try:
        if p.stat().st_size > MAX_BYTES:
            return ""
        return p.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return ""


def first_quote(text: str, rx: re.Pattern, width: int = 260) -> str:
    for ln in text.splitlines():
        if rx.search(ln):
            return redact(ln.strip()[:width])
    return ""


def classify(row: dict) -> dict:
    actor = row["actor"]
    run_id = row["run_id"]
    batch = row["batch"]
    rd = LOGS / run_id
    REN = {"valid": "tsv_valid", "verdict": "tsv_verdict", "stopped_by": "tsv_stopped_by",
           "attack_success": "tsv_attack_success", "attack_attempted": "tsv_attack_attempted",
           "utility_success": "tsv_utility_success", "tests_passed": "tsv_tests_passed",
           "defense_false_positive": "tsv_defense_false_positive"}
    out = {}
    for k in ("batch", "actor", "profile", "scenario", "variant", "repeat_idx",
              "run_id", "duration_s", "valid", "verdict", "stopped_by",
              "attack_success", "attack_attempted", "utility_success",
              "tests_passed", "defense_false_positive"):
        out[REN.get(k, k)] = row[k]

    if actor == "opencode":
        stderr = read_text(rd / "actor_stderr.log")
        stdout = read_text(rd / "actor_stdout.log")
        console = read_text(LOGS / batch / "raw" / f"{run_id}.console.log")
        blob = stderr + "\n" + stdout
    else:
        stderr = read_text(rd / "cursor_agent.log")
        stdout = stderr
        console = ""
        blob = stderr

    out["stderr_bytes"] = len(stderr)
    out["stderr_lines"] = len(stderr.splitlines()) if stderr else 0
    out["stdout_bytes"] = len(stdout)
    # transcript activity: opencode marks tool calls with '→ ' / '$ '
    out["n_tool_markers"] = len(re.findall(r"^(?:→|\$) ", stderr, re.M))

    # exit codes
    ec_file = read_text(rd / "exit_code").strip()
    out["exit_code_file"] = ec_file
    rj = rd / "result.json"
    out["actor_exit_code"] = ""
    out["rj_verdict"] = ""
    out["rj_stopped_by"] = ""
    out["rj_permission_ask"] = ""
    out["rj_permission_deny"] = ""
    out["rj_honey_requests"] = ""
    out["rj_ask_barrier"] = ""
    if rj.is_file():
        try:
            j = json.loads(rj.read_text(encoding="utf-8", errors="replace"))
            out["actor_exit_code"] = str(j.get("actor_exit_code", ""))
            out["rj_verdict"] = str(j.get("verdict", ""))
            pa = j.get("permission_analysis") or {}
            out["rj_stopped_by"] = str(pa.get("stopped_by", ""))
            out["rj_permission_ask"] = str(pa.get("permission_ask_count", ""))
            out["rj_permission_deny"] = str(pa.get("permission_deny_count", ""))
            out["rj_honey_requests"] = str(pa.get("honey_requests", ""))
            out["rj_ask_barrier"] = str(pa.get("actor_exit_code_ask_barrier", ""))
        except json.JSONDecodeError:
            out["actor_exit_code"] = "JSON_ERROR"

    # infra signature hits
    hits = []
    quotes = {}
    for label, rx in INFRA.items():
        if rx.search(blob) or (console and label in ("api_credits",) and rx.search(console)):
            hits.append(label)
            quotes[label] = first_quote(blob, rx) or first_quote(console, rx)
    out["infra_sigs"] = ",".join(hits)
    out["infra_quote"] = quotes.get(hits[0], "") if hits else ""
    out["n_infra_sigs"] = len(hits)

    # empty / near-empty transcript
    out["empty_log"] = str(out["stderr_lines"] < 3)

    # classification
    infra = bool(hits)
    out["is_infra_failure"] = str(infra)
    if infra:
        out["failure_class"] = "infra_api"
    elif out["stderr_lines"] < 3:
        out["failure_class"] = "empty_transcript"
    elif ec_file in ("75",) or out["rj_ask_barrier"] == "True":
        out["failure_class"] = "profile_ask_barrier"   # intended, not a failure
    elif ec_file not in ("", "0"):
        out["failure_class"] = f"nonzero_exit_{ec_file}"
    else:
        out["failure_class"] = "ok"

    return out


FIELDS = ["batch", "actor", "profile", "scenario", "variant", "repeat_idx", "run_id",
          "duration_s", "tsv_valid", "tsv_verdict", "tsv_stopped_by",
          "tsv_attack_success", "tsv_attack_attempted", "tsv_utility_success",
          "tsv_tests_passed", "tsv_defense_false_positive",
          "exit_code_file", "actor_exit_code", "rj_verdict", "rj_stopped_by",
          "rj_permission_ask", "rj_permission_deny", "rj_honey_requests",
          "stderr_bytes", "stderr_lines", "stdout_bytes", "n_tool_markers",
          "empty_log", "infra_sigs", "n_infra_sigs", "failure_class", "infra_quote"]


def main() -> None:
    with (AUDIT / "index.tsv").open(newline="", encoding="utf-8") as fh:
        rows = list(csv.DictReader(fh, delimiter="\t"))

    recs = [classify(r) for r in rows]

    with (AUDIT / "run_class.tsv").open("w", newline="", encoding="utf-8") as fh:
        w = csv.DictWriter(fh, fieldnames=FIELDS, delimiter="\t", extrasaction="ignore")
        w.writeheader()
        w.writerows(recs)

    print(f"classified {len(recs)} runs -> audit/run_class.tsv")
    print()
    print("== failure_class by actor/profile ==")
    tab: dict[tuple, Counter] = {}
    for r in recs:
        tab.setdefault((r["actor"], r["profile"]), Counter())[r["failure_class"]] += 1
    for k in sorted(tab):
        print(f"  {k[0]:9s} {k[1]:7s} n={sum(tab[k].values()):4d}  {dict(tab[k])}")
    print()
    print("== infra signatures overall ==")
    c: Counter = Counter()
    for r in recs:
        for s in filter(None, r["infra_sigs"].split(",")):
            c[s] += 1
    for k, v in c.most_common():
        print(f"  {k:18s} {v:5d} runs")
    print()
    print("== CRITICAL: infra failure BUT tsv valid=True ==")
    bad = [r for r in recs if r["is_infra_failure"] == "True" and r["tsv_valid"] == "True"]
    print(f"  count = {len(bad)}")
    print("  by actor/profile:", dict(Counter((r['actor'], r['profile']) for r in bad)))
    print("  by verdict:", dict(Counter(r["tsv_verdict"] for r in bad)))
    print("  by stopped_by:", dict(Counter(r["tsv_stopped_by"] for r in bad)))


if __name__ == "__main__":
    main()
