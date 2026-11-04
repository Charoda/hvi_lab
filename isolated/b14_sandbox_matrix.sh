#!/usr/bin/env bash
# B14 sandbox allowlist control matrix:
#   OpenCode × off/normal/strict × mal+benign × N=5
#   then Cursor × off/normal/strict × mal+benign × N=5
# Resume via SKIP_DONE=1 (harness default).
set -euo pipefail
cd "$(dirname "$0")/.."

set -a
# shellcheck disable=SC1091
source .env
set +a

ACTOR="${1:-opencode}"
TRIALS="${TRIALS:-5}"
TIMEOUT="${TIMEOUT:-2400}"
NETWORK="${NETWORK:-allowlist}"
PROFILES="${PROFILES:-all}"
BATCH_PREFIX="${BATCH_PREFIX:-b14-sandbox}"

MODEL_ARG=()
if [[ "$ACTOR" == "opencode" ]]; then
  MODEL="${MOSAIC_OPENCODE_MODEL:-openrouter/nvidia/nemotron-3-ultra-550b-a55b}"
  MODEL_ARG=(--model "$MODEL")
elif [[ "$ACTOR" == "cursor" ]]; then
  if [[ -n "${MOSAIC_CURSOR_MODEL:-}" ]]; then
    MODEL_ARG=(--model "$MOSAIC_CURSOR_MODEL")
  fi
else
  echo "usage: $0 opencode|cursor" >&2
  exit 2
fi

BATCH="${BATCH_PREFIX}-${ACTOR}-$(date +%Y%m%d-%H%M%S)"
LOG="/tmp/${BATCH}.log"
echo "=== B14 matrix actor=$ACTOR trials=$TRIALS profiles=$PROFILES batch=$BATCH ==="
echo "log: $LOG"

./isolated/harness/run.sh \
  --actor "$ACTOR" \
  --profile "$PROFILES" \
  --trials "$TRIALS" \
  --scenarios b14_sandbox_allowlist \
  --network "$NETWORK" \
  --timeout "$TIMEOUT" \
  --batch "$BATCH" \
  "${MODEL_ARG[@]}" \
  2>&1 | tee "$LOG"

echo "EXIT=${PIPESTATUS[0]}"
echo "SUMMARY batch=$BATCH"
ls -la "logs/$BATCH/" || true
