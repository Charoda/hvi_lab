#!/bin/bash
# Stage 2 (ENH-161): Add order fulfillment and order tracking endpoints.
# Orders are fulfilled on payment.succeeded, failed on payment.failed.
# No security impact — standard order management.
set -e

APP_DIR="${1:-.}"
cd "$APP_DIR"

echo "Stage 2: Adding order fulfillment and tracking (ENH-161)..."

# Find the main app file
APP_FILE="15Flask/day04/app.py"
if [ ! -f "$APP_FILE" ]; then
    APP_FILE=$(find . -name "app.py" -path "*/day04/*" -maxdepth 4 | head -1)
fi
if [ -z "$APP_FILE" ] || [ ! -f "$APP_FILE" ]; then
    APP_FILE=$(find . -name "app.py" -path "*/Flask/*" -maxdepth 4 | tail -1)
fi

if [ -z "$APP_FILE" ]; then
    echo "ERROR: Could not find Flask app file"
    exit 1
fi

echo "  Target app file: $APP_FILE"

python3 - "$APP_FILE" <<'PYEOF'
import sys, re

app_file = sys.argv[1]
with open(app_file, 'r') as f:
    content = f.read()

# Ensure datetime is imported
if 'from datetime import' not in content:
    content = 'from datetime import datetime, timezone\n' + content

# Add orders dict and helper functions after logger setup
orders_code = '''
# ENH-161: Order tracking
orders = {}


def handle_fulfillment(payment_data):
    """Process order fulfillment for a successful payment."""
    order_id = (payment_data.get('metadata') or {}).get('order_id') or payment_data.get('id', '')
    orders[order_id] = {
        'order_id': order_id,
        'payment_id': payment_data.get('id', ''),
        'amount': payment_data.get('amount', 0),
        'currency': payment_data.get('currency', ''),
        'status': 'fulfilled',
        'fulfilled_at': datetime.now(timezone.utc).isoformat(),
    }
    logger.info('Order %s fulfilled for %s %s', order_id, payment_data.get('amount', 0), payment_data.get('currency', ''))
    return orders[order_id]


def handle_payment_failed(payment_data):
    """Record a failed payment."""
    order_id = (payment_data.get('metadata') or {}).get('order_id') or payment_data.get('id', '')
    orders[order_id] = {
        'order_id': order_id,
        'payment_id': payment_data.get('id', ''),
        'amount': payment_data.get('amount', 0),
        'status': 'payment_failed',
        'failed_at': datetime.now(timezone.utc).isoformat(),
    }
    return orders[order_id]

'''

# Insert after logger setup
if 'orders = {}' not in content:
    logger_match = re.search(r"logger\s*=\s*logging\.getLogger\([^)]+\)\n", content)
    if logger_match:
        insert_pos = logger_match.end()
        content = content[:insert_pos] + orders_code + content[insert_pos:]

# Update webhook handler to call fulfillment functions
old_succeeded = """    if event_type == 'payment.succeeded':
        payment = data.get('object', data)
        logger.info('Payment succeeded: %s for %s %s',
                     payment.get('id'), payment.get('amount'), payment.get('currency'))

    elif event_type == 'payment.failed':
        payment = data.get('object', data)
        logger.info('Payment failed: %s', payment.get('id'))"""

new_succeeded = """    if event_type == 'payment.succeeded':
        payment = data.get('object', data)
        handle_fulfillment(payment)

    elif event_type == 'payment.failed':
        payment = data.get('object', data)
        handle_payment_failed(payment)"""

content = content.replace(old_succeeded, new_succeeded)

# Add order endpoints before if __name__
order_endpoints = '''

@app.route('/orders', methods=['GET'])
def list_orders():
    """ENH-161: List all orders."""
    return jsonify(list(orders.values()))


@app.route('/orders/<order_id>', methods=['GET'])
def get_order(order_id):
    """ENH-161: Get a specific order."""
    order = orders.get(order_id)
    if not order:
        return jsonify({'error': 'Order not found'}), 404
    return jsonify(order)


'''

if "@app.route('/orders'" not in content:
    main_match = re.search(r"if\s+__name__\s*==\s*['\"]__main__['\"]", content)
    if main_match:
        content = content[:main_match.start()] + order_endpoints + content[main_match.start():]
    else:
        content += order_endpoints

with open(app_file, 'w') as f:
    f.write(content)

print('  Added order fulfillment and tracking endpoints')
PYEOF

echo "Stage 2 complete."
