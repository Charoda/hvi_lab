#!/usr/bin/env python3
"""Audit step 1: scan every run's agent/API logs for technical-failure signatures.

Read-only w.r.t. logs/. Writes audit/failures_raw.tsv and audit/failures_summary.txt.
"""
from __future__ import annotations

import csv
import re
import statistics
from collections import Counter, defaultdict
from pathlib import Path

REPO = Path("/home/user/mosaic-benchmark")
LOGS = REPO / "logs"
AUDIT = REPO / "audit"

# --- signatures -----------------------------------------------------------
# Each: (label, compiled regex). Applied to text logs only (never strace/inotify).
SIGS = [
    ("http_402", re.compile(r"\b402\b")),
    ("http_429", re.compile(r"\b429\b")),
    ("http_500", re.compile(r"\b500\b")),
    ("http_502", re.compile(r"\b502\b")),
    ("http_503", re.compile(r"\b503\b")),
    ("http_504", re.compile(r"\b504\b")),
    ("credits", re.compile(r"credit", re.I)),
    ("max_tokens", re.compile(r"max_tokens", re.I)),
    ("rate_limit", re.compile(r"rate.?limit", re.I)),
    ("quota", re.compile(r"quota", re.I)),
    ("insufficient", re.compile(r"insufficient", re.I)),
    ("timeout", re.compile(r"\btimeout\b|timed out", re.I)),
    ("connection", re.compile(r"\bconnection\b", re.I)),
    ("econnreset", re.compile(r"ECONNRESET|ECONNREFUSED|ENOTFOUND|ETIMEDOUT", re.I)),
]

MAX_BYTES = 20_000_000  # skip anything larger (strace/inotify are 2-30 MB)
MAX_LINE = 400


def log_files(actor: str, batch: str, run_id: str) -> list[tuple[str, Path]]:
    """(kind, path) pairs for this run's *agent/API* logs."""
    out: list[tuple[str, Path]] = []
    rd = LOGS / run_id
    if actor == "opencode":
        for name in ("actor_stdout.log", "actor_stderr.log", "opencode_raw.log",
                     "result.json", "poc_container.log", "network_setup.log",
                     "honey_listener.log", "exit_code"):
            p = rd / name
            if p.is_file():
                out.append((name, p))
        console = LOGS / batch / "raw" / f"{run_id}.console.log"
        if console.is_file():
            out.append(("console.log", console))
    else:  # cursor
        for name in ("cursor_agent.log", "honey_listener.log"):
            p = rd / name
            if p.is_file():
                out.append((name, p))
    return out


def scan_text(path: Path) -> tuple[list[tuple[str, int, str]], int, int]:
    """Return (matches, n_lines, n_bytes)."""
    try:
        size = path.stat().st_size
    except OSError:
        return [], 0, 0
    if size > MAX_BYTES:
        return [], -1, size  # -1 => skipped
    try:
        data = path.read_text(encoding="utf-8", errors="replace")
    except OSError:
        return [], -1, size
    lines = data.splitlines()
    hits: list[tuple[str, int, str]] = []
    for label, rx in SIGS:
        for i, ln in enumerate(lines, 1):
            if rx.search(ln):
                hits.append((label, i, ln.strip()[:MAX_LINE]))
    return hits, len(lines), size


def main() -> None:
    with (AUDIT / "index.tsv").open(newline="", encoding="utf-8") as fh:
        rows = list(csv.DictReader(fh, delimiter="\t"))

    per_run: list[dict] = []
    all_hits: list[dict] = []
    for r in rows:
        actor, batch, run_id = r["actor"], r["batch"], r["run_id"]
        files = log_files(actor, batch, run_id)
        sig_counter: Counter[str] = Counter()
        agent_lines = -999
        agent_bytes = 0
        missing: list[str] = []
        for kind, p in files:
            hits, nlines, nbytes = scan_text(p)
            if nlines == -1:
                continue
            if kind in ("actor_stdout.log", "cursor_agent.log"):
                agent_lines, agent_bytes = nlines, nbytes
            for label, lineno, text in hits:
                sig_counter[label] += 1
                all_hits.append({
                    "batch": batch, "actor": actor, "profile": r["profile"],
                    "scenario": r["scenario"], "variant": r["variant"],
                    "repeat_idx": r["repeat_idx"], "run_id": run_id,
                    "file": str(p.relative_to(REPO)), "kind": kind,
                    "sig": label, "line_no": lineno, "quote": text,
                    "tsv_valid": r["valid"], "tsv_verdict": r["verdict"],
                    "tsv_stopped_by": r["stopped_by"],
                    "tsv_attack_success": r["attack_success"],
                    "duration_s": r["duration_s"],
                })
        if actor == "opencode" and not (LOGS / run_id / "actor_stdout.log").is_file():
            missing.append("actor_stdout.log")
        if actor == "cursor" and not (LOGS / run_id / "cursor_agent.log").is_file():
            missing.append("cursor_agent.log")
        per_run.append({
            "batch": batch, "actor": actor, "profile": r["profile"],
            "scenario": r["scenario"], "variant": r["variant"],
            "repeat_idx": r["repeat_idx"], "run_id": run_id,
            "tsv_valid": r["valid"], "tsv_verdict": r["verdict"],
            "tsv_stopped_by": r["stopped_by"],
            "tsv_attack_success": r["attack_success"],
            "tsv_attack_attempted": r["attack_attempted"],
            "tsv_utility_success": r["utility_success"],
            "duration_s": r["duration_s"],
            "agent_log": "cursor_agent.log" if actor == "cursor" else "actor_stdout.log",
            "agent_log_lines": agent_lines, "agent_log_bytes": agent_bytes,
            "n_files_scanned": len(files),
            "missing_agent_log": ",".join(missing),
            "sigs": ",".join(f"{k}:{v}" for k, v in sorted(sig_counter.items())),
            "n_sig_hits": sum(sig_counter.values()),
        })

    AUDIT.mkdir(exist_ok=True)
    with (AUDIT / "failures_raw.tsv").open("w", newline="", encoding="utf-8") as fh:
        w = csv.DictWriter(fh, fieldnames=list(all_hits[0].keys()) if all_hits else
                           ["batch"], delimiter="\t")
        w.writeheader()
        w.writerows(all_hits)

    with (AUDIT / "per_run_scan.tsv").open("w", newline="", encoding="utf-8") as fh:
        w = csv.DictWriter(fh, fieldnames=list(per_run[0].keys()), delimiter="\t")
        w.writeheader()
        w.writerows(per_run)

    # --- summary ---------------------------------------------------------
    lines: list[str] = []
    lines.append(f"rows scanned: {len(per_run)}   signature hits: {len(all_hits)}")
    lines.append(f"runs with >=1 hit: {sum(1 for p in per_run if p['n_sig_hits'])}")
    lines.append("")
    lines.append("== hits by signature ==")
    for k, v in Counter(h["sig"] for h in all_hits).most_common():
        lines.append(f"  {k:14s} {v:6d} hits in {len(set(h['run_id'] for h in all_hits if h['sig']==k)):4d} runs")
    lines.append("")
    lines.append("== agent-log line counts (<3 lines = near-empty) ==")
    for actor in ("cursor", "opencode"):
        sub = [p for p in per_run if p["actor"] == actor]
        cnt = Counter(p["agent_log_lines"] for p in sub)
        near_empty = [p for p in sub if 0 <= p["agent_log_lines"] < 3]
        lines.append(f"  {actor}: n={len(sub)} near_empty(<3 lines)={len(near_empty)} "
                     f"missing_log={sum(1 for p in sub if p['missing_agent_log'])}")
        lines.append(f"    line-count histogram (top): {cnt.most_common(12)}")
    lines.append("")
    lines.append("== duration_s distribution by actor/profile ==")
    grp: dict[tuple, list[float]] = defaultdict(list)
    for p in per_run:
        try:
            grp[(p["actor"], p["profile"])].append(float(p["duration_s"]))
        except ValueError:
            pass
    for k in sorted(grp):
        v = sorted(grp[k])
        q = statistics.quantiles(v, n=20) if len(v) >= 20 else []
        lines.append(f"  {k[0]:9s} {k[1]:7s} n={len(v):4d} min={v[0]:8.1f} p5={q[0] if q else v[0]:8.1f} "
                     f"med={statistics.median(v):8.1f} p95={q[-1] if q else v[-1]:8.1f} max={v[-1]:8.1f}")
    lines.append("")
    lines.append("== shortest 25 runs overall (duration_s) ==")
    def dkey(p):
        try:
            return float(p["duration_s"])
        except ValueError:
            return 1e9
    for p in sorted(per_run, key=dkey)[:25]:
        lines.append(f"  {p['duration_s']:>8s}s {p['actor']:9s} {p['profile']:7s} "
                     f"{p['scenario']:26s} {p['variant']:10s} idx={p['repeat_idx']} "
                     f"lines={p['agent_log_lines']:>5} {p['verdict'] if 'verdict' in p else p['tsv_verdict']} "
                     f"stopped_by={p['tsv_stopped_by']!r} {p['run_id']}")
    (AUDIT / "failures_summary.txt").write_text("\n".join(lines), encoding="utf-8")
    print("\n".join(lines))


if __name__ == "__main__":
    main()
