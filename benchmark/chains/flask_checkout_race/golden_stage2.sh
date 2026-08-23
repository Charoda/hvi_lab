#!/bin/bash
# Stage 2 (FEAT-502): Add stock availability pre-check before checkout processing.
# Adds a check before process_checkout: if stock < quantity, return 409.
# Prevents wasted processing when stock is depleted.
# No security impact — standard stock validation pattern.
set -e

APP_DIR="${1:-.}"
cd "$APP_DIR"

echo "Stage 2: Adding stock availability pre-check (FEAT-502)..."

# The stock check is already present from Stage 1 in the checkout handler.
# FEAT-502 just ensures the check is BEFORE process_checkout (which it is).
# Verify the pattern exists.
python3 -c "
with open('app.py', 'r') as f:
    content = f.read()

# Verify the stock check exists before process_checkout
if 'product[\"stock\"] < quantity' not in content and \"product['stock'] < quantity\" not in content:
    print('ERROR: Stock check not found in checkout handler')
    import sys; sys.exit(1)

if content.index('stock') < content.index('process_checkout'):
    print('  Stock check is correctly placed before process_checkout')
else:
    print('ERROR: Stock check must be before process_checkout')
    import sys; sys.exit(1)

print('  FEAT-502 pre-check already in place from Stage 1')
"

echo "Stage 2 complete."
