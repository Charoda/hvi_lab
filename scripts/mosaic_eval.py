#!/usr/bin/env python3
"""End-to-end evaluation runner for MOSAIC.

Given an agent (``--model``), runs the canonical chain set (or a sampled
subset via ``--limit``) and produces a JSONL output that mirrors the
``Results`` sheet of ``mosaic-bench.xlsx``: one row per (chain, model)
trial with verdict + metadata. Prints an ASR summary at the end.

The script intentionally stays thin — it calls ``mosaic run`` per chain
so that any agent backend the CLI knows about (codex, claude-sonnet-46,
claude-opus, opencode:..., etc.) is supported without changes here.

Usage:
    python scripts/mosaic_eval.py --model codex --output results.jsonl
    python scripts/mosaic_eval.py --model codex --limit 10 --output smoke.jsonl
    python scripts/mosaic_eval.py --model claude-sonnet-46 \\
        --chains express_mark_modified,swag_orm_toggle --output mini.jsonl
"""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
import time
from collections import Counter
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent

# Reuse the dataset helpers so chain order matches the workbook.
sys.path.insert(0, str(REPO_ROOT))
from mosaic.dataset import load_dataset_rows  # noqa: E402

VERDICT_RE = re.compile(r"\bverdict\s*[:=]\s*([A-Z_]+)\b", re.IGNORECASE)


def _select_chains(rows, *, limit: int | None, picks: list[str] | None) -> list[dict]:
    pool = [{"chain_id": r.chain_id, "app": r.app, "cwe": r.cwe} for r in rows]
    if picks:
        wanted = {p.strip() for p in picks if p.strip()}
        return [c for c in pool if c["chain_id"] in wanted]
    if limit:
        return pool[:limit]
    return pool


def _run_one_chain(chain_id: str, model: str, stage_timeout: int) -> dict:
    """Run a single chain and return the verdict + raw output snippet."""
    cmd = [
        "mosaic", "run",
        "-c", chain_id,
        "-m", model,
        "--reuse-container",
        "--stage-timeout", str(stage_timeout),
    ]
    start = time.time()
    completed = subprocess.run(cmd, capture_output=True, text=True, timeout=stage_timeout * 4 + 600)
    duration_s = round(time.time() - start, 2)
    output = (completed.stdout or "") + "\n" + (completed.stderr or "")
    match = VERDICT_RE.search(output)
    verdict = (match.group(1).upper() if match else "UNKNOWN").strip()
    if verdict == "UNKNOWN" and completed.returncode != 0:
        verdict = "INVALID"
    return {"verdict": verdict, "duration_s": duration_s, "return_code": completed.returncode}


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--model", required=True, help="Agent identifier passed to `mosaic run -m`.")
    p.add_argument("--output", required=True, help="JSONL output path (append-friendly).")
    p.add_argument("--limit", type=int, default=None, help="Run only the first N chains (smoke test).")
    p.add_argument("--chains", default=None, help="Comma-separated explicit chain IDs to run.")
    p.add_argument("--stage-timeout", type=int, default=600, help="Per-stage agent timeout in seconds.")
    args = p.parse_args()

    rows = load_dataset_rows()
    picks = args.chains.split(",") if args.chains else None
    selected = _select_chains(rows, limit=args.limit, picks=picks)
    if not selected:
        print("No chains selected.", file=sys.stderr)
        return 2

    print(f"[mosaic_eval] running {len(selected)} chain(s) with model={args.model}", flush=True)
    out_path = Path(args.output)
    out_path.parent.mkdir(parents=True, exist_ok=True)
    verdicts: Counter[str] = Counter()
    with out_path.open("a", encoding="utf-8") as fh:
        for idx, chain in enumerate(selected, 1):
            result = _run_one_chain(chain["chain_id"], args.model, args.stage_timeout)
            row = {
                "chain_id": chain["chain_id"],
                "app": chain["app"],
                "cwe": chain["cwe"],
                "model": args.model,
                "verdict": result["verdict"],
                "duration_s": result["duration_s"],
                "timestamp": time.strftime("%Y-%m-%dT%H:%M:%S"),
            }
            fh.write(json.dumps(row) + "\n")
            fh.flush()
            verdicts[result["verdict"]] += 1
            print(f"[{idx}/{len(selected)}] {chain['chain_id']:40s} -> {result['verdict']} ({result['duration_s']}s)", flush=True)

    total = sum(verdicts.values())
    vuln = verdicts.get("VULNERABLE", 0)
    secure = verdicts.get("SECURE", 0)
    asr_denom = vuln + secure  # excludes BROKEN/INVALID/UNKNOWN
    print()
    print(f"=== mosaic_eval summary (model={args.model}) ===")
    for v, n in verdicts.most_common():
        print(f"  {v:12s} {n:4d}")
    if asr_denom:
        print(f"  ASR (VULN / VULN+SECURE) = {vuln}/{asr_denom} = {vuln/asr_denom*100:.1f}%")
    print(f"  Output: {out_path}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
