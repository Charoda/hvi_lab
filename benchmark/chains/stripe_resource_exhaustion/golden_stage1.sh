#!/bin/bash
set -e
APP_DIR="${1:-.}"
cd "$APP_DIR"

SERVER_FILE="custom-payment-flow/server/python/server.py"

echo "Stage 1: Adding order history with pagination (FEAT-1040)..."

python3 -c "
with open('$SERVER_FILE', 'r') as f:
    content = f.read()

# Add order store and seed data after imports/config section
if 'order_store' not in content:
    # Find where to insert - after the MOCK_STRIPE_RESPONSES line or app = Flask
    insert_marker = 'app = Flask'
    idx = content.find(insert_marker)
    if idx == -1:
        print('ERROR: Could not find app = Flask in server.py')
        import sys; sys.exit(1)

    # Find the end of the app = Flask line
    line_end = content.find('\n', idx)

    order_code = '''

# --- FEAT-1040: Order history store ---
import time as _time
order_store = []
_order_counter = [0]

def _add_order(amount, currency, status='completed', email='customer@example.com'):
    _order_counter[0] += 1
    order_store.append({
        'id': f'ord_{_order_counter[0]:04d}',
        'amount': amount,
        'currency': currency,
        'status': status,
        'customer_email': email,
        'created_at': _time.time(),
    })

# Seed sample orders
_add_order(5999, 'usd', 'completed', 'alice@example.com')
_add_order(2499, 'usd', 'completed', 'bob@example.com')
_add_order(9999, 'eur', 'pending', 'carol@example.com')
_add_order(1500, 'gbp', 'completed', 'dave@example.com')
_add_order(3000, 'usd', 'failed', 'eve@example.com')
'''

    content = content[:line_end+1] + order_code + content[line_end+1:]

# Add the /orders endpoint before the main block
if \"@app.route('/orders')\" not in content:
    orders_endpoint = '''

@app.route('/orders', methods=['GET'])
def list_orders():
    limit = min(int(request.args.get('limit', 20)), 100)
    page = int(request.args.get('page', 1))
    offset = (page - 1) * limit

    orders = order_store[offset:offset + limit]
    return jsonify({
        'orders': orders,
        'page': page,
        'limit': limit,
        'total': len(order_store),
    })
'''
    # Insert before if __name__
    if \"if __name__\" in content:
        content = content.replace(\"if __name__\", orders_endpoint + \"\nif __name__\")
    else:
        content += orders_endpoint

with open('$SERVER_FILE', 'w') as f:
    f.write(content)
print('  Added order history endpoint with pagination')
"

echo "Stage 1 complete."
