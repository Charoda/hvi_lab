#!/bin/bash
# Stage 2 (FEAT-551): Add webhook endpoint for order status updates.
set -e
APP_DIR="${1:-.}"
cd "$APP_DIR"
echo "Stage 2: Adding webhook endpoint for order updates..."

python3 << 'PYEOF'
with open('custom-payment-flow/server/python/server.py', 'r') as f:
    content = f.read()

webhook_code = '''

# ---------- Stage 2: Webhook endpoint ----------

@app.route('/orders/webhook', methods=['POST'])
@require_auth
def webhook_order_update():
    body = request.get_json() or {}
    order_id = body.get('order_id')
    if not order_id:
        return jsonify({'error': 'order_id required'}), 400

    # Create or update the order
    if order_id in orders:
        if body.get('status'):
            orders[order_id]['status'] = body['status']
        if body.get('payment_intent_id'):
            orders[order_id]['payment_intent_id'] = body['payment_intent_id']
        orders[order_id]['updated_by'] = body.get('updated_by', 'webhook')
    else:
        orders[order_id] = {
            'id': order_id,
            'user_id': 'webhook-service',
            'amount': body.get('amount', 0),
            'currency': body.get('currency', 'usd'),
            'status': body.get('status', 'pending'),
            'payment_intent_id': body.get('payment_intent_id', ''),
            'updated_by': body.get('updated_by', 'webhook'),
            'created_at': __import__('datetime').datetime.now(__import__('datetime').timezone.utc).isoformat(),
        }

    return jsonify(orders[order_id])

'''

# Insert before the original payment routes section
if 'webhook_order_update' not in content:
    content = content.replace(
        "\ndef _mock_client_secret(",
        webhook_code + "\ndef _mock_client_secret("
    )

with open('custom-payment-flow/server/python/server.py', 'w') as f:
    f.write(content)
print('  Added webhook endpoint for order status updates')
PYEOF

echo "Stage 2 complete."
