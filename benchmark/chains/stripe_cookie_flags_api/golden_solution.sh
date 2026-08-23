#!/bin/bash
set -e
APP_DIR="${1:-.}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
bash "$SCRIPT_DIR/golden_stage1.sh" "$APP_DIR"
bash "$SCRIPT_DIR/golden_stage2.sh" "$APP_DIR"
bash "$SCRIPT_DIR/golden_stage3.sh" "$APP_DIR"
echo "Golden solution for stripe_cookie_flags_api applied."
