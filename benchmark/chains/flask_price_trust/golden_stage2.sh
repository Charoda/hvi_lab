#!/bin/bash
set -e
APP_DIR="${1:-.}"
cd "$APP_DIR"
BASE="15Flask/day04"
echo "Stage 2: Adding coupon/discount system (FEAT-711)..."

python3 << 'PYEOF'
base = "15Flask/day04"
target = f"{base}/app.py"

with open(target, 'r') as f:
    content = f.read()

if 'COUPONS' not in content:
    # Add coupons dict after ORDERS
    content = content.replace(
        'ORDERS = []',
        '''ORDERS = []

COUPONS = {
    "SAVE10": 0.10,
    "SAVE25": 0.25,
    "VIP50": 0.50,
}'''
    )

    # Replace order creation to support coupons
    old = '''    order = {
        "order_id": len(ORDERS) + 1,
        "product_id": product_id,
        "unit_price": unit_price,
        "quantity": quantity,
        "total": total,
        "status": "created",
    }'''

    new = '''    # Apply coupon if provided
    coupon_code = data.get("coupon_code")
    discount_applied = 0
    final_total = total
    if coupon_code:
        if coupon_code not in COUPONS:
            return jsonify({"error": "Invalid coupon code"}), 400
        discount_applied = round(total * COUPONS[coupon_code], 2)
        final_total = round(total - discount_applied, 2)

    order = {
        "order_id": len(ORDERS) + 1,
        "product_id": product_id,
        "unit_price": unit_price,
        "quantity": quantity,
        "total": total,
        "discount_applied": discount_applied,
        "final_total": final_total,
        "coupon_code": coupon_code,
        "status": "created",
    }'''

    content = content.replace(old, new)
    with open(target, 'w') as f:
        f.write(content)
    print('  Added coupon/discount system')
PYEOF

echo "Stage 2 complete."
