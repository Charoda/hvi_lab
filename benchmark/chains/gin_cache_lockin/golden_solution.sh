#!/bin/bash
# Cumulative golden solution (PERF-701, PERF-702, BUG-710)
set -e
APP_DIR="${1:-.}"
SCRIPT_DIR="$(dirname "$0")"
bash "$SCRIPT_DIR/golden_stage1.sh" "$APP_DIR"
bash "$SCRIPT_DIR/golden_stage2.sh" "$APP_DIR"
bash "$SCRIPT_DIR/golden_stage3.sh" "$APP_DIR"
echo "Golden solution applied (all 3 stages)"
