#!/usr/bin/env bash
# Shared helpers for blind Cursor manual / agent-CLI runs.
# No chain spoilers — only paths and meta from chain.json fields task_id / sandbox_env.

set -euo pipefail

MANUAL_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$MANUAL_ROOT/../.." && pwd)"
PYTHON="${PYTHON:-$HOME/.pyenv/versions/mosaic-311/bin/python}"
SCENARIOS_FILE="${SCENARIOS_FILE:-$MANUAL_ROOT/scenarios.txt}"
RUNS_ROOT="${RUNS_ROOT:-$HOME/mosaic-manual-runs}"
BATCH_NAME="${BATCH_NAME:-}"
AGENT_BIN="${AGENT_BIN:-$(command -v agent || true)}"
MODEL="${MODEL:-auto}"
HONEY_PORT="${HONEY_PORT:-8080}"

die() { echo "error: $*" >&2; exit 1; }

need_python() {
  [[ -x "$PYTHON" ]] || die "python not found: $PYTHON (set PYTHON=...)"
}

list_scenarios() {
  grep -vE '^\s*(#|$)' "$SCENARIOS_FILE"
}

batch_dir() {
  local name="$1"
  echo "$RUNS_ROOT/$name"
}

resolve_meta() {
  # stdout: task_id<TAB>app_dir<TAB>honey(0|1)<TAB>poc_module
  local chain="$1"
  need_python
  "$PYTHON" - "$REPO_ROOT" "$chain" <<'PY'
import json, sys
from pathlib import Path
repo, chain = Path(sys.argv[1]), sys.argv[2]
meta = json.loads((repo / "benchmark/chains" / chain / "chain.json").read_text())
sys.path.insert(0, str(repo))
from mosaic.deploy import ABC_BENCH_APPS
cfg = ABC_BENCH_APPS[meta["task_id"]]
honey = 1 if (meta.get("sandbox_env") or {}).get("HONEY_PORT") else 0
print(f"{meta['task_id']}\t{cfg.app_dir}\t{honey}\t{meta.get('poc_module','')}")
PY
}

stage_one() {
  local batch="$1" chain="$2"
  local meta task app_dir honey poc ws meta_dir
  meta="$(resolve_meta "$chain")"
  IFS=$'\t' read -r task app_dir honey poc <<<"$meta"
  ws="$(batch_dir "$batch")/workspaces/$chain"
  meta_dir="$(batch_dir "$batch")/meta/$chain"
  # Workspace for the actor: ONLY app sources (no chain.json / poc / docs).
  rm -rf "$ws"
  mkdir -p "$ws"
  cp -a "$REPO_ROOT/benchmark/apps/$task/$app_dir/." "$ws/"
  # Harness meta lives outside the Cursor workspace tree.
  mkdir -p "$meta_dir/evidence"
  cp "$REPO_ROOT/benchmark/chains/$chain/agent_prompt.txt" "$meta_dir/PROMPT.txt"
  printf '%s\n' "$chain" >"$meta_dir/CHAIN_ID"
  printf '%s\n' "$task" >"$meta_dir/TASK_ID"
  printf '%s\n' "$honey" >"$meta_dir/NEEDS_HONEY"
  printf '%s\n' "$poc" >"$meta_dir/POC_MODULE"
  printf '%s\n' "$ws" >"$meta_dir/WORKSPACE"
  echo "$ws"
}

meta_dir_for() {
  echo "$(batch_dir "$1")/meta/$2"
}

workspace_for() {
  echo "$(batch_dir "$1")/workspaces/$2"
}

start_honey() {
  local evidence_dir="$1"
  local pidfile="$evidence_dir/honey.pid"
  local logfile="$evidence_dir/honey_listener.log"
  mkdir -p "$evidence_dir"
  if [[ -f "$pidfile" ]] && kill -0 "$(cat "$pidfile")" 2>/dev/null; then
    return 0
  fi
  # free port if stale listener
  if command -v fuser >/dev/null 2>&1; then
    fuser -k "${HONEY_PORT}/tcp" 2>/dev/null || true
  fi
  nohup "$PYTHON" "$REPO_ROOT/isolated/honey_listener.py" "$HONEY_PORT" \
    "$evidence_dir/honey_requests.jsonl" >"$logfile" 2>&1 &
  echo $! >"$pidfile"
  sleep 0.3
  kill -0 "$(cat "$pidfile")" 2>/dev/null || die "honey failed to start (see $logfile)"
}

stop_honey() {
  local evidence_dir="$1"
  local pidfile="$evidence_dir/honey.pid"
  if [[ -f "$pidfile" ]]; then
    kill "$(cat "$pidfile")" 2>/dev/null || true
    rm -f "$pidfile"
  fi
}

collect_to_logs() {
  local batch="$1" chain="$2"
  local ws meta_dir run_id dest
  ws="$(workspace_for "$batch" "$chain")"
  meta_dir="$(meta_dir_for "$batch" "$chain")"
  run_id="cursor-manual-${chain}-$(date +%Y%m%d-%H%M%S)"
  dest="$REPO_ROOT/logs/$run_id"
  mkdir -p "$dest"
  cp -a "$ws" "$dest/final_app"
  if [[ -d "$meta_dir/evidence" ]]; then
    cp -a "$meta_dir/evidence/." "$dest/" 2>/dev/null || true
  fi
  if [[ -f "$meta_dir/agent_stdout.log" ]]; then
    cp "$meta_dir/agent_stdout.log" "$dest/cursor_agent.log"
  fi
  printf '%s\n' "$run_id" >"$meta_dir/LAST_RUN_ID"
  printf '%s\n' "$dest" >"$meta_dir/LAST_LOG_DIR"
  echo "$dest"
}
