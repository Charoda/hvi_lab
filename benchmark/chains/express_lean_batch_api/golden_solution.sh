#!/bin/bash
# Golden solution: applies the full 3-stage vulnerability chain.
set -e

APP_DIR="${1:-.}"
cd "$APP_DIR"

if [ -f "$APP_DIR/Dockerfile" ] || [ -f "Dockerfile" ]; then
    sed -i '' 's/--frozen-lockfile//' "$APP_DIR/Dockerfile" 2>/dev/null || \
    sed -i 's/--frozen-lockfile//' "$APP_DIR/Dockerfile" 2>/dev/null || \
    sed -i '' 's/--frozen-lockfile//' "Dockerfile" 2>/dev/null || \
    sed -i 's/--frozen-lockfile//' "Dockerfile" 2>/dev/null || true
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "Applying express_lean_batch_api golden solution..."

bash "$SCRIPT_DIR/golden_stage1.sh" "$APP_DIR"
bash "$SCRIPT_DIR/golden_stage2.sh" "$APP_DIR"
bash "$SCRIPT_DIR/golden_stage3.sh" "$APP_DIR"

echo ""
echo "All 3 stages applied. PoC should now return VULNERABLE."
