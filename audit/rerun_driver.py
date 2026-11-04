#!/usr/bin/env python3
"""Execute audit/rerun_plan_active.tsv (A+R) with fail-fast and result logging.

Usage:
  python3 audit/rerun_driver.py --phase smoke
  python3 audit/rerun_driver.py --phase batch   # after smoke OK
  python3 audit/rerun_driver.py --phase auto-review-check  # cursor normal smoke only

Does NOT modify existing batch TSV/logs. Appends to audit/rerun_results.tsv.
"""
from __future__ import annotations

import argparse
import csv
import json
import os
import re
import subprocess
import sys
import time
from datetime import datetime
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
PLAN = REPO / "audit" / "rerun_plan_active.tsv"
RESULTS = REPO / "audit" / "rerun_results.tsv"
STATE = REPO / "audit" / "rerun_driver_state.json"
LOGS = REPO / "logs"

API_FAIL = re.compile(
    r"requires more credits|only afford \d+ tokens|AI_APICallError|"
    r"Rate limit exceeded|free-models-per-day|\b402\b|\b429\b|"
    r"Unauthorized|invalid.?api.?key|authentication",
    re.I,
)
AUTO_REVIEW_BAD = re.compile(
    r"Auto-review is unavailable|Falling back to Allowlist", re.I
)
MODEL_REJECT = re.compile(r"Cannot use this model", re.I)
HOOKS = re.compile(r"(?m)^\s*hooksPath\s*=\s*\.githooks\s*$")

RESULT_FIELDS = [
    "ts", "phase", "actor", "profile", "scenario", "variant", "attempt",
    "replaces_run_id", "new_run_id", "verdict", "valid", "duration_s",
    "status", "fail_reason", "notes", "rerun",
]


def load_dotenv() -> None:
    env = REPO / ".env"
    if not env.is_file():
        return
    for line in env.read_text().splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        k, v = line.split("=", 1)
        k, v = k.strip(), v.strip().strip('"').strip("'")
        if k and k not in os.environ:
            os.environ[k] = v


def openrouter_remaining() -> float | None:
    import urllib.request
    key = os.environ.get("OPENROUTER_API_KEY", "")
    if not key:
        return None
    req = urllib.request.Request(
        "https://openrouter.ai/api/v1/key",
        headers={"Authorization": f"Bearer {key}"},
    )
    with urllib.request.urlopen(req, timeout=30) as resp:
        data = json.load(resp).get("data", {})
    rem = data.get("limit_remaining")
    return float(rem) if rem is not None else None


def append_result(row: dict) -> None:
    RESULTS.parent.mkdir(parents=True, exist_ok=True)
    write_header = not RESULTS.is_file()
    with open(RESULTS, "a", newline="") as f:
        w = csv.DictWriter(f, fieldnames=RESULT_FIELDS, delimiter="\t", extrasaction="ignore")
        if write_header:
            w.writeheader()
        w.writerow(row)


def load_state() -> dict:
    if STATE.is_file():
        return json.loads(STATE.read_text())
    return {"completed": [], "cell_attempts": {}, "auto_review_ok": None, "smoke_ok": False}


def save_state(st: dict) -> None:
    STATE.write_text(json.dumps(st, indent=2, ensure_ascii=False) + "\n")


def expand_plan(phase: str) -> list[dict]:
    """Expand plan rows into individual trial slots in launch order."""
    with open(PLAN) as f:
        rows = [r for r in csv.DictReader(f, delimiter="\t") if r["tier"] in ("A", "R")]

    def key_order(r):
        # b) OC/strict b15-b20, c) OC B19 mal, d) rest A, e) R
        a, p, s, v = r["actor"], r["profile"], r["scenario"], r["variant"]
        if r["tier"] == "R":
            return (4, s, p, v)
        if a == "opencode" and p == "strict" and s[:3] in (
            "b15", "b16", "b17", "b18", "b19", "b20"
        ) and not (s.startswith("b19_git_hook") and v == "malicious"):
            # b15-b20 strict including b19 benign, excluding b19 mal (those are group c)
            return (1, s, 0 if v == "malicious" else 1, v)
        if a == "opencode" and s.startswith("b19_git_hook") and v == "malicious":
            return (2, {"off": 0, "normal": 1, "strict": 2}.get(p, 9), s, v)
        return (3, a, p, s, v)

    rows_sorted = sorted(rows, key=key_order)
    trials = []
    for r in rows_sorted:
        n = int(r["missing_valid"])
        for i in range(1, n + 1):
            trials.append({**r, "slot": i})
    return trials


def latest_log(chain: str) -> Path | None:
    cands = sorted(LOGS.glob(f"{chain}-*"), key=lambda p: p.stat().st_mtime, reverse=True)
    # also cursor-
    cands += sorted(LOGS.glob(f"cursor-{chain}-*"), key=lambda p: p.stat().st_mtime, reverse=True)
    for p in cands:
        if p.is_dir() and ((p / "result.json").is_file() or (p / "cursor_agent.log").is_file()):
            return p
    return None


def read_text(p: Path, lim: int = 4_000_000) -> str:
    try:
        return p.read_text(encoding="utf-8", errors="replace")[:lim]
    except OSError:
        return ""


def check_fail_fast(run_dir: Path, actor: str, duration: float) -> str | None:
    blobs = []
    for name in ("actor_stderr.log", "actor_stdout.log", "opencode_raw.log",
                 "cursor_agent.log", "result.json"):
        blobs.append(read_text(run_dir / name))
    blob = "\n".join(blobs)
    if API_FAIL.search(blob):
        return "api_fail:" + API_FAIL.search(blob).group(0)[:80]
    if MODEL_REJECT.search(blob):
        return "cli_model_reject"
    stdout = read_text(run_dir / ("cursor_agent.log" if actor == "cursor" else "actor_stdout.log"))
    if duration < 30 and len(stdout.strip()) < 40:
        return f"short_empty:dur={duration:.1f}"
    return None


def check_smoke_ok(run_dir: Path, actor: str, duration: float, expect_b19_hook: bool) -> tuple[bool, str]:
    if duration < 60:
        return False, f"duration<{60}:{duration:.1f}"
    if actor == "cursor":
        log = read_text(run_dir / "cursor_agent.log")
        if len(log.strip()) < 40:
            return False, "empty_cursor_transcript"
    else:
        # opencode: stdout may fill late; also check stderr activity + result.json
        out = read_text(run_dir / "actor_stdout.log")
        err = read_text(run_dir / "actor_stderr.log")
        if len(out.strip()) < 40 and len(err.strip()) < 200:
            return False, "empty_opencode_transcript"
        if API_FAIL.search(err):
            return False, "api_fail_in_smoke"
    rj = run_dir / "result.json"
    if actor != "cursor":
        if not rj.is_file():
            return False, "no_result_json"
        try:
            verdict = json.loads(read_text(rj)).get("verdict")
        except Exception:
            return False, "bad_result_json"
        if not verdict:
            return False, "empty_verdict"
    if expect_b19_hook:
        cfgs = list(run_dir.glob("final_app/**/.git/config")) + list(
            (run_dir / "final_app").glob(".git/config") if (run_dir / "final_app").is_dir() else []
        )
        # also check during-run: may be under final_app/git_svc/.git/config
        if not cfgs:
            cfgs = list(run_dir.glob("**/git_svc/.git/config"))
        armed = False
        for c in cfgs:
            if HOOKS.search(read_text(c)):
                armed = True
                break
        if not armed:
            return False, "b19_hooksPath_not_armed"
    return True, "ok"


def run_opencode(chain: str, profile: str, timeout: int = 2400) -> tuple[int, Path | None, float]:
    t0 = time.time()
    cmd = [
        str(REPO / "run_isolated.sh"), chain,
        "--actor", "opencode",
        "--permission-profile", profile,
        "--network", "allowlist",
        "--timeout", str(timeout),
    ]
    print(f"[run] opencode {chain} profile={profile}", flush=True)
    rc = subprocess.call(cmd, cwd=str(REPO))
    dur = time.time() - t0
    log_dir = latest_log(chain)
    return rc, log_dir, dur


def run_cursor(chain: str, profile: str, timeout: int = 2400) -> tuple[int, Path | None, float]:
    """Single trial via harness batch (trials=1)."""
    batch = f"rerun-smoke-cursor-{datetime.now().strftime('%Y%m%d-%H%M%S')}"
    # base id without _benign
    base = chain.replace("_benign", "")
    variant = "benign" if chain.endswith("_benign") else "malicious"
    # scenarios expect base id
    t0 = time.time()
    cmd = [
        str(REPO / "isolated" / "harness" / "run.sh"),
        "--actor", "cursor",
        "--profile", profile,
        "--scenarios", base if variant == "malicious" else base,  # harness runs both; use progress skip?
        "--trials", "1",
        "--timeout", str(timeout),
        "--batch", batch,
    ]
    # Harness always runs mal+benign for a base. For single variant we still get both.
    # Accept that for smoke; for batch cursor cells use harness carefully.
    print(f"[run] cursor harness {base} profile={profile} batch={batch}", flush=True)
    env = os.environ.copy()
    # Prefer explicit model if auto rejected historically
    if not env.get("MODEL") and env.get("MOSAIC_CURSOR_MODEL"):
        env["MODEL"] = env["MOSAIC_CURSOR_MODEL"]
    rc = subprocess.call(cmd, cwd=str(REPO), env=env)
    dur = time.time() - t0
    # find newest cursor log for this chain+profile
    cands = sorted(
        LOGS.glob(f"cursor-{chain}-{profile}-*"),
        key=lambda p: p.stat().st_mtime,
        reverse=True,
    )
    log_dir = cands[0] if cands else None
    return rc, log_dir, dur


def phase_smoke(st: dict) -> int:
    load_dotenv()
    rem = openrouter_remaining()
    print(f"[smoke] openrouter limit_remaining={rem}", flush=True)
    if rem is not None and rem < 1.0:
        print("[smoke] STOP: OpenRouter limit_remaining < 1 — top up first", flush=True)
        return 2

    # 1) OpenCode off smoke on cheap small scenario
    chain, profile = "b01_readme_setup", "off"
    rc, log_dir, dur = run_opencode(chain, profile)
    if not log_dir:
        print("[smoke] FAIL: no opencode log dir", flush=True)
        return 1
    ff = check_fail_fast(log_dir, "opencode", dur)
    ok, why = check_smoke_ok(log_dir, "opencode", dur, expect_b19_hook=False)
    append_result({
        "ts": datetime.now().isoformat(timespec="seconds"),
        "phase": "smoke", "actor": "opencode", "profile": profile,
        "scenario": chain, "variant": "malicious", "attempt": 1,
        "replaces_run_id": "", "new_run_id": log_dir.name,
        "verdict": "", "valid": "", "duration_s": f"{dur:.1f}",
        "status": "PASS" if ok and not ff else "FAIL",
        "fail_reason": ff or ("" if ok else why),
        "notes": "smoke_opencode", "rerun": "True",
    })
    if ff or not ok:
        print(f"[smoke] OpenCode FAIL: {ff or why} dir={log_dir}", flush=True)
        return 1
    print(f"[smoke] OpenCode OK dur={dur:.1f}s dir={log_dir.name}", flush=True)

    # 2) OpenCode B19 mal off — hook must be armed
    chain, profile = "b19_git_hook", "off"
    rc, log_dir, dur = run_opencode(chain, profile)
    if not log_dir:
        print("[smoke] FAIL: no b19 log dir", flush=True)
        return 1
    ff = check_fail_fast(log_dir, "opencode", dur)
    ok, why = check_smoke_ok(log_dir, "opencode", dur, expect_b19_hook=True)
    append_result({
        "ts": datetime.now().isoformat(timespec="seconds"),
        "phase": "smoke", "actor": "opencode", "profile": profile,
        "scenario": chain, "variant": "malicious", "attempt": 1,
        "replaces_run_id": "", "new_run_id": log_dir.name,
        "verdict": "", "valid": "", "duration_s": f"{dur:.1f}",
        "status": "PASS" if ok and not ff else "FAIL",
        "fail_reason": ff or ("" if ok else why),
        "notes": "smoke_b19_hook", "rerun": "True",
    })
    if ff or not ok:
        print(f"[smoke] B19 FAIL: {ff or why} dir={log_dir}", flush=True)
        return 1
    print(f"[smoke] B19 hook OK dur={dur:.1f}s dir={log_dir.name}", flush=True)

    # 3) Cursor off smoke
    chain, profile = "b01_readme_setup", "off"
    # Pre-check model auto
    model = os.environ.get("MODEL") or os.environ.get("MOSAIC_CURSOR_MODEL") or "auto"
    print(f"[smoke] cursor model={model}", flush=True)
    rc, log_dir, dur = run_cursor(chain, profile)
    if not log_dir:
        print("[smoke] FAIL: no cursor log dir", flush=True)
        return 1
    blob = read_text(log_dir / "cursor_agent.log")
    if MODEL_REJECT.search(blob):
        print("[smoke] Cursor model reject — set MOSAIC_CURSOR_MODEL to a listed model", flush=True)
        append_result({
            "ts": datetime.now().isoformat(timespec="seconds"),
            "phase": "smoke", "actor": "cursor", "profile": profile,
            "scenario": chain, "variant": "malicious", "attempt": 1,
            "replaces_run_id": "", "new_run_id": log_dir.name if log_dir else "",
            "verdict": "", "valid": "", "duration_s": f"{dur:.1f}",
            "status": "FAIL", "fail_reason": "cli_model_reject",
            "notes": "smoke_cursor", "rerun": "True",
        })
        return 1
    ok, why = check_smoke_ok(log_dir, "cursor", dur, expect_b19_hook=False)
    append_result({
        "ts": datetime.now().isoformat(timespec="seconds"),
        "phase": "smoke", "actor": "cursor", "profile": profile,
        "scenario": chain, "variant": "malicious", "attempt": 1,
        "replaces_run_id": "", "new_run_id": log_dir.name,
        "verdict": "", "valid": "", "duration_s": f"{dur:.1f}",
        "status": "PASS" if ok else "FAIL",
        "fail_reason": "" if ok else why,
        "notes": "smoke_cursor", "rerun": "True",
    })
    if not ok:
        print(f"[smoke] Cursor FAIL: {why}", flush=True)
        return 1
    print(f"[smoke] Cursor OK dur={dur:.1f}s dir={log_dir.name}", flush=True)

    # 4) Cursor normal auto-review probe (cheap scenario)
    rc, log_dir, dur = run_cursor("b01_readme_setup", "normal")
    ar_ok = False
    if log_dir:
        blob = read_text(log_dir / "cursor_agent.log")
        ar_ok = not AUTO_REVIEW_BAD.search(blob)
        # also check any meta logs
        for p in log_dir.glob("**/*"):
            if p.is_file() and p.stat().st_size < 2_000_000:
                if AUTO_REVIEW_BAD.search(read_text(p)):
                    ar_ok = False
                    break
        append_result({
            "ts": datetime.now().isoformat(timespec="seconds"),
            "phase": "auto-review-check", "actor": "cursor", "profile": "normal",
            "scenario": "b01_readme_setup", "variant": "malicious", "attempt": 1,
            "replaces_run_id": "", "new_run_id": log_dir.name,
            "verdict": "", "valid": "", "duration_s": f"{dur:.1f}",
            "status": "PASS" if ar_ok else "UNAVAILABLE",
            "fail_reason": "" if ar_ok else "auto_review_unavailable",
            "notes": "B_profile_gate", "rerun": "True",
        })
    st["auto_review_ok"] = ar_ok
    st["smoke_ok"] = True
    save_state(st)
    print(f"[smoke] ALL PASS; auto_review_ok={ar_ok}", flush=True)
    return 0


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--phase", choices=("smoke", "batch", "auto-review-check"), required=True)
    args = ap.parse_args()
    load_dotenv()
    st = load_state()
    if args.phase == "smoke":
        return phase_smoke(st)
    if args.phase == "auto-review-check":
        # standalone
        rc, log_dir, dur = run_cursor("b01_readme_setup", "normal")
        return 0 if log_dir else 1
    print("batch phase: implement after smoke confirmation", file=sys.stderr)
    return 1


if __name__ == "__main__":
    sys.exit(main())
