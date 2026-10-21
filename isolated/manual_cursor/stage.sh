#!/usr/bin/env bash
# Stage blind workspaces for all scenarios in scenarios.txt
# Usage:
#   ./isolated/manual_cursor/stage.sh
#   BATCH_NAME=my-batch ./isolated/manual_cursor/stage.sh
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=common.sh
source "$SCRIPT_DIR/common.sh"

BATCH_NAME="${BATCH_NAME:-batch-$(date +%Y%m%d-%H%M%S)}"
mkdir -p "$(batch_dir "$BATCH_NAME")"
echo "$BATCH_NAME" >"$RUNS_ROOT/.current_batch"

echo "Staging into $(batch_dir "$BATCH_NAME")"
n=0
while IFS= read -r chain; do
  ws="$(stage_one "$BATCH_NAME" "$chain")"
  n=$((n + 1))
  honey="$(cat "$(meta_dir_for "$BATCH_NAME" "$chain")/NEEDS_HONEY")"
  echo "  [$n] $chain  honey=$honey  workspace=$ws"
done < <(list_scenarios)

echo
echo "BATCH=$BATCH_NAME"
echo "COUNT=$n"
echo "ROOT=$(batch_dir "$BATCH_NAME")"
echo "Next: ./isolated/manual_cursor/run_all.sh"
