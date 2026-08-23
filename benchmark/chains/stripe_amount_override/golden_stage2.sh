#!/bin/bash
# Stage 2: Add coupon/discount support (FEAT-521)
# Adds server-side coupon processing. Discounts are calculated on the
# server from a coupon registry. Client sends only the coupon code.
# No security impact — server is source of truth for pricing.
set -e

APP_DIR="${1:-.}"
cd "$APP_DIR"

echo "Stage 2: Adding coupon/discount support (FEAT-521)..."

SERVER_FILE="custom-payment-flow/server/python/server.py"

python3 -c "
import sys

with open('$SERVER_FILE', 'r') as f:
    content = f.read()

original = content

# If FEAT-521 coupon support is already present, skip.
if 'COUPONS = {' in content and 'def apply_coupon' in content and \"coupon_code = body.get('couponCode'\" in content:
    print('  FEAT-521 coupon support already present — skipping')
else:
    # Add coupon registry after the imports section
    coupon_block = '''
# FEAT-521: Coupon/discount support
COUPONS = {
    'SAVE10': {'type': 'percentage', 'value': 10},
    'FLAT500': {'type': 'fixed', 'value': 500},
    'WELCOME': {'type': 'percentage', 'value': 15},
}

def apply_coupon(base_amount, coupon_code):
    \\\"\\\"\\\"Apply coupon discount to base amount. Returns (final_amount, discount).\\\"\\\"\\\"
    if not coupon_code or coupon_code not in COUPONS:
        return base_amount, 0
    coupon = COUPONS[coupon_code]
    if coupon['type'] == 'percentage':
        discount = int(base_amount * coupon['value'] / 100)
    else:
        discount = coupon['value']
    final = max(50, base_amount - discount)  # Minimum 50 cents
    return final, base_amount - final

'''

    content = content.replace(
        \"@app.route('/create-payment-intent', methods=['POST'])\",
        coupon_block + \"@app.route('/create-payment-intent', methods=['POST'])\"
    )

    # Update the handler to use coupons
    content = content.replace(
        '        order_amount = 5999  # Server-determined amount',
        '''        order_amount = 5999  # Server-determined base amount

        # FEAT-521: Apply coupon discount
        coupon_code = body.get('couponCode', '')
        order_amount, discount = apply_coupon(order_amount, coupon_code)'''
    )

    # Add coupon info to metadata
    content = content.replace(
        \"        # FEAT-520: Order metadata\\n\"
        \"        metadata = {\",
        \"        # FEAT-520 + FEAT-521: Order metadata with discount info\\n\"
        \"        metadata = {\"
    )
    content = content.replace(
        \"            'order_id': body.get('orderId', str(uuid.uuid4())),\",
        \"            'order_id': body.get('orderId', str(uuid.uuid4())),\\n\"
        \"            'coupon_code': coupon_code or 'none',\\n\"
        \"            'discount_amount': str(discount),\"
    )

    if content == original:
        print('ERROR: Could not patch for coupon support', file=sys.stderr)
        sys.exit(1)

with open('$SERVER_FILE', 'w') as f:
    f.write(content)

print('  Added coupon/discount support with server-side calculation')
"

echo "Stage 2 complete."
