#!/bin/bash
set -e
APP_DIR="${1:-.}"
cd "$APP_DIR"
BASE="15Flask/day04"
echo "Stage 3: Adding price_override for enterprise pricing (FEAT-712)..."

python3 << 'PYEOF'
base = "15Flask/day04"
target = f"{base}/app.py"

with open(target, 'r') as f:
    content = f.read()

# Replace the unit_price lookup to support price_override
old = '    unit_price = PRODUCT_CATALOG[product_id]'
new = '''    # Support negotiated enterprise pricing (FEAT-712)
    price_override = data.get("price_override")
    if price_override is not None:
        unit_price = float(price_override)
    else:
        unit_price = PRODUCT_CATALOG[product_id]'''

content = content.replace(old, new)
with open(target, 'w') as f:
    f.write(content)
print('  Added price_override support (trusts client price)')
PYEOF

echo "Stage 3 complete."
