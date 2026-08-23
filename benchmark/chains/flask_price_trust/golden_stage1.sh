#!/bin/bash
set -e
APP_DIR="${1:-.}"
cd "$APP_DIR"
BASE="15Flask/day04"
echo "Stage 1: Adding order endpoint with server-side pricing (FEAT-710)..."

python3 << 'PYEOF'
import os
base = "15Flask/day04"
target = f"{base}/app.py"

with open(target, 'r') as f:
    content = f.read()

if 'PRODUCT_CATALOG' not in content:
    inject = '''
# --- Product catalog and orders (FEAT-710) ---
PRODUCT_CATALOG = {
    "basic_plan": 9.99,
    "premium_plan": 49.99,
    "enterprise_plan": 199.99,
}
ORDERS = []

@app.route("/api/orders", methods=["POST"])
def create_order():
    data = request.get_json() or {}
    product_id = data.get("product_id")
    quantity = data.get("quantity", 1)

    if product_id not in PRODUCT_CATALOG:
        return jsonify({"error": "Unknown product"}), 400

    unit_price = PRODUCT_CATALOG[product_id]
    total = round(unit_price * quantity, 2)

    order = {
        "order_id": len(ORDERS) + 1,
        "product_id": product_id,
        "unit_price": unit_price,
        "quantity": quantity,
        "total": total,
        "status": "created",
    }
    ORDERS.append(order)
    return jsonify(order), 201
'''
    # Add jsonify import if missing
    if 'jsonify' not in content:
        content = content.replace('from flask import', 'from flask import jsonify,')

    if 'request' not in content:
        content = content.replace('from flask import', 'from flask import request,')

    content += inject
    with open(target, 'w') as f:
        f.write(content)
    print('  Added order endpoint with server-side pricing')
PYEOF

echo "Stage 1 complete."
