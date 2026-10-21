#!/usr/bin/env python3
"""Audit step 0: build a flat index of every TSV row across the 6 n5 batches.

Read-only w.r.t. logs/. Writes audit/index.tsv.
"""
from __future__ import annotations

import csv
import json
from pathlib import Path

REPO = Path("/home/user/mosaic-benchmark")
LOGS = REPO / "logs"
AUDIT = REPO / "audit"

BATCHES = [
    ("cursor", "off", LOGS / "cursor/cursor-b01-b20-n5-off"),
    ("cursor", "normal", LOGS / "cursor/cursor-b01-b20-n5-normal"),
    ("cursor", "strict", LOGS / "cursor/cursor-b01-b20-n5-strict"),
    ("opencode", "off", LOGS / "opencode/opencode-b01-b20-n5-off"),
    ("opencode", "normal", LOGS / "opencode/opencode-b01-b20-n5-normal"),
    ("opencode", "strict", LOGS / "opencode/opencode-b01-b20-n5-strict"),
]

FIELDS = [
    "batch", "actor", "profile_col", "tsv", "scenario", "variant", "profile",
    "repeat_idx", "run_id", "model", "verdict", "valid", "attack_attempted",
    "attack_success", "utility_success", "tests_passed",
    "permission_blocked_attack", "permission_blocked_utility",
    "defense_false_positive", "stopped_by", "duration_s", "evidence", "notes",
    "run_dir", "run_dir_exists",
]


def run_dir_for(actor: str, batch_dir: Path, run_id: str) -> Path:
    if actor == "cursor":
        link = batch_dir / "runs" / run_id
        if link.exists():
            return link.resolve()
        return LOGS / run_id
    return LOGS / run_id


def main() -> None:
    rows: list[dict] = []
    for actor, profile_col, batch_dir in BATCHES:
        if not batch_dir.is_dir():
            print(f"MISSING BATCH DIR: {batch_dir}")
            continue
        for tsv_name in ("malicious.tsv", "benign.tsv"):
            p = batch_dir / tsv_name
            if not p.is_file():
                print(f"MISSING TSV: {p}")
                continue
            with p.open(newline="", encoding="utf-8") as fh:
                for rec in csv.DictReader(fh, delimiter="\t"):
                    run_id = (rec.get("run_id") or "").strip()
                    rd = run_dir_for(actor, batch_dir, run_id)
                    rows.append({
                        "batch": batch_dir.name,
                        "actor": actor,
                        "profile_col": profile_col,
                        "tsv": tsv_name,
                        "scenario": rec.get("scenario", ""),
                        "variant": rec.get("variant", ""),
                        "profile": rec.get("profile", ""),
                        "repeat_idx": rec.get("repeat_idx", ""),
                        "run_id": run_id,
                        "model": rec.get("model", ""),
                        "verdict": rec.get("verdict", ""),
                        "valid": rec.get("valid", ""),
                        "attack_attempted": rec.get("attack_attempted", ""),
                        "attack_success": rec.get("attack_success", ""),
                        "utility_success": rec.get("utility_success", ""),
                        "tests_passed": rec.get("tests_passed", ""),
                        "permission_blocked_attack": rec.get("permission_blocked_attack", ""),
                        "permission_blocked_utility": rec.get("permission_blocked_utility", ""),
                        "defense_false_positive": rec.get("defense_false_positive", ""),
                        "stopped_by": rec.get("stopped_by", ""),
                        "duration_s": rec.get("duration_s", ""),
                        "evidence": rec.get("evidence", "").replace("\t", " ").replace("\n", " "),
                        "notes": rec.get("notes", "").replace("\t", " ").replace("\n", " "),
                        "run_dir": str(rd),
                        "run_dir_exists": str(rd.is_dir()),
                    })

    AUDIT.mkdir(exist_ok=True)
    out = AUDIT / "index.tsv"
    with out.open("w", newline="", encoding="utf-8") as fh:
        w = csv.DictWriter(fh, fieldnames=FIELDS, delimiter="\t", extrasaction="ignore")
        w.writeheader()
        w.writerows(rows)

    print(f"wrote {out} rows={len(rows)}")
    from collections import Counter
    print("by batch/tsv:", dict(Counter((r["batch"], r["tsv"]) for r in rows)))
    print("run_dir_exists:", dict(Counter(r["run_dir_exists"] for r in rows)))
    print("verdict:", dict(Counter(r["verdict"] for r in rows)))
    print("valid:", dict(Counter(r["valid"] for r in rows)))
    print("stopped_by:", dict(Counter(r["stopped_by"] for r in rows)))


if __name__ == "__main__":
    main()
