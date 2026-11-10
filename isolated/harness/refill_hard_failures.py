#!/usr/bin/env python3
"""Refill task1 hard-failure slots into existing harness batches.

- Backs up malicious.tsv / benign.tsv → *.pre_refill (once)
- Clears progress + removes HF rows for each slot, then runs harness for that
  scenario only (SKIP_DONE skips the rest)
- INVALID_RETRIES=0 (no retry burn)
- Stops immediately on api_provider_credits / credit exhaustion (paid tier)
- Optional --prefer-free: start on Nemotron :free, switch to paid on free limits
- --resume: skip slots already refilled; keep prior status.results

Usage:
  python isolated/harness/refill_hard_failures.py [--dry-run] [--from-idx N]
      [--resume] [--prefer-free]
"""
from __future__ import annotations

import argparse
import csv
import json
import os
import re
import shutil
import subprocess
import sys
import time
import urllib.request
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
HF_TSV = REPO / "audit" / "task1_hard_failures.tsv"
STATUS = REPO / "logs" / "refill_20261102" / "status.json"
LOG = REPO / "logs" / "refill_20261102" / "refill.log"

BATCH_MAP = {
    ("opencode", "off"): "opencode/opencode-b01-b20-n5-off",
    ("opencode", "normal"): "opencode/opencode-b01-b20-n5-normal",
    ("opencode", "strict"): "opencode/opencode-b01-b20-n5-strict",
    ("cursor", "off"): "cursor/cursor-b01-b20-n5-off",
    ("cursor", "normal"): "cursor/cursor-b01-b20-n5-normal",
    ("cursor", "strict"): "cursor/cursor-b01-b20-n5-strict",
}

MODEL_FREE = "openrouter/nvidia/nemotron-3-ultra-550b-a55b:free"
MODEL_PAID = "openrouter/nvidia/nemotron-3-ultra-550b-a55b"

CREDIT_RE = re.compile(
    r"credit|credits|api_provider_credits|would exceed your available|requires more credits|"
    r"only afford \d+ tokens",
    re.I,
)
# Free-tier / free-provider problems → switch to paid (not a hard stop).
FREE_LIMIT_RE = re.compile(
    r"free-models-per-day|Rate limit exceeded|"
    r"(?:HTTP\/\d\.?\d?\s*|status[=:\s]|error[=:\s]|code[=:\s])429\b|"
    r"\b429\s+Too Many Requests\b|"
    r"AI_APICallError|"
    r"error code:\s*502|\b502\b|\b503\b|\b504\b|"
    r"Provider Error|No endpoints found",
    re.I,
)


def log(msg: str) -> None:
    STATUS.parent.mkdir(parents=True, exist_ok=True)
    line = f"[{time.strftime('%Y-%m-%d %H:%M:%S')}] {msg}"
    print(line, flush=True)
    with LOG.open("a") as f:
        f.write(line + "\n")


def write_status(d: dict) -> None:
    STATUS.parent.mkdir(parents=True, exist_ok=True)
    STATUS.write_text(json.dumps(d, indent=2, ensure_ascii=False) + "\n")


def openrouter_remaining() -> dict:
    key = os.environ.get("OPENROUTER_API_KEY", "")
    if not key:
        env = (REPO / ".env").read_text()
        m = re.search(r"^OPENROUTER_API_KEY=(.+)$", env, re.M)
        key = (m.group(1).strip().strip('"') if m else "")
    out = {"key_remaining": None, "credits_remaining": None}
    try:
        req = urllib.request.Request(
            "https://openrouter.ai/api/v1/key",
            headers={"Authorization": f"Bearer {key}"},
        )
        with urllib.request.urlopen(req, timeout=20) as resp:
            data = json.loads(resp.read().decode())["data"]
            out["key_remaining"] = data.get("limit_remaining")
            out["usage"] = data.get("usage")
    except Exception as e:
        out["key_err"] = str(e)
    try:
        req = urllib.request.Request(
            "https://openrouter.ai/api/v1/credits",
            headers={"Authorization": f"Bearer {key}"},
        )
        with urllib.request.urlopen(req, timeout=20) as resp:
            data = json.loads(resp.read().decode())["data"]
            out["credits_remaining"] = float(data["total_credits"]) - float(
                data["total_usage"]
            )
            out["total_credits"] = data["total_credits"]
            out["total_usage"] = data["total_usage"]
    except Exception as e:
        out["credits_err"] = str(e)
    return out


def load_hf() -> list[dict]:
    rows = list(csv.DictReader(HF_TSV.open(), delimiter="\t"))
    rows.sort(
        key=lambda r: (
            0 if r["actor"] == "opencode" else 1,
            r["profile"],
            r["scenario"],
            r["variant"],
            int(r["repeat_idx"]),
        )
    )
    return rows


def batch_dir(actor: str, profile: str) -> Path:
    return REPO / "logs" / BATCH_MAP[(actor, profile)]


def ensure_pre_refill(bdir: Path) -> None:
    for name in ("malicious.tsv", "benign.tsv"):
        src = bdir / name
        dst = bdir / f"{name}.pre_refill"
        if src.is_file() and not dst.is_file():
            shutil.copy2(src, dst)
            log(f"backup {dst}")


def tsv_path(bdir: Path, variant: str) -> Path:
    return bdir / ("benign.tsv" if variant == "benign" else "malicious.tsv")


def progress_path(bdir: Path) -> Path:
    return bdir / "progress.tsv"


def chain_name(scenario: str, variant: str) -> str:
    return f"{scenario}_benign" if variant == "benign" else scenario


def remove_progress_slot(bdir: Path, scenario: str, variant: str, profile: str, idx: int) -> None:
    pp = progress_path(bdir)
    chain = chain_name(scenario, variant)
    rows = pp.read_text().splitlines()
    hdr, body = rows[0], rows[1:]
    keep = []
    for line in body:
        parts = line.split("\t")
        if len(parts) >= 5 and parts[0] == chain and parts[1] == variant and parts[2] == profile and parts[3] == str(idx):
            continue
        keep.append(line)
    pp.write_text(hdr + "\n" + ("\n".join(keep) + ("\n" if keep else "")))


def remove_tsv_row(bdir: Path, scenario: str, variant: str, profile: str, idx: int, run_id: str) -> None:
    tp = tsv_path(bdir, variant)
    with tp.open() as f:
        reader = csv.DictReader(f, delimiter="\t")
        fieldnames = list(reader.fieldnames or [])
        rows = list(reader)
    new_rows = []
    for r in rows:
        if r.get("run_id") == run_id:
            continue
        if (
            r.get("scenario") == scenario
            and r.get("variant") == variant
            and r.get("profile") == profile
            and str(r.get("repeat_idx")) == str(idx)
        ):
            continue
        new_rows.append(r)
    with tp.open("w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=fieldnames, delimiter="\t", lineterminator="\n")
        w.writeheader()
        for r in new_rows:
            w.writerow(r)


def latest_tsv_row(bdir: Path, scenario: str, variant: str, profile: str, idx: int) -> dict | None:
    tp = tsv_path(bdir, variant)
    if not tp.is_file():
        return None
    matches = []
    with tp.open() as f:
        for r in csv.DictReader(f, delimiter="\t"):
            if (
                r.get("scenario") == scenario
                and r.get("variant") == variant
                and r.get("profile") == profile
                and str(r.get("repeat_idx")) == str(idx)
            ):
                matches.append(r)
    return matches[-1] if matches else None


def _slot_log_blob(row: dict | None, console: Path | None = None) -> str:
    parts: list[str] = []
    if row:
        parts.append(
            " ".join(
                str(row.get(k, ""))
                for k in ("verdict", "evidence", "notes", "valid", "stopped_by")
            )
        )
        run_id = row.get("run_id") or ""
        log_dir = REPO / "logs" / run_id
        if log_dir.is_dir():
            for name in ("actor_stderr.log", "opencode_raw.log", "cursor_agent.log", "agent_stdout.log"):
                p = log_dir / name
                if p.is_file():
                    parts.append(p.read_text(errors="replace")[:120000])
    if console and console.is_file():
        parts.append(console.read_text(errors="replace")[:80000])
    return "\n".join(parts)


def is_credit_failure(row: dict | None, bdir: Path, console: Path | None = None) -> bool:
    blob = _slot_log_blob(row, console)
    if not blob:
        return False
    if CREDIT_RE.search(blob):
        if row and str(row.get("verdict")).upper() == "INVALID":
            return True
        if row and str(row.get("valid")).lower() in ("false", "0"):
            return True
        # Short false-SECURE (~15s) after credits die — treat as credit fail.
        try:
            dur = float(row.get("duration_s") or 0) if row else 0
        except ValueError:
            dur = 0
        if row and dur and dur < 45 and CREDIT_RE.search(blob):
            return True
    return bool(CREDIT_RE.search(blob) and row and str(row.get("verdict")).upper() == "INVALID")


def is_free_limit_failure(row: dict | None, console: Path | None = None) -> bool:
    blob = _slot_log_blob(row, console)
    if not blob:
        # Empty / missing row after a free attempt often means provider flake.
        return row is None
    if CREDIT_RE.search(blob) and not FREE_LIMIT_RE.search(blob):
        return False
    if FREE_LIMIT_RE.search(blob):
        return True
    if row:
        try:
            dur = float(row.get("duration_s") or 0)
        except ValueError:
            dur = 0
        if dur and dur < 45 and str(row.get("verdict")).upper() in ("SECURE", "INVALID", ""):
            # Classic free-tier / provider short abort.
            return True
    return False


def slot_key(slot: dict) -> tuple:
    return (
        slot["actor"],
        slot["profile"],
        slot["scenario"],
        slot["variant"],
        int(slot["repeat_idx"]),
    )


def already_refilled(slot: dict, prior_results: list[dict]) -> bool:
    """True if this HF slot already has a replacement run (status or batch TSV)."""
    key = slot_key(slot)
    for r in prior_results:
        if (
            r.get("actor") == key[0]
            and r.get("profile") == key[1]
            and r.get("scenario") == key[2]
            and r.get("variant") == key[3]
            and int(r.get("repeat_idx", -1)) == key[4]
            and r.get("new_run_id")
            and not r.get("error")
        ):
            return True
    bdir = batch_dir(slot["actor"], slot["profile"])
    row = latest_tsv_row(
        bdir, slot["scenario"], slot["variant"], slot["profile"], int(slot["repeat_idx"])
    )
    if not row:
        return False
    if row.get("run_id") == slot.get("run_id"):
        return False  # still the original hard-failure row
    try:
        dur = float(row.get("duration_s") or 0)
    except ValueError:
        dur = 0
    # Accept any non-old replacement that looks like a real trial.
    if dur >= 45 or str(row.get("valid")).lower() in ("true", "1"):
        return True
    return False


def run_slot(slot: dict, model: str | None = None) -> dict:
    actor = slot["actor"]
    profile = slot["profile"]
    scenario = slot["scenario"]
    variant = slot["variant"]
    idx = int(slot["repeat_idx"])
    old_run = slot["run_id"]
    bdir = batch_dir(actor, profile)
    batch_name = BATCH_MAP[(actor, profile)]

    ensure_pre_refill(bdir)
    remove_tsv_row(bdir, scenario, variant, profile, idx, old_run)
    remove_progress_slot(bdir, scenario, variant, profile, idx)

    env = os.environ.copy()
    # Load .env
    for line in (REPO / ".env").read_text().splitlines():
        if not line or line.startswith("#") or "=" not in line:
            continue
        k, _, v = line.partition("=")
        env.setdefault(k.strip(), v.strip().strip('"'))
    env["INVALID_RETRIES"] = "0"
    env["SKIP_DONE"] = "1"
    env["NETWORK"] = "allowlist"
    env["TIMEOUT"] = "2400"

    cmd = [
        str(REPO / "isolated" / "harness" / "run.sh"),
        "--actor",
        actor,
        "--profile",
        profile,
        "--trials",
        "5",
        "--scenarios",
        scenario,
        "--batch",
        batch_name,
        "--network",
        "allowlist",
        "--timeout",
        "2400",
    ]
    if actor == "opencode":
        use_model = model or env.get("MOSAIC_OPENCODE_MODEL", MODEL_PAID)
        env["MOSAIC_OPENCODE_MODEL"] = use_model
        cmd.extend(["--model", use_model])
    else:
        use_model = "auto"
        cmd.extend(["--model", "auto"])

    # Preserve original run_config (harness overwrites it each invocation).
    rc = bdir / "run_config.json"
    rc_bak = bdir / "run_config.json.pre_refill"
    if rc.is_file() and not rc_bak.is_file():
        shutil.copy2(rc, rc_bak)

    log(f"RUN {actor}/{profile}/{scenario}/{variant}#{idx} model={use_model} (was {old_run})")
    t0 = time.time()
    proc = subprocess.run(
        cmd,
        cwd=str(REPO),
        env=env,
        capture_output=True,
        text=True,
    )
    dt = time.time() - t0
    if rc_bak.is_file():
        shutil.copy2(rc_bak, rc)
    console = STATUS.parent / f"slot_{actor}_{profile}_{scenario}_{variant}_{idx}.console.log"
    console.write_text((proc.stdout or "") + "\n--- STDERR ---\n" + (proc.stderr or ""))
    row = latest_tsv_row(bdir, scenario, variant, profile, idx)
    result = {
        "actor": actor,
        "profile": profile,
        "scenario": scenario,
        "variant": variant,
        "repeat_idx": idx,
        "old_run_id": old_run,
        "new_run_id": (row or {}).get("run_id"),
        "verdict": (row or {}).get("verdict"),
        "valid": (row or {}).get("valid"),
        "attack_success": (row or {}).get("attack_success"),
        "model": use_model,
        "rc": proc.returncode,
        "duration_s": round(dt, 1),
        "console": str(console),
    }
    log(
        f"DONE #{idx} verdict={result['verdict']} valid={result['valid']} "
        f"run={result['new_run_id']} model={use_model} rc={proc.returncode} {dt:.0f}s"
    )
    if not result.get("new_run_id"):
        raise RuntimeError(
            f"no TSV row after harness for {scenario}/{variant}#{idx}; "
            f"see {console}"
        )
    return result


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--from-idx", type=int, default=0, help="0-based index into HF list")
    ap.add_argument("--only-cursor", action="store_true")
    ap.add_argument("--only-opencode", action="store_true")
    ap.add_argument(
        "--resume",
        action="store_true",
        help="Skip slots already refilled; keep prior status.results",
    )
    ap.add_argument(
        "--prefer-free",
        action="store_true",
        help="OpenCode: try :free first, switch to paid on free limits/5xx",
    )
    args = ap.parse_args()

    # Ensure .env loaded for this process
    for line in (REPO / ".env").read_text().splitlines():
        if not line or line.startswith("#") or "=" not in line:
            continue
        k, _, v = line.partition("=")
        os.environ.setdefault(k.strip(), v.strip().strip('"'))

    prior: list[dict] = []
    if args.resume and STATUS.is_file():
        try:
            prior = list(json.loads(STATUS.read_text()).get("results") or [])
        except Exception:
            prior = []

    # Also seed prior from batch TSV replacements so resume sees b07/b15 early wins
    # that never landed in status.results.
    all_hf = load_hf()
    for s in all_hf:
        if already_refilled(s, prior):
            key = slot_key(s)
            if not any(
                r.get("actor") == key[0]
                and r.get("profile") == key[1]
                and r.get("scenario") == key[2]
                and r.get("variant") == key[3]
                and int(r.get("repeat_idx", -1)) == key[4]
                and r.get("new_run_id")
                for r in prior
            ):
                row = latest_tsv_row(
                    batch_dir(s["actor"], s["profile"]),
                    s["scenario"],
                    s["variant"],
                    s["profile"],
                    int(s["repeat_idx"]),
                )
                prior.append(
                    {
                        "actor": s["actor"],
                        "profile": s["profile"],
                        "scenario": s["scenario"],
                        "variant": s["variant"],
                        "repeat_idx": int(s["repeat_idx"]),
                        "old_run_id": s["run_id"],
                        "new_run_id": (row or {}).get("run_id"),
                        "verdict": (row or {}).get("verdict"),
                        "valid": (row or {}).get("valid"),
                        "attack_success": (row or {}).get("attack_success"),
                        "recovered_from_tsv": True,
                    }
                )

    slots = all_hf
    if args.only_cursor:
        slots = [s for s in slots if s["actor"] == "cursor"]
    if args.only_opencode:
        slots = [s for s in slots if s["actor"] == "opencode"]
    slots = slots[args.from_idx :]
    if args.resume:
        before = len(slots)
        slots = [s for s in slots if not already_refilled(s, prior)]
        log(f"resume: skip {before - len(slots)} already-refilled; queue {len(slots)}")

    model_tier = "free" if args.prefer_free else "paid"
    current_oc_model = MODEL_FREE if args.prefer_free else (
        os.environ.get("MOSAIC_OPENCODE_MODEL") or MODEL_PAID
    )
    if args.prefer_free:
        log(f"prefer-free: start model={current_oc_model}")

    bal = openrouter_remaining()
    log(f"start refill n={len(slots)} balance={bal} tier={model_tier}")
    results: list[dict] = list(prior) if args.resume else []
    write_status(
        {
            "phase": "running",
            "total": len(slots) + len(results),
            "done": len(results),
            "remaining": len(slots),
            "results": results,
            "stopped_reason": None,
            "balance_start": bal,
            "model_tier": model_tier,
            "model": current_oc_model,
            "resume": bool(args.resume),
            "prefer_free": bool(args.prefer_free),
        }
    )

    if args.dry_run:
        for i, s in enumerate(slots):
            log(f"DRY {i}: {s['actor']}/{s['profile']}/{s['scenario']}/{s['variant']}#{s['repeat_idx']}")
        return 0

    if not slots:
        write_status(
            {
                "phase": "complete",
                "total": len(results),
                "done": len(results),
                "remaining": 0,
                "results": results,
                "stopped_reason": None,
                "balance_end": openrouter_remaining(),
                "model_tier": model_tier,
                "model": current_oc_model,
            }
        )
        log("ALL SLOTS COMPLETE (nothing queued)")
        return 0

    for i, slot in enumerate(slots):
        bal = openrouter_remaining()
        rem = bal.get("credits_remaining")
        # Only enforce credit floor on paid tier (free does not burn key credits the same way).
        if model_tier == "paid" and rem is not None and rem < 0.05:
            log(f"STOP pre-slot: credits_remaining={rem}")
            write_status(
                {
                    "phase": "stopped_credits",
                    "total": len(results) + len(slots) - i,
                    "done": len(results),
                    "remaining": len(slots) - i,
                    "remaining_slots": [
                        f"{s['actor']}/{s['profile']}/{s['scenario']}/{s['variant']}#{s['repeat_idx']}"
                        for s in slots[i:]
                    ],
                    "results": results,
                    "stopped_reason": "credits_low_before_slot",
                    "balance": bal,
                    "model_tier": model_tier,
                    "model": current_oc_model,
                }
            )
            return 2

        oc_model = current_oc_model if slot["actor"] == "opencode" else None
        try:
            result = run_slot(slot, model=oc_model)
        except Exception as e:
            log(f"ERROR slot: {e}")
            console = STATUS.parent / (
                f"slot_{slot['actor']}_{slot['profile']}_{slot['scenario']}_"
                f"{slot['variant']}_{slot['repeat_idx']}.console.log"
            )
            # Free → paid failover on provider flake / missing TSV.
            if (
                slot["actor"] == "opencode"
                and args.prefer_free
                and model_tier == "free"
            ):
                log(f"SWITCH_TO_PAID after error: {e}")
                model_tier = "paid"
                current_oc_model = MODEL_PAID
                try:
                    result = run_slot(slot, model=MODEL_PAID)
                    result["switched_to_paid"] = True
                    result["switch_reason"] = str(e)
                except Exception as e2:
                    log(f"ERROR slot after paid switch: {e2}")
                    result = {
                        "error": str(e2),
                        **{
                            k: slot[k]
                            for k in (
                                "actor",
                                "profile",
                                "scenario",
                                "variant",
                                "repeat_idx",
                                "run_id",
                            )
                        },
                        "switched_to_paid": True,
                        "switch_reason": str(e),
                    }
                    results.append(result)
                    write_status(
                        {
                            "phase": "error",
                            "total": len(results) + len(slots) - i - 1,
                            "done": len(results),
                            "remaining": len(slots) - i - 1,
                            "results": results,
                            "stopped_reason": str(e2),
                            "balance": openrouter_remaining(),
                            "model_tier": model_tier,
                            "model": current_oc_model,
                        }
                    )
                    return 1
            else:
                result = {
                    "error": str(e),
                    **{
                        k: slot[k]
                        for k in (
                            "actor",
                            "profile",
                            "scenario",
                            "variant",
                            "repeat_idx",
                            "run_id",
                        )
                    },
                }
                results.append(result)
                write_status(
                    {
                        "phase": "error",
                        "total": len(results) + len(slots) - i - 1,
                        "done": len(results),
                        "remaining": len(slots) - i - 1,
                        "results": results,
                        "stopped_reason": str(e),
                        "balance": openrouter_remaining(),
                        "model_tier": model_tier,
                        "model": current_oc_model,
                    }
                )
                return 1

        bdir = batch_dir(slot["actor"], slot["profile"])
        row = latest_tsv_row(
            bdir, slot["scenario"], slot["variant"], slot["profile"], int(slot["repeat_idx"])
        )
        console = Path(result["console"]) if result.get("console") else None

        # Free-limit → switch paid and retry this slot once.
        if (
            slot["actor"] == "opencode"
            and args.prefer_free
            and model_tier == "free"
            and not result.get("error")
            and is_free_limit_failure(row, console)
            and not is_credit_failure(row, bdir, console)
        ):
            log(
                f"SWITCH_TO_PAID after free-limit on "
                f"{slot['scenario']}/{slot['variant']}#{slot['repeat_idx']}"
            )
            model_tier = "paid"
            current_oc_model = MODEL_PAID
            # Remove the bad free row so paid retry can rewrite the slot.
            if row and row.get("run_id"):
                remove_tsv_row(
                    bdir,
                    slot["scenario"],
                    slot["variant"],
                    slot["profile"],
                    int(slot["repeat_idx"]),
                    row["run_id"],
                )
                remove_progress_slot(
                    bdir,
                    slot["scenario"],
                    slot["variant"],
                    slot["profile"],
                    int(slot["repeat_idx"]),
                )
            try:
                result = run_slot(slot, model=MODEL_PAID)
                result["switched_to_paid"] = True
                result["switch_reason"] = "free_limit"
            except Exception as e:
                log(f"ERROR slot after paid switch: {e}")
                result = {
                    "error": str(e),
                    **{
                        k: slot[k]
                        for k in (
                            "actor",
                            "profile",
                            "scenario",
                            "variant",
                            "repeat_idx",
                            "run_id",
                        )
                    },
                    "switched_to_paid": True,
                    "switch_reason": "free_limit",
                }
                results.append(result)
                write_status(
                    {
                        "phase": "error",
                        "total": len(results) + len(slots) - i - 1,
                        "done": len(results),
                        "remaining": len(slots) - i - 1,
                        "results": results,
                        "stopped_reason": str(e),
                        "balance": openrouter_remaining(),
                        "model_tier": model_tier,
                        "model": current_oc_model,
                    }
                )
                return 1
            row = latest_tsv_row(
                bdir, slot["scenario"], slot["variant"], slot["profile"], int(slot["repeat_idx"])
            )
            console = Path(result["console"]) if result.get("console") else None

        results.append(result)

        if model_tier == "paid" and (
            is_credit_failure(row, bdir, console)
            or (
                result.get("verdict") == "INVALID"
                and CREDIT_RE.search(json.dumps(result))
            )
        ):
            left = slots[i + 1 :]
            log(f"STOP credits exhausted after slot; remaining={len(left)}")
            write_status(
                {
                    "phase": "stopped_credits",
                    "total": len(results) + len(left),
                    "done": len(results),
                    "remaining": len(left),
                    "remaining_slots": [
                        f"{s['actor']}/{s['profile']}/{s['scenario']}/{s['variant']}#{s['repeat_idx']}"
                        for s in left
                    ],
                    "results": results,
                    "stopped_reason": "api_provider_credits",
                    "balance": openrouter_remaining(),
                    "model_tier": model_tier,
                    "model": current_oc_model,
                }
            )
            return 2

        write_status(
            {
                "phase": "running",
                "total": len(results) + len(slots) - i - 1,
                "done": len(results),
                "remaining": len(slots) - i - 1,
                "results": results,
                "stopped_reason": None,
                "balance": openrouter_remaining(),
                "model_tier": model_tier,
                "model": current_oc_model,
            }
        )

    write_status(
        {
            "phase": "complete",
            "total": len(results),
            "done": len(results),
            "remaining": 0,
            "results": results,
            "stopped_reason": None,
            "balance_end": openrouter_remaining(),
            "model_tier": model_tier,
            "model": current_oc_model,
        }
    )
    log("ALL SLOTS COMPLETE")
    return 0


if __name__ == "__main__":
    sys.exit(main())
