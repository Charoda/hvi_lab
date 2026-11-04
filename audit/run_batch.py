#!/usr/bin/env python3
"""Batch rerun driver for OC (A+R) then optional Cursor phase.

Resume: queue rebuilt from audit/rerun_results.tsv (PASS+verdict fills slots).
Fail-fast on paid API/auth/credits and short-empty transcripts.
Free→paid failover on free-model rate/day limits (not a hard stop).
Budget: after every 10 OC runs, if limit_remaining < $3 → planned stop.
Max 2 FAIL attempts per cell (free-limit switches do not count).
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
from collections import defaultdict
from datetime import datetime
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
LOGS = REPO / "logs"
PLAN = REPO / "audit" / "rerun_plan_active.tsv"
RESULTS = REPO / "audit" / "rerun_results.tsv"
STATE = REPO / "audit" / "rerun_driver_state.json"
BATCH_LOG = REPO / "audit" / "rerun_logs" / "batch.log"

MODEL_FREE = "openrouter/nvidia/nemotron-3-ultra-550b-a55b:free"
MODEL_PAID = "openrouter/nvidia/nemotron-3-ultra-550b-a55b"
BUDGET_FLOOR = 3.0
OC_BALANCE_EVERY = 10

# NOTE: do NOT match bare "429" — timestamps look like "22:31:40.429Z".
API_FAIL = re.compile(
    r"requires more credits|only afford \d+ tokens|AI_APICallError|"
    r"Rate limit exceeded|free-models-per-day|"
    r"(?:HTTP\/\d\.?\d?\s*|status[=:\s]|error[=:\s]|code[=:\s])(?:402|429)\b|"
    r"\b(?:402|429)\s+(?:Payment Required|Too Many Requests)\b|"
    r"Unauthorized|invalid.?api.?key|authentication failed",
    re.I | re.M,
)
# Free-tier / free-provider problems → switch to paid (not hard stop).
FREE_LIMIT = re.compile(
    r"free-models-per-day|Rate limit exceeded|"
    r"(?:HTTP\/\d\.?\d?\s*|status[=:\s]|error[=:\s]|code[=:\s])429\b|"
    r"\b429\s+Too Many Requests\b|"
    r"AI_APICallError|"
    r"error code:\s*502|\b502\b",
    re.I | re.M,
)
HARD_PAID_FAIL = re.compile(
    r"requires more credits|only afford \d+ tokens|"
    r"(?:HTTP\/\d\.?\d?\s*|status[=:\s]|error[=:\s]|code[=:\s])402\b|"
    r"\b402\s+Payment Required\b|"
    r"Unauthorized|invalid.?api.?key|authentication failed",
    re.I | re.M,
)
AUTH_FAIL = re.compile(
    r"Unauthorized|invalid.?api.?key|authentication failed",
    re.I | re.M,
)
MODEL_REJECT = re.compile(r"Cannot use this model", re.I)
HOOKS = re.compile(r"(?m)^\s*hooksPath\s*=\s*\.githooks\s*$")
FIELDS = [
    "ts", "phase", "actor", "profile", "scenario", "variant", "attempt",
    "replaces_run_id", "new_run_id", "verdict", "valid", "duration_s",
    "status", "fail_reason", "notes", "rerun",
]


def load_dotenv() -> None:
    p = REPO / ".env"
    if not p.is_file():
        return
    for line in p.read_text().splitlines():
        if not line.strip() or line.strip().startswith("#") or "=" not in line:
            continue
        k, v = line.split("=", 1)
        k, v = k.strip(), v.strip().strip('"').strip("'")
        if k and k not in os.environ:
            os.environ[k] = v


def log(msg: str) -> None:
    line = f"[{datetime.now().strftime('%H:%M:%S')}] {msg}"
    print(line, flush=True)
    BATCH_LOG.parent.mkdir(parents=True, exist_ok=True)
    with open(BATCH_LOG, "a") as f:
        f.write(line + "\n")


def append_result(row: dict) -> None:
    write_header = not RESULTS.is_file()
    with open(RESULTS, "a", newline="") as f:
        w = csv.DictWriter(f, fieldnames=FIELDS, delimiter="\t", extrasaction="ignore")
        if write_header:
            w.writeheader()
        w.writerow(row)


def load_state() -> dict:
    if STATE.is_file():
        return json.loads(STATE.read_text())
    return {
        "smoke_ok": False,
        "auto_review_ok": False,
        "completed_keys": [],
        "cell_attempts": {},
        "model_tier": "free",
    }


def save_state(st: dict) -> None:
    STATE.write_text(json.dumps(st, indent=2, ensure_ascii=False) + "\n")


def current_model() -> str:
    return (os.environ.get("MOSAIC_OPENCODE_MODEL") or MODEL_FREE).strip()


def set_model(tier: str, st: dict) -> None:
    model = MODEL_FREE if tier == "free" else MODEL_PAID
    os.environ["MOSAIC_OPENCODE_MODEL"] = model
    st["model_tier"] = tier
    st["model"] = model
    save_state(st)
    log(f"model set tier={tier} id={model}")


def already_ok_counts() -> dict[tuple, int]:
    """Count successful fills per cell from rerun_results.tsv (resume source of truth)."""
    counts: dict[tuple, int] = defaultdict(int)
    if not RESULTS.is_file():
        return counts
    with open(RESULTS) as f:
        for r in csv.DictReader(f, delimiter="\t"):
            if r.get("status") != "PASS":
                continue
            if not r.get("verdict"):
                continue
            if r.get("phase") not in ("batch", "smoke"):
                continue
            # smoke b01 don't fill plan holes
            if r.get("phase") == "smoke" and r["scenario"] == "b01_readme_setup":
                continue
            key = (r["actor"], r["profile"], r["scenario"], r["variant"])
            counts[key] += 1
    return counts


def cell_attempts_from_results() -> dict[str, int]:
    """Per-cell FAIL streak from results. Interrupted (no row) does not count."""
    attempts: dict[str, int] = defaultdict(int)
    if not RESULTS.is_file():
        return {}
    with open(RESULTS) as f:
        for r in csv.DictReader(f, delimiter="\t"):
            if r.get("phase") != "batch":
                continue
            key = "|".join((r["actor"], r["profile"], r["scenario"], r["variant"]))
            if r.get("status") == "PASS" and r.get("verdict"):
                attempts[key] = 0
            elif r.get("status") in ("FAIL", "FAIL_FAST"):
                attempts[key] = attempts.get(key, 0) + 1
            # SWITCH_TO_PAID / SKIP do not increment
    return dict(attempts)


def build_queue(phase: str, skipped_cells: set[str] | None = None) -> list[dict]:
    with open(PLAN) as f:
        rows = list(csv.DictReader(f, delimiter="\t"))

    if phase == "oc":
        rows = [r for r in rows if r["actor"] == "opencode" and r["tier"] in ("A", "R")]
    elif phase == "cursor":
        rows = [r for r in rows if r["actor"] == "cursor" and r["tier"] in ("A", "B_profile")]
    else:
        raise ValueError(phase)

    skipped = skipped_cells or set()

    def sort_key(r):
        a, p, s, v, t = r["actor"], r["profile"], r["scenario"], r["variant"], r["tier"]
        if t == "R":
            return (5, s, p, v)
        if t == "B_profile":
            return (4, s, v)
        # A OC: strict b15-b20 (not b19 mal) → b19 mal off/normal/strict → rest
        if a == "opencode" and p == "strict" and s.startswith(
            ("b15_", "b16_", "b17_", "b18_", "b19_", "b20_")
        ) and not (s.startswith("b19_git_hook") and v == "malicious"):
            return (1, s, 0 if v == "malicious" else 1)
        if a == "opencode" and s.startswith("b19_git_hook") and v == "malicious":
            return (2, {"off": 0, "normal": 1, "strict": 2}[p])
        # Cursor A: off b16 then normal b19
        if a == "cursor":
            return (3, 0 if s.startswith("b16_") else 1, s, v)
        return (3, a, p, s, v)

    rows = sorted(rows, key=sort_key)
    have = already_ok_counts()
    queue = []
    for r in rows:
        key = (r["actor"], r["profile"], r["scenario"], r["variant"])
        cell_key = "|".join(key)
        if cell_key in skipped:
            continue
        need = int(r["missing_valid"]) - have.get(key, 0)
        for slot in range(1, max(0, need) + 1):
            queue.append({**r, "slot": slot, "cell_key": cell_key})
    return queue


def chain_id(scenario: str, variant: str) -> str:
    return scenario if variant == "malicious" else f"{scenario}_benign"


def read(p: Path, lim: int = 6_000_000) -> str:
    try:
        return p.read_text(encoding="utf-8", errors="replace")[:lim]
    except OSError:
        return ""


def latest_oc_log(chain: str, after_ts: float) -> Path | None:
    best = None
    best_m = after_ts
    for p in LOGS.glob(f"{chain}-*"):
        if not p.is_dir():
            continue
        m = p.stat().st_mtime
        if m >= after_ts - 1 and m >= best_m:
            if (p / "result.json").is_file() or (p / "actor_stderr.log").is_file():
                best, best_m = p, m
    return best


def latest_cursor_log(chain: str, profile: str, after_ts: float) -> Path | None:
    best = None
    best_m = after_ts
    for p in LOGS.glob(f"cursor-{chain}-{profile}-*"):
        if not p.is_dir():
            continue
        m = p.stat().st_mtime
        if m >= after_ts - 1 and m >= best_m:
            best, best_m = p, m
    return best


def agent_blob(run_dir: Path) -> str:
    return "\n".join(
        read(run_dir / n)
        for n in (
            "actor_stderr.log", "actor_stdout.log", "opencode_raw.log",
            "cursor_agent.log", "result.json",
        )
    )


def evaluate_run(
    run_dir: Path, actor: str, scenario: str, variant: str, dur: float, model_tier: str
) -> tuple[str, str, str, str]:
    """Return status, fail_reason, verdict, valid.

    status: PASS | FAIL | FAIL_FAST | SWITCH_TO_PAID
    """
    blob = agent_blob(run_dir)

    # Auth always hard-stops (free or paid).
    if AUTH_FAIL.search(blob):
        return "FAIL_FAST", "api_fail:" + AUTH_FAIL.search(blob).group(0)[:100], "", ""

    # On free: rate limits, day caps, provider 502 / AI_APICallError → paid.
    if model_tier == "free" and FREE_LIMIT.search(blob):
        return (
            "SWITCH_TO_PAID",
            "free_provider:" + FREE_LIMIT.search(blob).group(0)[:80],
            "",
            "",
        )

    if model_tier == "paid" and HARD_PAID_FAIL.search(blob):
        return "FAIL_FAST", "api_fail:" + HARD_PAID_FAIL.search(blob).group(0)[:100], "", ""

    if API_FAIL.search(blob):
        if model_tier == "free":
            return "SWITCH_TO_PAID", "free_api:" + API_FAIL.search(blob).group(0)[:80], "", ""
        # Paid: credits/auth already handled. Transient provider errors → FAIL (retry), not package stop.
        if re.search(r"AI_APICallError|error code:\s*502|\b502\b|Rate limit exceeded|\b429\b", blob, re.I):
            return "FAIL", "provider_transient:" + API_FAIL.search(blob).group(0)[:80], "", ""
        return "FAIL_FAST", "api_fail:" + API_FAIL.search(blob).group(0)[:100], "", ""

    if MODEL_REJECT.search(blob):
        return "FAIL_FAST", "cli_model_reject", "", ""

    verdict, valid = "", ""
    if actor == "opencode" and (run_dir / "result.json").is_file():
        try:
            rj = json.loads(read(run_dir / "result.json", 500_000))
            verdict = str(rj.get("verdict") or "")
            dur = float(rj.get("duration_s") or dur)
        except Exception:
            return "FAIL", "bad_result_json", "", ""
        valid = "True" if verdict in ("SECURE", "VULNERABLE") else "False"
    else:
        clog = read(run_dir / "cursor_agent.log")
        if MODEL_REJECT.search(clog):
            return "FAIL_FAST", "cli_model_reject", "", ""
        if len(clog.strip()) < 20:
            return "FAIL", "empty_transcript", "", ""

    stdout = read(run_dir / ("cursor_agent.log" if actor == "cursor" else "actor_stdout.log"))
    stderr = read(run_dir / "actor_stderr.log") if actor == "opencode" else ""
    if dur < 30 and len(stdout.strip()) < 40 and len(stderr) < 100:
        # short empty on free often = rate limit without clear string — switch
        if model_tier == "free":
            return "SWITCH_TO_PAID", f"short_empty_on_free:dur={dur:.1f}", verdict, valid
        return "FAIL_FAST", f"short_empty:dur={dur:.1f}", verdict, valid

    if actor == "opencode" and scenario.startswith("b19_git_hook") and variant == "malicious":
        cfgs = list(run_dir.glob("final_app/**/.git/config")) + list(run_dir.glob("final_app/.git/config"))
        if not any(HOOKS.search(read(c)) for c in cfgs):
            return "FAIL", "b19_hooksPath_not_armed", verdict, valid

    if actor == "opencode" and not verdict:
        return "FAIL", "no_verdict", "", ""

    return "PASS", "", verdict, valid or ("True" if verdict else "")


def run_opencode(chain: str, profile: str) -> tuple[Path | None, float, int]:
    t0 = time.time()
    cmd = [
        str(REPO / "run_isolated.sh"), chain,
        "--actor", "opencode",
        "--permission-profile", profile,
        "--network", "allowlist",
        "--timeout", "2400",
    ]
    env = os.environ.copy()
    rc = subprocess.call(cmd, cwd=str(REPO), env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    dur = time.time() - t0
    return latest_oc_log(chain, t0), dur, rc


def run_cursor_one(chain: str, profile: str, scenario: str, variant: str) -> tuple[Path | None, float, int]:
    batch = f"rerun-batch-cursor-{scenario}-{profile}-{variant}-{datetime.now().strftime('%H%M%S')}"
    t0 = time.time()
    cmd = [
        str(REPO / "isolated" / "harness" / "run.sh"),
        "--actor", "cursor",
        "--profile", profile,
        "--scenarios", scenario,
        "--trials", "1",
        "--timeout", "2400",
        "--batch", batch,
    ]
    rc = subprocess.call(cmd, cwd=str(REPO), env=os.environ.copy())
    dur = time.time() - t0
    return latest_cursor_log(chain, profile, t0), dur, rc


def find_replace_id(actor: str, profile: str, scenario: str, variant: str) -> str:
    idx = REPO / "audit" / "stopped_by_corrected.tsv"
    if not idx.is_file():
        return ""
    with open(idx) as f:
        for r in csv.DictReader(f, delimiter="\t"):
            if (
                r["actor"] == actor and r["profile"] == profile
                and r["scenario"] == scenario and r["variant"] == variant
                and r["status_effective"] in ("INVALID", "MEASUREMENT_INVALID", "PROFILE_DEGRADED")
            ):
                return r["run_id"]
    return ""


def openrouter_remaining() -> float | None:
    import urllib.request
    key = os.environ.get("OPENROUTER_API_KEY", "")
    if not key:
        return None
    req = urllib.request.Request(
        "https://openrouter.ai/api/v1/key",
        headers={"Authorization": f"Bearer {key}"},
    )
    try:
        with urllib.request.urlopen(req, timeout=30) as resp:
            data = json.load(resp).get("data", {})
        return float(data.get("limit_remaining") or 0)
    except Exception as e:
        log(f"balance check failed: {type(e).__name__}")
        return None


def phase_smoke(st: dict) -> int:
    """One OC smoke on free model (b01 off) to verify env after orphan cleanup."""
    load_dotenv()
    set_model("free", st)
    rem0 = openrouter_remaining()
    log(f"[smoke] start model={current_model()} remaining={rem0}")
    run_dir, dur, rc = run_opencode("b01_readme_setup", "off")
    if not run_dir:
        log(f"[smoke] FAIL no log dir rc={rc}")
        return 1
    status, fail_reason, verdict, valid = evaluate_run(
        run_dir, "opencode", "b01_readme_setup", "malicious", dur, "free"
    )
    if status == "SWITCH_TO_PAID":
        log(f"[smoke] free limit on smoke → switch paid and retry once ({fail_reason})")
        set_model("paid", st)
        run_dir, dur, rc = run_opencode("b01_readme_setup", "off")
        if not run_dir:
            log("[smoke] FAIL no log dir after paid switch")
            return 1
        status, fail_reason, verdict, valid = evaluate_run(
            run_dir, "opencode", "b01_readme_setup", "malicious", dur, "paid"
        )
    notes = f"smoke_oc;model={current_model()};tier={st.get('model_tier')}"
    append_result({
        "ts": datetime.now().isoformat(timespec="seconds"),
        "phase": "smoke", "actor": "opencode", "profile": "off",
        "scenario": "b01_readme_setup", "variant": "malicious", "attempt": 1,
        "replaces_run_id": "", "new_run_id": run_dir.name,
        "verdict": verdict, "valid": valid, "duration_s": f"{dur:.1f}",
        "status": "PASS" if status == "PASS" else status,
        "fail_reason": fail_reason, "notes": notes, "rerun": "True",
    })
    if status != "PASS":
        log(f"[smoke] FAIL {status} {fail_reason} dir={run_dir.name}")
        return 1
    st["smoke_ok"] = True
    st["smoke_run_id"] = run_dir.name
    st["rem_at_smoke"] = rem0
    save_state(st)
    rem1 = openrouter_remaining()
    log(f"[smoke] PASS {run_dir.name} verdict={verdict} dur={dur:.1f} remaining={rem1}")
    return 0


def run_batch_phase(phase: str, st: dict) -> int:
    if phase == "oc" and not st.get("smoke_ok"):
        log("STOP: smoke_ok is false — run --phase smoke first")
        return 2

    # model: keep current tier from state (free unless already switched)
    tier = st.get("model_tier") or "free"
    if phase == "oc":
        set_model(tier if tier in ("free", "paid") else "free", st)
    if (st.get("model_tier") == "paid") and st.get("rem_at_paid_start") is None:
        rem_p = openrouter_remaining()
        st["rem_at_paid_start"] = rem_p
        save_state(st)
        log(f"seeded rem_at_paid_start={rem_p}")

    skipped = set(st.get("skipped_cells") or [])
    queue = build_queue(phase, skipped)
    rem_start = openrouter_remaining()
    st[f"rem_at_{phase}_start"] = rem_start
    save_state(st)
    log(f"[{phase}] queue size={len(queue)} model={current_model()} remaining={rem_start}")
    if phase == "oc":
        log("[oc] note: full-plan 4x b15 mal ASR_USABLE not in active — skipped")

    cell_attempts = cell_attempts_from_results()
    oc_since_balance = 0
    rem_before_paid_oc: float | None = st.get("rem_at_paid_start")
    safety = 0

    while True:
        safety += 1
        if safety > 5000:
            log("safety break: iteration cap")
            break

        skipped = set(st.get("skipped_cells") or [])
        live_queue = build_queue(phase, skipped)
        if not live_queue:
            log(f"[{phase}] queue empty — done")
            break

        item = live_queue[0]
        key = item["cell_key"]
        attempts = cell_attempts.get(key, 0)
        if attempts >= 2:
            log(f"SKIP {key}: already 2 FAIL attempts")
            skipped.add(key)
            st["skipped_cells"] = list(skipped)
            save_state(st)
            continue

        actor = item["actor"]
        profile = item["profile"]
        scenario = item["scenario"]
        variant = item["variant"]
        chain = chain_id(scenario, variant)
        replaces = find_replace_id(actor, profile, scenario, variant)
        tier = st.get("model_tier") or "free"

        log(
            f"=== [{phase}] {actor}/{profile}/{scenario}/{variant} "
            f"slot={item['slot']} attempt={attempts+1} model_tier={tier} ==="
        )

        if actor == "opencode":
            run_dir, dur, rc = run_opencode(chain, profile)
            st["oc_runs_done"] = int(st.get("oc_runs_done") or 0) + 1
            oc_since_balance += 1
            if tier == "paid" and rem_before_paid_oc is None:
                rem_before_paid_oc = openrouter_remaining()
                st["rem_at_paid_start"] = rem_before_paid_oc
            save_state(st)
        else:
            run_dir, dur, rc = run_cursor_one(chain, profile, scenario, variant)

        if not run_dir:
            append_result({
                "ts": datetime.now().isoformat(timespec="seconds"),
                "phase": "batch", "actor": actor, "profile": profile,
                "scenario": scenario, "variant": variant, "attempt": attempts + 1,
                "replaces_run_id": replaces, "new_run_id": "",
                "verdict": "", "valid": "", "duration_s": f"{dur:.1f}",
                "status": "FAIL", "fail_reason": f"no_log_dir:rc={rc}",
                "notes": f"model={current_model()}", "rerun": "True",
            })
            cell_attempts[key] = attempts + 1
            log(f"FAIL no log dir rc={rc}")
            if cell_attempts[key] >= 2:
                skipped = set(st.get("skipped_cells") or [])
                skipped.add(key)
                st["skipped_cells"] = list(skipped)
                save_state(st)
            continue

        status, fail_reason, verdict, valid = evaluate_run(
            run_dir, actor, scenario, variant, dur, tier if actor == "opencode" else "paid"
        )

        if actor == "cursor" and not verdict:
            for batch in sorted(
                LOGS.glob("rerun-batch-cursor-*"),
                key=lambda p: p.stat().st_mtime,
                reverse=True,
            )[:3]:
                tsv = batch / ("malicious.tsv" if variant == "malicious" else "benign.tsv")
                if not tsv.is_file():
                    continue
                with open(tsv) as f:
                    for row in csv.DictReader(f, delimiter="\t"):
                        if row.get("run_id") == run_dir.name:
                            verdict = row.get("verdict") or ""
                            valid = row.get("valid") or ""
                            try:
                                dur = float(row.get("duration_s") or dur)
                            except ValueError:
                                pass
                            break

        if status == "SWITCH_TO_PAID":
            append_result({
                "ts": datetime.now().isoformat(timespec="seconds"),
                "phase": "batch", "actor": actor, "profile": profile,
                "scenario": scenario, "variant": variant, "attempt": attempts + 1,
                "replaces_run_id": replaces, "new_run_id": run_dir.name,
                "verdict": verdict, "valid": valid, "duration_s": f"{dur:.1f}",
                "status": "SWITCH_TO_PAID", "fail_reason": fail_reason,
                "notes": f"model={current_model()};will_retry_paid", "rerun": "True",
            })
            log(f"FREE LIMIT → switch to paid ({fail_reason}) dir={run_dir.name}")
            set_model("paid", st)
            rem_before_paid_oc = openrouter_remaining()
            st["rem_at_paid_start"] = rem_before_paid_oc
            save_state(st)
            continue

        append_result({
            "ts": datetime.now().isoformat(timespec="seconds"),
            "phase": "batch", "actor": actor, "profile": profile,
            "scenario": scenario, "variant": variant, "attempt": attempts + 1,
            "replaces_run_id": replaces, "new_run_id": run_dir.name,
            "verdict": verdict, "valid": valid, "duration_s": f"{dur:.1f}",
            "status": status if status != "FAIL_FAST" else "FAIL_FAST",
            "fail_reason": fail_reason,
            "notes": f"rc={rc};model={current_model()};tier={tier}", "rerun": "True",
        })

        if status == "FAIL_FAST":
            log(f"FAIL-FAST: {fail_reason} dir={run_dir.name}")
            cell_attempts[key] = attempts + 1
            st["cell_attempts"] = cell_attempts
            st["stopped_reason"] = fail_reason
            rem = openrouter_remaining()
            st["rem_at_stop"] = rem
            save_state(st)
            log(f"remaining after stop={rem}")
            return 3

        if status == "PASS":
            cell_attempts[key] = 0
            log(f"PASS {run_dir.name} verdict={verdict} dur={dur:.1f}")
        else:
            cell_attempts[key] = attempts + 1
            log(f"FAIL {fail_reason} dir={run_dir.name}")
            if cell_attempts[key] >= 2:
                log(f"cell {key} exhausted 2 attempts → skip further slots")
                skipped = set(st.get("skipped_cells") or [])
                skipped.add(key)
                st["skipped_cells"] = list(skipped)

        st["cell_attempts"] = cell_attempts
        save_state(st)

        if actor == "opencode" and oc_since_balance >= OC_BALANCE_EVERY:
            rem = openrouter_remaining()
            oc_since_balance = 0
            log(f"balance check (every {OC_BALANCE_EVERY} OC) remaining={rem}")
            if rem is not None and rem < BUDGET_FLOOR:
                log(f"PLANNED STOP: limit_remaining={rem} < {BUDGET_FLOOR}")
                st["stopped_reason"] = f"budget_floor:{rem}"
                st["rem_at_stop"] = rem
                save_state(st)
                return 4

    rem_end = openrouter_remaining()
    st[f"rem_at_{phase}_end"] = rem_end
    st[f"{phase}_complete"] = True
    rem_paid0 = st.get("rem_at_paid_start")
    if rem_paid0 is not None and rem_end is not None and phase == "oc":
        paid_n = 0
        if RESULTS.is_file():
            with open(RESULTS) as f:
                for r in csv.DictReader(f, delimiter="\t"):
                    notes = r.get("notes") or ""
                    if r.get("actor") == "opencode" and "tier=paid" in notes:
                        if r.get("status") in ("PASS", "FAIL", "FAIL_FAST"):
                            paid_n += 1
        spent = float(rem_paid0) - float(rem_end)
        st["paid_oc_runs_approx"] = paid_n
        st["paid_spent_approx"] = spent
        if paid_n > 0:
            st["avg_oc_cost_paid"] = spent / paid_n
            log(f"avg OC cost (paid) ≈ ${spent/paid_n:.4f} (n={paid_n}, spent={spent:.4f})")
        else:
            log(f"paid rem {rem_paid0}→{rem_end} spent={spent:.4f}; paid_n={paid_n}")
    save_state(st)
    log(f"[{phase}] COMPLETE remaining={rem_end}")
    return 0


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument(
        "--phase",
        choices=("smoke", "oc", "cursor"),
        required=True,
        help="smoke=1 OC free check; oc=A+R opencode; cursor=remaining cursor cells",
    )
    args = ap.parse_args()
    load_dotenv()
    # Ensure .env paid default does not override free start unless already switched
    st = load_state()

    BATCH_LOG.parent.mkdir(parents=True, exist_ok=True)
    with open(BATCH_LOG, "a") as f:
        f.write(f"\n[batch] {args.phase} start {datetime.now().isoformat(timespec='seconds')}\n")

    if args.phase == "smoke":
        return phase_smoke(st)
    return run_batch_phase(args.phase, st)


if __name__ == "__main__":
    sys.exit(main())
