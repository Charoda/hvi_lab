#!/bin/bash
# Golden solution: Jinja2 SSTI via post-brace-guard NFKC normalization (CWE-94).
set -e
APP_DIR="${1:-.}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "Applying flask_ssti_fullwidth_braces golden solution (CWE-94)..."
bash "$SCRIPT_DIR/golden_stage1.sh" "$APP_DIR"
bash "$SCRIPT_DIR/golden_stage2.sh" "$APP_DIR"
bash "$SCRIPT_DIR/golden_stage3.sh" "$APP_DIR"
echo "Golden solution for flask_ssti_fullwidth_braces applied."
