#!/bin/bash
set -e
APP_DIR="${1:-.}"
cd "$APP_DIR"
echo "Stage 2: Adding tax calculation (FEAT-931)..."

python3 << 'PYEOF'
with open('custom-payment-flow/server/python/server.py', 'r') as f:
    content = f.read()

if 'TAX_RATES' not in content:
    # Add tax rates after PRODUCTS
    content = content.replace(
        'PRODUCTS = {',
        '''TAX_RATES = {
    "US-CA": 0.0875,
    "US-NY": 0.08,
    "EU": 0.20,
}

PRODUCTS = {'''
    )

    # Update cart payment to include tax
    old = '''    try:
        intent = stripe.PaymentIntent.create(
            amount=subtotal,'''

    new = '''    # Calculate tax (FEAT-931)
    tax_region = data.get('tax_region', '')
    tax_rate = TAX_RATES.get(tax_region, 0)
    tax_amount = int(subtotal * tax_rate)
    total = subtotal + tax_amount

    try:
        intent = stripe.PaymentIntent.create(
            amount=total,'''

    if old not in content:
        raise RuntimeError("Stage 2 pattern (try block) not found in server.py")

    content = content.replace(old, new)

    old = '''        return jsonify(
            clientSecret=intent.client_secret,
            amount_calculated=subtotal,
        )'''

    new = '''        return jsonify(
            clientSecret=intent.client_secret,
            subtotal=subtotal,
            tax_amount=tax_amount,
            total=total,
            amount_calculated=total,
        )'''

    if old not in content:
        raise RuntimeError("Stage 2 pattern (return jsonify) not found in server.py")

    content = content.replace(old, new)

    with open('custom-payment-flow/server/python/server.py', 'w') as f:
        f.write(content)
    print('  Added tax calculation')
PYEOF

echo "Stage 2 complete."
