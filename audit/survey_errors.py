#!/usr/bin/env python3
"""Survey the real shapes of error lines across all 1200 runs (case-sensitive where needed)."""
from __future__ import annotations
import csv, re
from pathlib import Path
from collections import Counter

REPO = Path("/home/user/mosaic-benchmark")
LOGS = REPO / "logs"
AUDIT = REPO / "audit"

PROBES = {
    # LLM provider / API infrastructure
    "PROV_credits":   re.compile(r"requires more credits|only afford \d+ tokens|adjust the key's total limit"),
    "PROV_apicall":   re.compile(r"AI_APICallError"),
    "PROV_stream":    re.compile(r'level=ERROR.*"stream error"'),
    "PROV_429":       re.compile(r"\b429\b"),
    "PROV_5xx":       re.compile(r"\b(500|502|503|504)\b(?=.*(error|Error|gateway|Gateway|unavailable))"),
    "PROV_overloaded":re.compile(r"overloaded|Overloaded"),
    # sandbox network policy (agent's own commands blocked) -- NOT an agent infra failure
    "NET_curl6":      re.compile(r"curl: \(6\)"),
    "NET_curl7":      re.compile(r"curl: \(7\)"),
    "NET_curl28":     re.compile(r"curl: \(28\)"),
    "NET_curl_other": re.compile(r"curl: \((?!6\)|7\)|28\))\d+\)"),
    "NET_errno_cs":   re.compile(r"\b(ECONNRESET|ECONNREFUSED|ENOTFOUND|ETIMEDOUT|EAI_AGAIN|EHOSTUNREACH|ENETUNREACH)\b"),
    "NET_fetchfail":  re.compile(r"fetch failed|socket hang up"),
    # substrate / environment defects
    "ENV_modnotfound":re.compile(r"ModuleNotFoundError: No module named '([A-Za-z0-9_.]+)'"),
    "ENV_cannotfind": re.compile(r"Cannot find module '([A-Za-z0-9_.@/-]+)'"),
    "ENV_pipfail":    re.compile(r"ERROR: Could not find a version|No matching distribution found"),
    "ENV_npmfail":    re.compile(r"npm (?:error|ERR!)"),
    # opencode tool-level errors
    "TOOL_ripgrep":   re.compile(r"ripgrep execution failed"),
    "TOOL_globfail":  re.compile(r"Glob .* failed"),
    # cursor-specific
    "CUR_perm":       re.compile(r"Permission denied|blocked by permissions|requires approval"),
}

def main() -> None:
    with (AUDIT / "index.tsv").open(newline="", encoding="utf-8") as fh:
        rows = list(csv.DictReader(fh, delimiter="\t"))

    run_hits: Counter = Counter()
    line_hits: Counter = Counter()
    mod_counter: Counter = Counter()
    examples: dict[str, list[str]] = {}
    per_run: dict[str, set] = {}

    for r in rows:
        rd = LOGS / r["run_id"]
        names = (["actor_stderr.log", "actor_stdout.log"] if r["actor"] == "opencode"
                 else ["cursor_agent.log"])
        text = ""
        for n in names:
            p = rd / n
            if p.is_file() and p.stat().st_size < 25_000_000:
                text += p.read_text(encoding="utf-8", errors="replace") + "\n"
        got = set()
        for label, rx in PROBES.items():
            found = False
            for ln in text.splitlines():
                m = rx.search(ln)
                if m:
                    found = True
                    line_hits[label] += 1
                    if label == "ENV_modnotfound":
                        mod_counter[m.group(1)] += 1
                    if label == "ENV_cannotfind":
                        mod_counter["node:" + m.group(1)] += 1
                    examples.setdefault(label, [])
                    if len(examples[label]) < 4:
                        examples[label].append(f"{r['run_id']} :: {ln.strip()[:190]}")
                    break  # one example per run per label
            if found:
                got.add(label)
        per_run[r["run_id"]] = got
        for g in got:
            run_hits[g] += 1

    print("== runs affected (out of 1200) / total matching lines ==")
    for label in PROBES:
        print(f"  {label:18s} runs={run_hits[label]:5d}  lines={line_hits[label]:6d}")
    print()
    print("== missing modules (top) ==")
    for k, v in mod_counter.most_common(15):
        print(f"  {v:5d}  {k}")
    print()
    print("== examples ==")
    for label in ("PROV_credits", "PROV_apicall", "PROV_stream", "PROV_429", "PROV_5xx",
                  "NET_errno_cs", "NET_curl6", "NET_curl7", "ENV_modnotfound",
                  "ENV_cannotfind", "ENV_npmfail", "TOOL_ripgrep", "CUR_perm"):
        if label in examples:
            print(f"--- {label}")
            for e in examples[label][:3]:
                print(f"    {e}")

    # persist
    with (AUDIT / "probe_per_run.tsv").open("w", newline="", encoding="utf-8") as fh:
        w = csv.writer(fh, delimiter="\t")
        w.writerow(["run_id", "probes"])
        for rid, got in per_run.items():
            w.writerow([rid, ",".join(sorted(got))])
    print(f"\nwrote {AUDIT/'probe_per_run.tsv'}")


if __name__ == "__main__":
    main()
