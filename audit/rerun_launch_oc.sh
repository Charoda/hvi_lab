#!/usr/bin/env bash
# OC phase launcher: smoke (free) → batch OC. Survives SSH drop when run under tmux.
set -euo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO"
mkdir -p audit/rerun_logs
LOG="audit/rerun_logs/batch.log"
REPORT_DATE="$(date +%Y%m%d)"

{
  echo ""
  echo "======== OC LAUNCH $(date -Iseconds) ========"
} >>"$LOG"

export PYTHONUNBUFFERED=1
# Start free; driver may switch to paid. Do not let .env paid stick for this session.
export MOSAIC_OPENCODE_MODEL="openrouter/nvidia/nemotron-3-ultra-550b-a55b:free"

echo "[launch] smoke…" | tee -a "$LOG"
if ! python3 audit/run_batch.py --phase smoke; then
  echo "[launch] SMOKE FAILED — stop" | tee -a "$LOG"
  exit 1
fi

echo "[launch] OC batch…" | tee -a "$LOG"
set +e
python3 audit/run_batch.py --phase oc
rc=$?
set -e
echo "[launch] OC batch exit=$rc" | tee -a "$LOG"

echo "[launch] validate_all_runs.py…" | tee -a "$LOG"
python3 audit/validate_all_runs.py >>"audit/rerun_logs/validate_${REPORT_DATE}.log" 2>&1 || true

python3 - <<'PY' >>"$LOG" 2>&1
from pathlib import Path
from datetime import datetime
import csv, json
REPO = Path(".")
st = json.loads((REPO/"audit/rerun_driver_state.json").read_text()) if (REPO/"audit/rerun_driver_state.json").is_file() else {}
results = list(csv.DictReader(open(REPO/"audit/rerun_results.tsv"), delimiter="\t")) if (REPO/"audit/rerun_results.tsv").is_file() else []
date = datetime.now().strftime("%Y%m%d")
path = REPO/f"audit/RERUN_REPORT_{date}.md"
# counts
from collections import Counter
c = Counter(r.get("status") for r in results if r.get("phase")=="batch" and r.get("actor")=="opencode")
lines = [
  f"# RERUN REPORT {date}",
  "",
  f"Generated: {datetime.now().isoformat(timespec='seconds')}",
  "",
  "## Scope",
  "- Phase: OpenCode only (strict b15–b20 → B19 mal → rest A OC → R).",
  "- Cursor (off/b16_mal, normal/b19_mal, B_profile) deferred to a separate step.",
  "- Full-plan 4× b15 mal strict ASR_USABLE: not rerun (same logic as B_attr).",
  "",
  "## Model",
  f"- tier at end: `{st.get('model_tier')}`",
  f"- model: `{st.get('model')}`",
  f"- stopped_reason: `{st.get('stopped_reason')}`",
  f"- rem_at_oc_start: {st.get('rem_at_oc_start')}",
  f"- rem_at_oc_end / rem_at_stop: {st.get('rem_at_oc_end') or st.get('rem_at_stop')}",
  f"- rem_at_paid_start: {st.get('rem_at_paid_start')}",
  f"- avg_oc_cost_paid: {st.get('avg_oc_cost_paid')}",
  f"- oc_runs_done: {st.get('oc_runs_done')}",
  f"- oc_complete: {st.get('oc_complete')}",
  "",
  "## Batch status counts (OC)",
  *[f"- {k}: {v}" for k,v in sorted(c.items())],
  "",
  "## Notes",
  "- Old logs/TSV not modified; results appended to `audit/rerun_results.tsv`.",
  "- Validate log: `audit/rerun_logs/validate_*.log`; summary also in `audit/validation_summary.md`.",
  "",
]
path.write_text("\n".join(lines) + "\n")
print(f"[launch] wrote {path}")
PY

echo "[launch] done rc=$rc — Cursor phase NOT started (separate step)" | tee -a "$LOG"
exit "$rc"
