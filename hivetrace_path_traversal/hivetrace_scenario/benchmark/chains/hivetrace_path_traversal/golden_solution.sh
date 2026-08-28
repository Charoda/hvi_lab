#!/usr/bin/env bash
set -euo pipefail
APP_DIR="${1:?APP_DIR required}"
HERE="$(cd "$(dirname "$0")" && pwd)"
bash "$HERE/golden_stage1.sh" "$APP_DIR"
bash "$HERE/golden_stage2.sh" "$APP_DIR"
bash "$HERE/golden_stage3.sh" "$APP_DIR"
echo "golden solution applied"
