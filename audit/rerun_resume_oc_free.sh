#!/usr/bin/env bash
# Resume OC on free Nemotron; auto-switch to paid on free limits / provider 502.
set -euo pipefail
REPO="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO"
mkdir -p audit/rerun_logs
LOG="audit/rerun_logs/batch.log"
REPORT_DATE="$(date +%Y%m%d)"

{
  echo ""
  echo "======== OC RESUME FREE $(date -Iseconds) ========"
} >>"$LOG"

export PYTHONUNBUFFERED=1
export MOSAIC_OPENCODE_MODEL="openrouter/nvidia/nemotron-3-ultra-550b-a55b:free"

python3 - <<'PY'
import json
from pathlib import Path
p = Path("audit/rerun_driver_state.json")
st = json.loads(p.read_text()) if p.is_file() else {}
st["smoke_ok"] = True
st["model_tier"] = "free"
st["model"] = "openrouter/nvidia/nemotron-3-ultra-550b-a55b:free"
st["stopped_reason"] = None
st["oc_complete"] = False
st.pop("rem_at_stop", None)
p.write_text(json.dumps(st, indent=2, ensure_ascii=False) + "\n")
print("[resume-free] state → free; will SWITCH_TO_PAID on free limits/502")
PY

echo "[resume-free] OC batch…" | tee -a "$LOG"
set +e
python3 audit/run_batch.py --phase oc
rc=$?
set -e
echo "[resume-free] OC batch exit=$rc" | tee -a "$LOG"

echo "[resume-free] validate_all_runs.py…" | tee -a "$LOG"
python3 audit/validate_all_runs.py >>"audit/rerun_logs/validate_${REPORT_DATE}.log" 2>&1 || true

python3 - <<'PY'
from pathlib import Path
from datetime import datetime
from collections import Counter
import csv, json
REPO = Path(".")
st = json.loads((REPO/"audit/rerun_driver_state.json").read_text())
results = list(csv.DictReader(open(REPO/"audit/rerun_results.tsv"), delimiter="\t"))
date = datetime.now().strftime("%Y%m%d")
path = REPO/f"audit/RERUN_REPORT_{date}.md"
c = Counter(r.get("status") for r in results if r.get("phase")=="batch" and r.get("actor")=="opencode")
lines = [
  f"# RERUN REPORT {date}",
  "",
  f"Generated: {datetime.now().isoformat(timespec='seconds')}",
  "",
  "## Scope",
  "- OpenCode A+R; Cursor deferred.",
  "- Full-plan 4× b15 mal ASR_USABLE: not rerun.",
  "",
  "## Model",
  f"- tier at end: `{st.get('model_tier')}`",
  f"- model: `{st.get('model')}`",
  f"- stopped_reason: `{st.get('stopped_reason')}`",
  f"- rem_at_paid_start: {st.get('rem_at_paid_start')}",
  f"- rem end/stop: {st.get('rem_at_oc_end') or st.get('rem_at_stop')}",
  f"- avg_oc_cost_paid: {st.get('avg_oc_cost_paid')}",
  f"- oc_runs_done: {st.get('oc_runs_done')}",
  f"- oc_complete: {st.get('oc_complete')}",
  "",
  "## Batch status counts (OC)",
  *[f"- {k}: {v}" for k,v in sorted(c.items())],
  "",
]
path.write_text("\n".join(lines) + "\n")
print(f"[resume-free] wrote {path}")
PY

echo "[resume-free] done rc=$rc" | tee -a "$LOG"
exit "$rc"
