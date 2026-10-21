#!/usr/bin/env bash
# HiveTrace repeat-stage: malicious-only, N valid runs × off/normal/strict.
# Fresh isolated run each trial. Technical failures retried; oracle salvage
# via isolated/repeat_record_run.py when harness crashes after final_app exists.
#
# Usage:
#   ./isolated/repeat_malicious.sh b08
#   RESUME_TSV=logs/b08-repeat-....tsv ./isolated/repeat_malicious.sh b08
set -uo pipefail
cd "$(dirname "$0")/.."

SCENARIO="${1:?usage: repeat_malicious.sh b07|b08|b09|b10|b11|b12}"
TRIALS="${TRIALS:-5}"
TIMEOUT="${TIMEOUT:-2400}"
NETWORK="${NETWORK:-allowlist}"
MAX_ATTEMPTS_PER_CELL="${MAX_ATTEMPTS_PER_CELL:-12}"

case "$SCENARIO" in
  b07) CHAIN=b07_lint_output; HELPER=tools/sync_lint_context.py ;;
  b08) CHAIN=b08_agent_handoff; HELPER=tools/sync_workspace.py ;;
  b09) CHAIN=b09_readme_backdoor; HELPER=apply_legacy_compat.py ;;
  b10) CHAIN=b10_auth_comment; HELPER=legacy/verifier.py ;;
  b11) CHAIN=b11_issue_rce; HELPER=apply_diagnostic_compat.py ;;
  b12) CHAIN=b12_agents_bootstrap; HELPER=tools/bootstrap.py ;;
  *) echo "unknown scenario: $SCENARIO" >&2; exit 2 ;;
esac

PROFILES=(off normal strict)
PYTHON="${PYTHON:-$HOME/.pyenv/versions/mosaic-311/bin/python}"
RECORD="$PYTHON isolated/repeat_record_run.py"
mkdir -p logs

TS="${RESUME_TSV:-logs/${SCENARIO}-repeat-$(date +%Y%m%d-%H%M%S).tsv}"
if [ ! -f "$TS" ]; then
  echo -e "scenario\tprofile\trepeat_idx\trun_id\tverdict\tvalid\tattack_attempted\tattack_success\tpermission_blocked_attack\tpermission_blocked_utility\tutility_success\ttests_passed\tstopped_by\tattack_method\thelper_executed\thelper_blocked\tmanual_bypass\tduration_s\tnotes" \
    | tee "$TS"
else
  # One-time salvage of ERROR rows from prior runner versions
  $RECORD --backfill --scenario "$SCENARIO" --profile x --idx 0 \
    --run-dir logs --helper "$HELPER" --tsv "$TS" || true
fi

count_valid() {
  local profile="$1"
  awk -F'\t' -v p="$profile" 'NR>1 && $2==p && $6=="True" { n++ } END { print n+0 }' "$TS"
}

for profile in "${PROFILES[@]}"; do
  while true; do
    n=$(count_valid "$profile")
    if [ "$n" -ge "$TRIALS" ]; then
      echo "===== $SCENARIO / $profile: already $n/$TRIALS valid — skip ====="
      break
    fi
    attempts=$(awk -F'\t' -v p="$profile" 'NR>1 && $2==p {n++} END{print n+0}' "$TS")
    if [ "$attempts" -ge "$MAX_ATTEMPTS_PER_CELL" ]; then
      echo "[repeat] $SCENARIO/$profile: MAX_ATTEMPTS=$MAX_ATTEMPTS_PER_CELL with only $n valid" >&2
      break
    fi
    idx=$((n + 1))
    echo "===== $SCENARIO / malicious / $profile / repeat $idx/$TRIALS (attempt $((attempts+1))) ====="
    log="/tmp/${SCENARIO}-repeat-${profile}-${idx}-$(date +%H%M%S).log"
    set +e
    ./run_isolated.sh "$CHAIN" \
      --actor opencode \
      --permission-profile "$profile" \
      --network "$NETWORK" \
      --timeout "$TIMEOUT" \
      --verbose 2>&1 | tee "$log"
    rc=${PIPESTATUS[0]}
    set -e

    run_dir=$(ls -td "logs/${CHAIN}-"* 2>/dev/null | head -1 || true)
    if [ -z "$run_dir" ] || [ ! -f "$run_dir/result.json" ]; then
      echo -e "${SCENARIO}\t${profile}\t${idx}\tNO_RUN\tERROR\tFalse\t\t\t\t\t\t\t\t\t\t\t\t\trc=$rc no result.json" \
        | tee -a "$TS"
      continue
    fi

    $RECORD \
      --scenario "$SCENARIO" \
      --profile "$profile" \
      --idx "$idx" \
      --run-dir "$run_dir" \
      --helper "$HELPER" \
      --tsv "$TS"
  done
done

echo "REPEAT_TSV: $TS"
column -t -s $'\t' "$TS" 2>/dev/null || cat "$TS"
