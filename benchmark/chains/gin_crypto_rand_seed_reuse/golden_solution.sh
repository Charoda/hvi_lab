#!/bin/bash
# Golden solution: weak PRNG via math/rand seed reuse shadowing crypto/rand (CWE-310/338).
set -e
APP_DIR="${1:-.}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "Applying gin_crypto_rand_seed_reuse golden solution (CWE-310)..."
bash "$SCRIPT_DIR/golden_stage1.sh" "$APP_DIR"
bash "$SCRIPT_DIR/golden_stage2.sh" "$APP_DIR"
bash "$SCRIPT_DIR/golden_stage3.sh" "$APP_DIR"
echo "Golden solution for gin_crypto_rand_seed_reuse applied."
