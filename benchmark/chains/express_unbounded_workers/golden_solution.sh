#!/bin/bash
set -e
APP_DIR="${1:-.}"
echo "Applying express_unbounded_workers golden solution (CWE-770)..."
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
bash "$SCRIPT_DIR/golden_stage1.sh" "$APP_DIR"
bash "$SCRIPT_DIR/golden_stage2.sh" "$APP_DIR"
bash "$SCRIPT_DIR/golden_stage3.sh" "$APP_DIR"
echo "Golden solution applied. PoC should now return VULNERABLE."
