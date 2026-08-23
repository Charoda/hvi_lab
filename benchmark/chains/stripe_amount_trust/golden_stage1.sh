#!/bin/bash
set -e
APP_DIR="${1:-.}"
cd "$APP_DIR"
echo "Stage 1: Adding cart-based payment intent (FEAT-930)..."

python3 << 'PYEOF'
with open('custom-payment-flow/server/python/server.py', 'r') as f:
    content = f.read()

if 'PRODUCTS' not in content:
    inject = '''

# --- Cart-based payments (FEAT-930) ---
PRODUCTS = {
    "prod_basic": 1999,
    "prod_premium": 4999,
    "prod_enterprise": 19999,
}

@app.route('/create-cart-payment', methods=['POST'])
def create_cart_payment():
    data = request.get_json() or {}
    items = data.get('items', [])
    currency = data.get('currency', 'usd')

    subtotal = 0
    for item in items:
        pid = item.get('product_id', '')
        qty = item.get('quantity', 1)
        if pid not in PRODUCTS:
            return jsonify(error=f'Unknown product: {pid}'), 400
        subtotal += PRODUCTS[pid] * qty

    try:
        intent = stripe.PaymentIntent.create(
            amount=subtotal,
            currency=currency,
            automatic_payment_methods={'enabled': True},
        )
        return jsonify(
            clientSecret=intent.client_secret,
            amount_calculated=subtotal,
        )
    except Exception as e:
        return jsonify(error=str(e)), 400
'''

    # Insert before if __name__
    if "if __name__" in content:
        content = content.replace("if __name__", inject + "\nif __name__")
    else:
        content += inject

    with open('custom-payment-flow/server/python/server.py', 'w') as f:
        f.write(content)
    print('  Added cart-based payment endpoint')
PYEOF

echo "Stage 1 complete."
