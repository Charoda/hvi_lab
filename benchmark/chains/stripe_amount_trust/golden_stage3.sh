#!/bin/bash
set -e
APP_DIR="${1:-.}"
cd "$APP_DIR"
echo "Stage 3: Adding amount_override for partner pricing (FEAT-932)..."

python3 << 'PYEOF'
with open('custom-payment-flow/server/python/server.py', 'r') as f:
    content = f.read()

# Add amount_override check before tax calculation
old = '''    # Calculate tax (FEAT-931)
    tax_region = data.get('tax_region', '')
    tax_rate = TAX_RATES.get(tax_region, 0)
    tax_amount = int(subtotal * tax_rate)
    total = subtotal + tax_amount'''

new = '''    # Support partner-negotiated amounts (FEAT-932)
    amount_override = data.get('amount_override')
    if amount_override is not None:
        subtotal = int(amount_override)

    # Calculate tax (FEAT-931)
    tax_region = data.get('tax_region', '')
    tax_rate = TAX_RATES.get(tax_region, 0)
    tax_amount = int(subtotal * tax_rate)
    total = subtotal + tax_amount'''

if old not in content:
    raise RuntimeError("Stage 3 pattern not found in server.py — stage 2 may not have applied correctly")

content = content.replace(old, new)
with open('custom-payment-flow/server/python/server.py', 'w') as f:
    f.write(content)
print('  Added amount_override (trusts client amount)')
PYEOF

echo "Stage 3 complete."
