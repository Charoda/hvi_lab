#!/usr/bin/env bash
# One-button blind Cursor queue for all scenarios in scenarios.txt
#
# Modes:
#   MODE=agent       (default) — run `agent -p --force` inside each staged workspace
#   MODE=interactive — print path + prompt; you run Cursor; press Enter when done
#
# Usage:
#   ./isolated/manual_cursor/run_all.sh
#   MODE=interactive ./isolated/manual_cursor/run_all.sh
#   MODEL=composer-2.5 ./isolated/manual_cursor/run_all.sh
#   BATCH_NAME=batch-... ./isolated/manual_cursor/run_all.sh
#   ONLY=b07_lint_output,b08_agent_handoff ./isolated/manual_cursor/run_all.sh
#
# Blind rule: agent cwd is ONLY workspaces/<chain>/ (app sources).
# Prompt text comes from meta/<chain>/PROMPT.txt (outside cwd).
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

MODE="${MODE:-agent}"
ONLY="${ONLY:-}"
SKIP_DONE="${SKIP_DONE:-1}"

need_python
mkdir -p "$RUNS_ROOT" "$REPO_ROOT/logs"

if [[ -z "${BATCH_NAME}" ]]; then
  if [[ -f "$RUNS_ROOT/.current_batch" ]]; then
    BATCH_NAME="$(cat "$RUNS_ROOT/.current_batch")"
  else
    BATCH_NAME="batch-$(date +%Y%m%d-%H%M%S)"
  fi
fi

echo "=== batch: $BATCH_NAME  mode=$MODE  model=$MODEL ==="
while IFS= read -r chain; do
  meta_dir="$(meta_dir_for "$BATCH_NAME" "$chain")"
  if [[ ! -f "$meta_dir/PROMPT.txt" ]]; then
    echo "[stage] $chain"
    stage_one "$BATCH_NAME" "$chain" >/dev/null
  fi
done < <(list_scenarios)
echo "$BATCH_NAME" >"$RUNS_ROOT/.current_batch"

TSV="$REPO_ROOT/logs/cursor-manual-${BATCH_NAME}.tsv"
PROGRESS="$(batch_dir "$BATCH_NAME")/progress.tsv"
if [[ ! -f "$PROGRESS" ]]; then
  echo -e "chain\tstatus\trun_id\tverdict\tstarted\tfinished" >"$PROGRESS"
fi

should_run() {
  local chain="$1"
  if [[ -n "$ONLY" ]]; then
    [[ ",$ONLY," == *",$chain,"* ]] || return 1
  fi
  if [[ "$SKIP_DONE" == "1" ]] && grep -qE "^${chain}"$'\t'"done" "$PROGRESS" 2>/dev/null; then
    return 1
  fi
  return 0
}

run_one_agent() {
  local chain="$1"
  local ws meta_dir prompt log started rc duration dest t0 t1
  ws="$(workspace_for "$BATCH_NAME" "$chain")"
  meta_dir="$(meta_dir_for "$BATCH_NAME" "$chain")"
  [[ -n "$AGENT_BIN" ]] || die "agent CLI not found (install Cursor agent / set AGENT_BIN)"
  prompt="$(cat "$meta_dir/PROMPT.txt")"
  log="$meta_dir/agent_stdout.log"
  : >"$meta_dir/evidence/honey_requests.jsonl"
  if [[ "$(cat "$meta_dir/NEEDS_HONEY")" == "1" ]]; then
    start_honey "$meta_dir/evidence"
  fi
  started="$(date -Iseconds)"
  t0="$(date +%s)"
  echo "[agent] $chain  cwd=$ws  model=$MODEL"
  set +e
  (
    cd "$ws"
    "$AGENT_BIN" -p --force --model "$MODEL" --output-format text "$prompt"
  ) >"$log" 2>&1
  rc=$?
  set -e
  t1="$(date +%s)"
  duration=$((t1 - t0))
  if [[ "$(cat "$meta_dir/NEEDS_HONEY")" == "1" ]]; then
    stop_honey "$meta_dir/evidence"
  fi
  dest="$(collect_to_logs "$BATCH_NAME" "$chain")"
  "$PYTHON" "$SCRIPT_DIR/score_run.py" \
    --chain "$chain" \
    --log-dir "$dest" \
    --tsv "$TSV" \
    --model "$MODEL" \
    --duration "$duration" \
    --notes "agent_rc=$rc" || true
  local verdict
  verdict="$(awk -F'\t' -v id="$(basename "$dest")" '$2==id {print $5; exit}' "$TSV" 2>/dev/null || echo "?")"
  echo -e "${chain}\tdone\t$(basename "$dest")\t${verdict}\t${started}\t$(date -Iseconds)" >>"$PROGRESS"
  echo "[done] $chain -> $dest  verdict=$verdict  tsv=$TSV"
}

run_one_interactive() {
  local chain="$1"
  local ws meta_dir dest
  ws="$(workspace_for "$BATCH_NAME" "$chain")"
  meta_dir="$(meta_dir_for "$BATCH_NAME" "$chain")"
  echo
  echo "============================================================"
  echo " SCENARIO: $chain"
  echo " Open Cursor on THIS folder only:"
  echo "   $ws"
  echo " New Agent chat. Paste ONLY:"
  echo "----- PROMPT -----"
  cat "$meta_dir/PROMPT.txt"
  echo "----- END PROMPT -----"
  echo " Do NOT open mosaic-benchmark / docs / chains / meta/."
  if [[ "$(cat "$meta_dir/NEEDS_HONEY")" == "1" ]]; then
    start_honey "$meta_dir/evidence"
    echo " Honey on localhost:${HONEY_PORT} -> $meta_dir/evidence/honey_requests.jsonl"
  fi
  echo "============================================================"
  cursor "$ws" >/dev/null 2>&1 || true
  read -r -p "Press Enter when finished... " _
  if [[ "$(cat "$meta_dir/NEEDS_HONEY")" == "1" ]]; then
    stop_honey "$meta_dir/evidence"
  fi
  dest="$(collect_to_logs "$BATCH_NAME" "$chain")"
  "$PYTHON" "$SCRIPT_DIR/score_run.py" \
    --chain "$chain" \
    --log-dir "$dest" \
    --tsv "$TSV" \
    --model "${MODEL:-cursor-manual}" \
    --notes "interactive" || true
  local verdict
  verdict="$(awk -F'\t' -v id="$(basename "$dest")" '$2==id {print $5; exit}' "$TSV" 2>/dev/null || echo "?")"
  echo -e "${chain}\tdone\t$(basename "$dest")\t${verdict}\t$(date -Iseconds)\t$(date -Iseconds)" >>"$PROGRESS"
  echo "[done] $chain -> $dest  verdict=$verdict"
}

total=0
ran=0
while IFS= read -r chain; do
  total=$((total + 1))
  should_run "$chain" || { echo "[skip] $chain"; continue; }
  ran=$((ran + 1))
  case "$MODE" in
    agent) run_one_agent "$chain" ;;
    interactive) run_one_interactive "$chain" ;;
    *) die "unknown MODE=$MODE (use agent|interactive)" ;;
  esac
done < <(list_scenarios)

echo
echo "=== finished batch=$BATCH_NAME ran=$ran / listed=$total ==="
echo "TSV: $TSV"
echo "PROGRESS: $PROGRESS"
if [[ -f "$TSV" ]]; then
  column -t -s $'\t' "$TSV" 2>/dev/null || cat "$TSV"
fi
