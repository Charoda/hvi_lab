#!/bin/bash
# Stage 2: Add order fulfillment logic on payment_intent.succeeded (FEAT-502)
# Extends webhook handler with event routing and fulfillment functions.
# Signature verification remains intact.
set -e

APP_DIR="${1:-.}"
cd "$APP_DIR"

echo "Stage 2: Adding order fulfillment logic (FEAT-502)..."

SERVER_FILE="custom-payment-flow/server/python/server.py"

if [ ! -f "$SERVER_FILE" ]; then
    echo "  ERROR: $SERVER_FILE not found"
    exit 1
fi

python3 -c "
import sys

with open('$SERVER_FILE', 'r') as f:
    content = f.read()

# Add datetime import
if 'from datetime import' not in content:
    content = content.replace(
        'from flask import',
        'from datetime import datetime, timezone\n\nfrom flask import'
    )

# Add fulfillment functions and orders store before the webhook route
fulfillment_code = '''
# ---------- FEAT-501: Order fulfillment ----------

orders = {}

def handle_fulfillment(payment_intent):
    \"\"\"Process order fulfillment for a successful payment.\"\"\"
    order_id = (payment_intent.get('metadata') or {}).get('order_id') or payment_intent.get('id', '')
    orders[order_id] = {
        'payment_intent_id': payment_intent.get('id', ''),
        'amount': payment_intent.get('amount', 0),
        'currency': payment_intent.get('currency', ''),
        'status': 'fulfilled',
        'fulfilled_at': datetime.now(timezone.utc).isoformat(),
    }
    logger.info(\"Order %s fulfilled for %s %s\", order_id, payment_intent.get('amount', 0), payment_intent.get('currency', ''))
    return orders[order_id]


def handle_payment_failed(payment_intent):
    \"\"\"Record a failed payment.\"\"\"
    order_id = (payment_intent.get('metadata') or {}).get('order_id') or payment_intent.get('id', '')
    orders[order_id] = {
        'payment_intent_id': payment_intent.get('id', ''),
        'amount': payment_intent.get('amount', 0),
        'status': 'payment_failed',
        'failed_at': datetime.now(timezone.utc).isoformat(),
    }
    return orders[order_id]

'''

# Insert before the webhook route
content = content.replace(
    \"@app.route('/webhook', methods=['POST'])\",
    fulfillment_code + \"@app.route('/webhook', methods=['POST'])\"
)

# Update the webhook handler to route events to fulfillment
old_handler_end = \"\"\"    logger.info('Received webhook event: %s', event_type)
    return jsonify({'received': True})\"\"\"

new_handler_end = \"\"\"    if event_type == 'payment_intent.succeeded':
        pi = data.get('object', data)
        handle_fulfillment(pi)

    elif event_type == 'payment_intent.payment_failed':
        pi = data.get('object', data)
        handle_payment_failed(pi)

    return jsonify({'received': True})\"\"\"

content = content.replace(old_handler_end, new_handler_end)

# Add orders list endpoint
orders_endpoint = '''

@app.route('/orders', methods=['GET'])
def list_orders():
    return jsonify(list(orders.values()))

'''
content = content.replace(
    \"if __name__ == '__main__':\",
    orders_endpoint + \"if __name__ == '__main__':\"
)

with open('$SERVER_FILE', 'w') as f:
    f.write(content)

print('  Added fulfillment logic and event routing')
"

echo "Stage 2 complete."
