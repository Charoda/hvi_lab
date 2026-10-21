#!/usr/bin/env bash
# =============================================================================
# 13. Harness — тестовый стенд / обвязка (MOSAIC agent-behavior)
# =============================================================================
# Программная инфраструктура, которая:
#   • Подготавливает тестовый репозиторий
#   • Запускает агента (opencode | cursor)
#   • Передаёт ему задачу (agent_prompt.txt)
#   • Собирает и сохраняет логи действий
#   • Оценивает результат: ASR / IRR / TCR / FPR
#
# На каждый batch пишет ДВА файла прогонов + метрики:
#   logs/harness-<batch>/malicious.tsv
#   logs/harness-<batch>/benign.tsv
#   logs/harness-<batch>/metrics.{tsv,json}
#
# Usage:
#   ./isolated/harness/run.sh --actor opencode
#   ./isolated/harness/run.sh --actor cursor
#   ./isolated/harness/run.sh --actor opencode --profile strict --scenarios b07,b08
#   ./isolated/harness/run.sh --actor opencode --profile all --trials 1
#   ./isolated/harness/run.sh --actor cursor --mode interactive --scenarios b01-b14
#   ./isolated/harness/run.sh --actor cursor --profile all --scenarios b07,b08
#   MODEL=composer-2.5 ./isolated/harness/run.sh --actor cursor --profile strict
#
# Cursor actor (MODE=agent) требует CURSOR_API_KEY в .env или окружении:
#   CURSOR_API_KEY=...
#   # опционально: CURSOR_API_ENDPOINT=https://api2.cursor.sh
#
# Permission profiles (оба актора): off | normal | strict | all
#   opencode → configs/opencode/*.json
#   cursor   → configs/cursor/*.json + флаги (--force / --auto-review / --sandbox)
# =============================================================================
set -euo pipefail

HARNESS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$HARNESS_DIR/../.." && pwd)"
PYTHON="${PYTHON:-$HOME/.pyenv/versions/mosaic-311/bin/python}"
SCENARIOS_FILE="${SCENARIOS_FILE:-$HARNESS_DIR/scenarios.txt}"
MANUAL_DIR="$REPO_ROOT/isolated/manual_cursor"
# shellcheck source=/dev/null
source "$MANUAL_DIR/common.sh"
# Override scenarios file to harness list
SCENARIOS_FILE="${SCENARIOS_FILE:-$HARNESS_DIR/scenarios.txt}"

load_dotenv() {
  # Load KEY=VAL from .env without overriding already-exported vars. No secrets printed.
  local env_file="$REPO_ROOT/.env"
  [[ -f "$env_file" ]] || return 0
  while IFS= read -r line || [[ -n "$line" ]]; do
    case "$line" in
      ''|'#'*) continue ;;
      *=*)
        local key="${line%%=*}" val="${line#*=}"
        key="${key#"${key%%[![:space:]]*}"}"
        key="${key%"${key##*[![:space:]]}"}"
        val="${val#"${val%%[![:space:]]*}"}"
        val="${val%"${val##*[![:space:]]}"}"
        val="${val#\"}"; val="${val%\"}"
        val="${val#\'}"; val="${val%\'}"
        if [[ -n "$key" && -z "${!key:-}" ]]; then
          export "$key=$val"
        fi
        ;;
    esac
  done <"$env_file"
}

load_dotenv

ACTOR=""
PROFILES=("off")
TRIALS=1
TIMEOUT="${TIMEOUT:-2400}"
NETWORK="${NETWORK:-allowlist}"
MODE="${MODE:-agent}"          # cursor: agent|interactive
SCENARIO_SPEC="all"            # all | b07,b08 | b01-b14
BATCH_NAME="${BATCH_NAME:-}"
SKIP_DONE="${SKIP_DONE:-1}"

die() { echo "error: $*" >&2; exit 1; }

require_cursor_api_key() {
  if [[ -z "${CURSOR_API_KEY:-}" ]]; then
    die "для --actor cursor нужен CURSOR_API_KEY (положите в .env или export).
  Пример в .env:
    CURSOR_API_KEY=key_...
  Опционально:
    CURSOR_API_ENDPOINT=https://api2.cursor.sh
    MOSAIC_CURSOR_MODEL=composer-2.5"
  fi
  # Prefer harness/model env over bare auto when set in .env
  if [[ -z "${MODEL}" || "${MODEL}" == "auto" ]]; then
    if [[ -n "${MOSAIC_CURSOR_MODEL:-}" ]]; then
      MODEL="$MOSAIC_CURSOR_MODEL"
    fi
  fi
}

usage() {
  sed -n '2,28p' "$0" | sed 's/^# \?//'
  exit 2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --actor) ACTOR="${2:-}"; shift 2 ;;
    --profile|--permission-profile)
      if [[ "${2:-}" == "all" ]]; then
        PROFILES=(off normal strict)
      else
        PROFILES=("${2:-}")
      fi
      shift 2
      ;;
    --trials|-n) TRIALS="${2:-1}"; shift 2 ;;
    --timeout) TIMEOUT="${2:-}"; shift 2 ;;
    --network) NETWORK="${2:-}"; shift 2 ;;
    --mode) MODE="${2:-}"; shift 2 ;;
    --scenarios) SCENARIO_SPEC="${2:-}"; shift 2 ;;
    --batch) BATCH_NAME="${2:-}"; shift 2 ;;
    --model) MODEL="${2:-}"; shift 2 ;;
    -h|--help) usage ;;
    *) die "unknown arg: $1 (see --help)" ;;
  esac
done

[[ -n "$ACTOR" ]] || die "required: --actor opencode|cursor"
[[ "$ACTOR" == "opencode" || "$ACTOR" == "cursor" ]] || die "actor must be opencode|cursor"
need_python
[[ -x "$PYTHON" ]] || die "bad PYTHON=$PYTHON"
if [[ "$ACTOR" == "cursor" && "$MODE" == "agent" ]]; then
  require_cursor_api_key
  echo "[harness] cursor auth: CURSOR_API_KEY (len=${#CURSOR_API_KEY}), model=${MODEL:-auto}"
fi

expand_scenarios() {
  local spec="$1"
  local -a all=()
  mapfile -t all < <(grep -vE '^\s*(#|$)' "$HARNESS_DIR/scenarios.txt")
  if [[ "$spec" == "all" ]]; then
    printf '%s\n' "${all[@]}"
    return
  fi
  local -a out=()
  IFS=',' read -ra parts <<<"$spec"
  for p in "${parts[@]}"; do
    p="${p// /}"
    if [[ "$p" =~ ^b([0-9]{2})-b([0-9]{2})$ ]]; then
      local a=${BASH_REMATCH[1]} b=${BASH_REMATCH[2]}
      local id
      for id in "${all[@]}"; do
        if [[ "$id" =~ ^b([0-9]{2})_ ]]; then
          local n=${BASH_REMATCH[1]}
          if (( 10#$n >= 10#$a && 10#$n <= 10#$b )); then
            out+=("$id")
          fi
        fi
      done
    else
      # exact base id or prefix match b07 → b07_lint_output
      local matched=0 id
      for id in "${all[@]}"; do
        if [[ "$id" == "$p" || "$id" == "${p}_"* ]]; then
          out+=("$id"); matched=1
        fi
      done
      [[ "$matched" == 1 ]] || die "unknown scenario: $p"
    fi
  done
  printf '%s\n' "${out[@]}" | awk 'NF && !seen[$0]++'
}

if [[ -z "$BATCH_NAME" ]]; then
  BATCH_NAME="harness-${ACTOR}-$(date +%Y%m%d-%H%M%S)"
fi

OUT_DIR="$REPO_ROOT/logs/$BATCH_NAME"
mkdir -p "$OUT_DIR"
MAL_TSV="$OUT_DIR/malicious.tsv"
BEN_TSV="$OUT_DIR/benign.tsv"
PROGRESS="$OUT_DIR/progress.tsv"
[[ -f "$PROGRESS" ]] || echo -e "chain\tvariant\tprofile\tidx\tstatus\trun_id" >"$PROGRESS"

mapfile -t SCENARIOS < <(expand_scenarios "$SCENARIO_SPEC")
[[ ${#SCENARIOS[@]} -gt 0 ]] || die "no scenarios selected"

# Persist run config
cat >"$OUT_DIR/run_config.json" <<EOF
{
  "batch": "$BATCH_NAME",
  "actor": "$ACTOR",
  "model": "${MODEL:-}",
  "profiles": [$(printf '"%s",' "${PROFILES[@]}" | sed 's/,$//')],
  "trials": $TRIALS,
  "network": "$NETWORK",
  "timeout": $TIMEOUT,
  "mode": "$MODE",
  "scenarios": [$(printf '"%s",' "${SCENARIOS[@]}" | sed 's/,$//')]
}
EOF

echo "=== Harness batch=$BATCH_NAME actor=$ACTOR ==="
echo "scenarios (${#SCENARIOS[@]}): ${SCENARIOS[*]}"
echo "profiles: ${PROFILES[*]}  trials=$TRIALS"
echo "out: $OUT_DIR"
echo "  malicious.tsv / benign.tsv / metrics.*"

already_done() {
  local chain="$1" variant="$2" profile="$3" idx="$4"
  [[ "$SKIP_DONE" == "1" ]] || return 1
  grep -qE "^${chain}"$'\t'"${variant}"$'\t'"${profile}"$'\t'"${idx}"$'\t'"done" "$PROGRESS" 2>/dev/null
}

mark_done() {
  echo -e "$1\t$2\t$3\t$4\tdone\t$5" >>"$PROGRESS"
}

tsv_for_variant() {
  [[ "$1" == "benign" ]] && echo "$BEN_TSV" || echo "$MAL_TSV"
}

chain_for() {
  local base="$1" variant="$2"
  if [[ "$variant" == "benign" ]]; then
    echo "${base}_benign"
  else
    echo "$base"
  fi
}

ensure_benign_exists() {
  local base="$1"
  [[ -f "$REPO_ROOT/benchmark/chains/${base}_benign/chain.json" ]]
}

# --- OpenCode path ----------------------------------------------------------
run_opencode_one() {
  local base="$1" variant="$2" profile="$3" idx="$4"
  local chain tsv log_dir
  chain="$(chain_for "$base" "$variant")"
  tsv="$(tsv_for_variant "$variant")"
  if [[ "$variant" == "benign" ]] && ! ensure_benign_exists "$base"; then
    echo "[skip] no benign twin for $base"
    return 0
  fi
  if already_done "$chain" "$variant" "$profile" "$idx"; then
    echo "[skip] $chain $profile #$idx"
    return 0
  fi
  echo "===== opencode $variant / $profile / $chain / trial $idx ====="
  local tmp_log="/tmp/harness-${chain}-${profile}-${idx}-$$.log"
  set +e
  "$REPO_ROOT/run_isolated.sh" "$chain" \
    --actor opencode \
    --permission-profile "$profile" \
    --network "$NETWORK" \
    --timeout "$TIMEOUT" \
    --verbose >"$tmp_log" 2>&1
  local rc=$?
  set -e
  log_dir="$(ls -td "$REPO_ROOT/logs/${chain}-"* 2>/dev/null | head -1 || true)"
  if [[ -z "$log_dir" || ! -f "$log_dir/result.json" ]]; then
    echo -e "${base}\t${variant}\t${profile}\t${idx}\tERROR\tNO_RUN\t\t\tFalse\t\t\t\t\t\t\t\t\t\trc=$rc no result.json" \
      | { [[ -f "$tsv" ]] || echo -e "scenario\tvariant\tprofile\trepeat_idx\trun_id\tactor\tmodel\tverdict\tvalid\tattack_attempted\tattack_success\tutility_success\ttests_passed\tpermission_blocked_attack\tpermission_blocked_utility\tdefense_false_positive\tstopped_by\tduration_s\tevidence\tnotes"; cat; } >>"$tsv"
    echo "[error] no result.json (rc=$rc) — see $tmp_log"
    return 0
  fi
  # keep harness copy of raw log
  mkdir -p "$OUT_DIR/raw"
  cp "$tmp_log" "$OUT_DIR/raw/$(basename "$log_dir").console.log" 2>/dev/null || true
  "$PYTHON" "$HARNESS_DIR/record_run.py" \
    --source opencode \
    --chain "$chain" \
    --scenario-base "$base" \
    --variant "$variant" \
    --profile "$profile" \
    --idx "$idx" \
    --log-dir "$log_dir" \
    --tsv "$tsv" \
    --notes "console=$tmp_log" \
    --rescore-poc || true
  mark_done "$chain" "$variant" "$profile" "$idx" "$(basename "$log_dir")"
}

# --- Cursor permission profiles ---------------------------------------------
cursor_profile_config() {
  local profile="$1"
  local cfg="$REPO_ROOT/configs/cursor/${profile}.json"
  [[ -f "$cfg" ]] || die "missing Cursor profile config: $cfg (see configs/cursor/README.md)"
  echo "$cfg"
}

# Prepare isolated HOME so IDE ~/.cursor/cli-config.json is not mixed in.
prepare_cursor_home() {
  local profile="$1" meta_dir="$2"
  local home cfg
  home="$meta_dir/cursor_home_${profile}"
  cfg="$(cursor_profile_config "$profile")"
  rm -rf "$home"
  mkdir -p "$home/.cursor"
  # Strip harness-only _mosaic key — agent may ignore unknown keys, but keep cli-config clean.
  "$PYTHON" - "$cfg" "$home/.cursor/cli-config.json" <<'PY'
import json, sys
src, dst = sys.argv[1], sys.argv[2]
data = json.loads(open(src).read())
data.pop("_mosaic", None)
open(dst, "w").write(json.dumps(data, indent=2) + "\n")
PY
  cp "$cfg" "$home/.cursor/mosaic_profile.json"
  printf '%s\n' "$profile" >"$home/.cursor/MOSAIC_CURSOR_PROFILE"
  echo "$home"
}

# --- Cursor path ------------------------------------------------------------
run_cursor_one() {
  local base="$1" variant="$2" profile="$3" idx="$4"
  local chain tsv ws meta_dir batch_cursor
  chain="$(chain_for "$base" "$variant")"
  tsv="$(tsv_for_variant "$variant")"
  if [[ "$variant" == "benign" ]] && ! ensure_benign_exists "$base"; then
    echo "[skip] no benign twin for $base"
    return 0
  fi
  if already_done "$chain" "$variant" "$profile" "$idx"; then
    echo "[skip] $chain $profile #$idx"
    return 0
  fi

  batch_cursor="${BATCH_NAME}-workspaces"
  echo "===== cursor $variant / $profile / $chain / trial $idx (mode=$MODE) ====="
  # Prepare blind workspace (harness meta outside workspace)
  stage_one "$batch_cursor" "$chain" >/dev/null
  ws="$(workspace_for "$batch_cursor" "$chain")"
  meta_dir="$(meta_dir_for "$batch_cursor" "$chain")"

  local prompt log t0 t1 duration dest rc=0 cursor_home=""
  prompt="$(cat "$meta_dir/PROMPT.txt")"
  log="$meta_dir/agent_stdout_${profile}.log"
  : >"$meta_dir/evidence/honey_requests.jsonl"
  if [[ "$(cat "$meta_dir/NEEDS_HONEY")" == "1" ]]; then
    start_honey "$meta_dir/evidence"
  fi
  t0="$(date +%s)"
  if [[ "$MODE" == "interactive" ]]; then
    echo "Open Cursor ONLY on: $ws"
    echo "Profile hint (manual): $profile — see configs/cursor/${profile}.json"
    echo "----- PROMPT -----"
    echo "$prompt"
    echo "----- END -----"
    cursor "$ws" >/dev/null 2>&1 || true
    read -r -p "Enter when agent finished... " _
  else
    [[ -n "$AGENT_BIN" ]] || die "agent CLI not found; use MODE=interactive or install Cursor agent"
    require_cursor_api_key
    cursor_home="$(prepare_cursor_home "$profile" "$meta_dir")"
    set +e
    (
      cd "$ws"
      # Isolated HOME → per-run cli-config (profile). Auth via API key only.
      # Avoid bash arrays — safer if the script file is edited mid-run.
      export HOME="$cursor_home"
      case "$profile" in
        off)
          if [[ -n "${CURSOR_API_ENDPOINT:-}" ]]; then
            timeout "$TIMEOUT" "$AGENT_BIN" -p --force --sandbox disabled --trust \
              --api-key "$CURSOR_API_KEY" \
              --endpoint "$CURSOR_API_ENDPOINT" \
              --model "${MODEL:-auto}" \
              --output-format text \
              "$prompt"
          else
            timeout "$TIMEOUT" "$AGENT_BIN" -p --force --sandbox disabled --trust \
              --api-key "$CURSOR_API_KEY" \
              --model "${MODEL:-auto}" \
              --output-format text \
              "$prompt"
          fi
          ;;
        normal)
          if [[ -n "${CURSOR_API_ENDPOINT:-}" ]]; then
            timeout "$TIMEOUT" "$AGENT_BIN" -p --auto-review --sandbox disabled --trust \
              --api-key "$CURSOR_API_KEY" \
              --endpoint "$CURSOR_API_ENDPOINT" \
              --model "${MODEL:-auto}" \
              --output-format text \
              "$prompt"
          else
            timeout "$TIMEOUT" "$AGENT_BIN" -p --auto-review --sandbox disabled --trust \
              --api-key "$CURSOR_API_KEY" \
              --model "${MODEL:-auto}" \
              --output-format text \
              "$prompt"
          fi
          ;;
        strict)
          if [[ -n "${CURSOR_API_ENDPOINT:-}" ]]; then
            timeout "$TIMEOUT" "$AGENT_BIN" -p --force --sandbox enabled --trust \
              --api-key "$CURSOR_API_KEY" \
              --endpoint "$CURSOR_API_ENDPOINT" \
              --model "${MODEL:-auto}" \
              --output-format text \
              "$prompt"
          else
            timeout "$TIMEOUT" "$AGENT_BIN" -p --force --sandbox enabled --trust \
              --api-key "$CURSOR_API_KEY" \
              --model "${MODEL:-auto}" \
              --output-format text \
              "$prompt"
          fi
          ;;
        *)
          die "unknown Cursor profile: $profile (use off|normal|strict)"
          ;;
      esac
    ) >"$log" 2>&1
    rc=$?
    set -e
  fi
  t1="$(date +%s)"
  duration=$((t1 - t0))
  if [[ "$(cat "$meta_dir/NEEDS_HONEY")" == "1" ]]; then
    stop_honey "$meta_dir/evidence"
  fi

  # Collect into logs/ under harness-friendly run id
  local run_id dest
  run_id="cursor-${chain}-${profile}-$(date +%Y%m%d-%H%M%S)"
  dest="$REPO_ROOT/logs/$run_id"
  mkdir -p "$dest"
  cp -a "$ws" "$dest/final_app"
  cp -a "$meta_dir/evidence/." "$dest/" 2>/dev/null || true
  [[ -f "$log" ]] && cp "$log" "$dest/cursor_agent.log"
  if [[ -n "$cursor_home" && -f "$cursor_home/.cursor/cli-config.json" ]]; then
    cp "$cursor_home/.cursor/cli-config.json" "$dest/cursor_cli_config.json" 2>/dev/null || true
    cp "$cursor_home/.cursor/mosaic_profile.json" "$dest/cursor_profile.json" 2>/dev/null || true
  fi
  printf '%s\n' "$profile" >"$dest/cursor_profile_name.txt"
  printf '%s\n' "$run_id" >"$meta_dir/LAST_RUN_ID"

  "$PYTHON" "$HARNESS_DIR/record_run.py" \
    --source cursor \
    --chain "$chain" \
    --scenario-base "$base" \
    --variant "$variant" \
    --profile "$profile" \
    --idx "$idx" \
    --log-dir "$dest" \
    --tsv "$tsv" \
    --model "${MODEL:-auto}" \
    --duration "$duration" \
    --notes "agent_rc=$rc mode=$MODE profile=$profile" || true
  # symlink into batch out dir for convenience
  mkdir -p "$OUT_DIR/runs"
  ln -sfn "$dest" "$OUT_DIR/runs/$run_id" 2>/dev/null || true
  mark_done "$chain" "$variant" "$profile" "$idx" "$run_id"
}

# --- Main loop: scenario × variant × profile × trial -----------------------
for base in "${SCENARIOS[@]}"; do
  for variant in malicious benign; do
    for profile in "${PROFILES[@]}"; do
      for ((idx=1; idx<=TRIALS; idx++)); do
        case "$ACTOR" in
          opencode) run_opencode_one "$base" "$variant" "$profile" "$idx" ;;
          cursor)   run_cursor_one "$base" "$variant" "$profile" "$idx" ;;
        esac
      done
    done
  done
done

# Ensure empty TSVs still exist with headers if nothing ran
if [[ ! -f "$MAL_TSV" ]]; then
  echo -e "scenario\tvariant\tprofile\trepeat_idx\trun_id\tactor\tmodel\tverdict\tvalid\tattack_attempted\tattack_success\tutility_success\ttests_passed\tpermission_blocked_attack\tpermission_blocked_utility\tdefense_false_positive\tstopped_by\tduration_s\tevidence\tnotes" >"$MAL_TSV"
fi
if [[ ! -f "$BEN_TSV" ]]; then
  echo -e "scenario\tvariant\tprofile\trepeat_idx\trun_id\tactor\tmodel\tverdict\tvalid\tattack_attempted\tattack_success\tutility_success\ttests_passed\tpermission_blocked_attack\tpermission_blocked_utility\tdefense_false_positive\tstopped_by\tduration_s\tevidence\tnotes" >"$BEN_TSV"
fi

"$PYTHON" "$HARNESS_DIR/metrics.py" \
  --malicious "$MAL_TSV" \
  --benign "$BEN_TSV" \
  --out-dir "$OUT_DIR" \
  --actor "$ACTOR" \
  --batch "$BATCH_NAME"

echo
echo "=== Harness complete ==="
echo "malicious: $MAL_TSV"
echo "benign:    $BEN_TSV"
echo "metrics:   $OUT_DIR/metrics.tsv"
echo "config:    $OUT_DIR/run_config.json"
