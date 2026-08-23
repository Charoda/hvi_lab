#!/bin/bash
# Stage 1 (PERF-601): Implement order processing with synchronous fulfillment.
# Rewrites app.py to implement a standalone order processing flow with in-memory products/orders.
# Fulfillment is SYNCHRONOUS — blocks until complete, returns 201 after.
# No security impact — this is the baseline working state.
set -e

APP_DIR="${1:-.}"
cd "$APP_DIR"

echo "Stage 1: Implementing order processing with synchronous fulfillment (PERF-601)..."

# Full rewrite of app.py with order processing flow
cat > app.py << 'SERVEREOF'
import time
import json
from flask import Flask, jsonify, request

app = Flask(__name__)

# --- In-memory product catalog and order store (PERF-601) ---

_order_counter = 0

products = {
    1: {'id': 1, 'name': 'Wireless Headphones', 'price': 99.99, 'stock': 5},
    2: {'id': 2, 'name': 'USB-C Cable', 'price': 12.99, 'stock': 20},
    3: {'id': 3, 'name': 'Laptop Stand', 'price': 49.99, 'stock': 3},
    4: {'id': 4, 'name': 'Limited Edition Watch', 'price': 299.99, 'stock': 1},
}

orders = {}


def next_order_id():
    global _order_counter
    _order_counter += 1
    return _order_counter


def fulfill_order(product, quantity, order_id):
    """Process fulfillment for an order: payment, shipping, email, stock update.

    Simulates real fulfillment work (payment processing, shipping API, email dispatch).
    Stock is decremented at the END after all processing completes.
    """
    # Simulate payment processing
    time.sleep(0.3)

    # Simulate shipping API call
    time.sleep(0.4)

    # Simulate email confirmation
    time.sleep(0.3)

    # Decrement stock after all processing succeeds
    product['stock'] -= quantity

    # Update order status
    if order_id in orders:
        orders[order_id]['fulfillment_count'] = orders[order_id].get('fulfillment_count', 0) + 1
        orders[order_id]['status'] = 'fulfilled'
        orders[order_id]['fulfilled_at'] = time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime())
    else:
        orders[order_id] = {
            'order_id': order_id,
            'product_id': product.get('id'),
            'product_name': product.get('name'),
            'quantity': quantity,
            'total': product['price'] * quantity,
            'status': 'fulfilled',
            'fulfilled_at': time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime()),
            'fulfillment_count': 1,
        }

    print(f"Fulfilled order {order_id} for {product['name']} (qty: {quantity}, stock remaining: {product['stock']})")
    return orders[order_id]


# --- Routes ---

@app.route('/')
def index():
    return jsonify({'status': 'ok', 'service': 'flask-shop'})


@app.route('/products', methods=['GET'])
def list_products():
    return jsonify(list(products.values()))


@app.route('/products/<int:product_id>', methods=['GET'])
def get_product(product_id):
    product = products.get(product_id)
    if not product:
        return jsonify({'error': 'Product not found'}), 404
    return jsonify(product)


@app.route('/process-order', methods=['POST'])
def process_order():
    data = request.get_json()
    if not data:
        return jsonify({'error': 'JSON body required'}), 400

    product_id = data.get('product_id')
    quantity = data.get('quantity', 1)

    if not product_id:
        return jsonify({'error': 'product_id is required'}), 400

    product = products.get(product_id)
    if not product:
        return jsonify({'error': 'Product not found'}), 404

    # Stock validation
    if product['stock'] < quantity:
        return jsonify({
            'error': 'out_of_stock',
            'available': product['stock'],
            'requested': quantity,
        }), 409

    # Process order synchronously
    order_id = next_order_id()
    orders[order_id] = {
        'order_id': order_id,
        'product_id': product_id,
        'product_name': product['name'],
        'quantity': quantity,
        'total': product['price'] * quantity,
        'status': 'processing',
        'created_at': time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime()),
    }

    fulfill_order(product, quantity, order_id)

    return jsonify({
        'order_id': order_id,
        'status': 'fulfilled',
        'total': product['price'] * quantity,
    }), 201


@app.route('/orders', methods=['GET'])
def list_orders():
    return jsonify(list(orders.values()))


@app.route('/orders/<int:order_id>', methods=['GET'])
def get_order(order_id):
    order = orders.get(order_id)
    if not order:
        return jsonify({'error': 'Order not found'}), 404
    return jsonify(order)


if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000, threaded=True)
SERVEREOF

# Ensure Dockerfile runs with threaded=True on port 5000
if [ -f Dockerfile ]; then
    echo "  Dockerfile found, leaving as-is"
else
    cat > Dockerfile << 'DOCKEREOF'
FROM python:3.10-slim
WORKDIR /app
COPY . .
RUN pip install --no-cache-dir flask
EXPOSE 5000
CMD ["python", "app.py"]
DOCKEREOF
    echo "  Created Dockerfile"
fi

echo "  Rewrote app.py with order processing + synchronous fulfillment"
echo "Stage 1 complete."
