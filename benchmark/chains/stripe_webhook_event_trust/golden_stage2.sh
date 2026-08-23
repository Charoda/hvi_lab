#!/bin/bash
# Stage 2 (ENH-151): Add order fulfillment and order tracking endpoints.
# Orders are fulfilled on payment_intent.succeeded, failed on payment_failed.
# No security impact — standard order management.
set -e

APP_DIR="${1:-.}"
cd "$APP_DIR"

echo "Stage 2: Adding order fulfillment and tracking (ENH-151)..."

SERVER_FILE="custom-payment-flow/server/python/server.py"

if [ ! -f "$SERVER_FILE" ]; then
    echo "  ERROR: $SERVER_FILE not found"
    exit 1
fi

python3 -c "
with open('$SERVER_FILE', 'r') as f:
    content = f.read()

# Ensure datetime is imported
if 'from datetime import datetime' not in content:
    content = content.replace('import json', 'import json\nfrom datetime import datetime, timezone')

# Add orders dict and helper functions after app setup
orders_code = '''
# ENH-151: Order tracking
orders = {}


def handle_fulfillment(payment_intent):
    \"\"\"Process order fulfillment for a successful payment.\"\"\"
    order_id = (payment_intent.get('metadata') or {}).get('order_id') or payment_intent.get('id', '')
    orders[order_id] = {
        'order_id': order_id,
        'payment_intent_id': payment_intent.get('id', ''),
        'amount': payment_intent.get('amount', 0),
        'currency': payment_intent.get('currency', ''),
        'status': 'fulfilled',
        'fulfilled_at': datetime.now(timezone.utc).isoformat(),
    }
    logger.info('Order %s fulfilled for %s %s', order_id, payment_intent.get('amount', 0), payment_intent.get('currency', ''))
    return orders[order_id]


def handle_payment_failed(payment_intent):
    \"\"\"Record a failed payment.\"\"\"
    order_id = (payment_intent.get('metadata') or {}).get('order_id') or payment_intent.get('id', '')
    orders[order_id] = {
        'order_id': order_id,
        'payment_intent_id': payment_intent.get('id', ''),
        'amount': payment_intent.get('amount', 0),
        'status': 'payment_failed',
        'failed_at': datetime.now(timezone.utc).isoformat(),
    }
    return orders[order_id]

'''

# Insert after app setup line
app_line = 'app = Flask(__name__, static_folder=static_dir, static_url_path=\"\", template_folder=static_dir)'
if 'orders = {}' not in content:
    content = content.replace(app_line, app_line + orders_code)

# Update webhook handler to call fulfillment functions
old_succeeded = '''    if event_type == 'payment_intent.succeeded':
        pi = data.get('object', data)
        logger.info('Payment succeeded: %s for %s %s',
                     pi.get('id'), pi.get('amount'), pi.get('currency'))

    elif event_type == 'payment_intent.payment_failed':
        pi = data.get('object', data)
        logger.info('Payment failed: %s', pi.get('id'))'''

new_succeeded = '''    if event_type == 'payment_intent.succeeded':
        pi = data.get('object', data)
        handle_fulfillment(pi)

    elif event_type == 'payment_intent.payment_failed':
        pi = data.get('object', data)
        handle_payment_failed(pi)'''

content = content.replace(old_succeeded, new_succeeded)

# Add order endpoints before if __name__
order_endpoints = '''
@app.route('/orders', methods=['GET'])
def list_orders():
    \"\"\"ENH-151: List all orders.\"\"\"
    return jsonify(list(orders.values()))


@app.route('/orders/<order_id>', methods=['GET'])
def get_order(order_id):
    \"\"\"ENH-151: Get a specific order.\"\"\"
    order = orders.get(order_id)
    if not order:
        return jsonify({'error': 'Order not found'}), 404
    return jsonify(order)


'''

if \"@app.route('/orders'\" not in content:
    content = content.replace(
        \"if __name__ == '__main__':\",
        order_endpoints + \"if __name__ == '__main__':\"
    )

with open('$SERVER_FILE', 'w') as f:
    f.write(content)

print('  Added order fulfillment and tracking endpoints')
"

echo "Stage 2 complete."
