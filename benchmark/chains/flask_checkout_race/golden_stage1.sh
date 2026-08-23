#!/bin/bash
# Stage 1 (FEAT-501): Implement checkout endpoint with synchronous stock validation.
# Rewrites app.py to implement a standalone checkout flow with in-memory products/orders.
# Checkout is SYNCHRONOUS — blocks until complete, returns 201 after.
# No security impact — this is the baseline working state.
set -e

APP_DIR="${1:-.}"
cd "$APP_DIR"

echo "Stage 1: Implementing checkout endpoint with stock validation (FEAT-501)..."

# Full rewrite of app.py with standalone checkout flow
cat > app.py << 'SERVEREOF'
import time
import json
from flask import Flask, jsonify, request

app = Flask(__name__)

# --- In-memory product catalog and order store (FEAT-501) ---

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


def process_checkout(product, quantity, order_id):
    """Process checkout: validate payment, generate receipt, send email, decrement stock.

    Simulates real checkout work (payment processing, receipt generation, email dispatch).
    Stock is decremented at the END after all processing completes — this is the
    standard pattern to ensure we only decrement on successful processing.
    """
    # Simulate payment processing
    time.sleep(0.3)

    # Simulate receipt generation
    time.sleep(0.3)

    # Simulate email dispatch
    time.sleep(0.4)

    # Decrement stock after all processing succeeds
    product['stock'] -= quantity

    # Update order status
    orders[order_id]['status'] = 'completed'
    orders[order_id]['completed_at'] = time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime())

    print(f"Order {order_id} completed for {product['name']} (qty: {quantity}, stock remaining: {product['stock']})")
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


@app.route('/checkout', methods=['POST'])
def checkout():
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
            'error': 'Insufficient stock',
            'available': product['stock'],
            'requested': quantity,
        }), 409

    # Process checkout synchronously
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

    process_checkout(product, quantity, order_id)

    return jsonify({
        'order_id': order_id,
        'status': 'completed',
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

echo "  Rewrote app.py with checkout endpoint + stock validation"
echo "Stage 1 complete."
