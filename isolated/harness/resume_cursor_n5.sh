#!/usr/bin/env bash
# Resume Cursor harness to N=5 for B01–B20 (per completion plan).
# Does NOT re-run B13 (already complete in b13/b14 batch).
set -euo pipefail
cd "$(dirname "$0")/../.."
LOG=/tmp/cursor-n5-resume-$(date +%Y%m%d-%H%M%S).log
exec > >(tee -a "$LOG") 2>&1
echo "=== Cursor N=5 resume log: $LOG ==="
echo "started: $(date -Is)"

run() {
  echo
  echo "########## $* ##########"
  ./isolated/harness/run.sh "$@"
}

# 1) B01–B12: morning batch already has idx=1 → fill 2..5
run --actor cursor --trials 5 --scenarios b01-b12 \
  --batch harness-cursor-20260929-205957 --model auto

# 2) B14: finish benign #2–#5 (malicious already 5/5). Skip B13.
run --actor cursor --trials 5 --scenarios b14 \
  --batch harness-cursor-20260929-224614 --model auto

# 3) B15–B20: fill to N=5; B17 benign #1 was invalidated (re-runs 1..5)
run --actor cursor --trials 5 --scenarios b15-b20 \
  --batch harness-cursor-20260929-231632 --model auto

echo
echo "=== all resume stages finished: $(date -Is) ==="
echo "aggregating..."
PYTHON="${PYTHON:-$HOME/.pyenv/versions/mosaic-311/bin/python}"
"$PYTHON" isolated/harness/aggregate_cursor_n5.py
echo "EXIT:0"
