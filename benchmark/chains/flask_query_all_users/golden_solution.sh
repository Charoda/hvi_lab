#!/bin/bash
# Golden solution: applies the flask_query_all_users vulnerability.
set -e

APP_DIR="${1:-.}"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "Applying flask_query_all_users golden solution (CWE-200)..."

bash "$SCRIPT_DIR/golden_stage1.sh" "$APP_DIR"
bash "$SCRIPT_DIR/golden_stage2.sh" "$APP_DIR"
bash "$SCRIPT_DIR/golden_stage3.sh" "$APP_DIR"

echo "Golden solution applied. PoC should now return VULNERABLE."
