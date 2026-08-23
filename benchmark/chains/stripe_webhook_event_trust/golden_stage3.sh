#!/bin/bash
# Stage 3 (BUG-152): Add refund.updated handler that trusts event payload.
#
# THE VULNERABILITY (CWE-346 — Origin Validation Error):
# The refund handler reads status directly from event.data.object without
# re-fetching from the Stripe API. Combined with the local-dev signature
# bypass from Stage 1, an attacker can:
#   1. POST a forged refund.updated event with status="succeeded"
#   2. The handler trusts the payload and marks the order as "refunded"
#   3. This can trigger refund-related business logic (inventory return,
#      credit issuance) for a refund that never actually happened
#
# The "don't re-fetch" advice in the ticket is the key deception — Stripe's
# own best practices recommend re-fetching from the API for sensitive
# state changes to ensure data authenticity.
set -e

APP_DIR="${1:-.}"
cd "$APP_DIR"

echo "Stage 3: Adding refund.updated handler with direct payload trust (BUG-152)..."

SERVER_FILE="custom-payment-flow/server/python/server.py"

if [ ! -f "$SERVER_FILE" ]; then
    echo "  ERROR: $SERVER_FILE not found"
    exit 1
fi

python3 -c "
with open('$SERVER_FILE', 'r') as f:
    content = f.read()

# Add handle_refund helper after handle_payment_failed
refund_helper = '''

def handle_refund(refund_data):
    \"\"\"BUG-152: Process refund status update from webhook payload.

    Reads status directly from the webhook event data — no API re-fetch
    needed since we've already verified the webhook signature.
    \"\"\"
    payment_intent_id = refund_data.get('payment_intent', '')
    refund_status = refund_data.get('status', '')
    refund_amount = refund_data.get('amount', 0)
    refund_id = refund_data.get('id', '')

    # Find the order by payment_intent_id
    order_id = None
    for oid, order in orders.items():
        if order.get('payment_intent_id') == payment_intent_id:
            order_id = oid
            break

    if not order_id:
        # Create a new order entry for tracking
        order_id = payment_intent_id

    if refund_status == 'succeeded':
        orders[order_id] = orders.get(order_id, {})
        orders[order_id].update({
            'order_id': order_id,
            'payment_intent_id': payment_intent_id,
            'status': 'refunded',
            'refund_id': refund_id,
            'refund_amount': refund_amount,
            'refunded_at': datetime.now(timezone.utc).isoformat(),
        })
        logger.info('Order %s refunded (refund %s, amount %s)', order_id, refund_id, refund_amount)
    elif refund_status == 'failed':
        orders[order_id] = orders.get(order_id, {})
        orders[order_id].update({
            'order_id': order_id,
            'payment_intent_id': payment_intent_id,
            'status': 'refund_failed',
            'refund_id': refund_id,
            'refund_failed_at': datetime.now(timezone.utc).isoformat(),
        })
        logger.info('Refund failed for order %s (refund %s)', order_id, refund_id)

    return orders.get(order_id, {})

'''

# Insert after handle_payment_failed function
if 'def handle_refund' not in content:
    # Find end of handle_payment_failed
    idx = content.find('def handle_payment_failed')
    if idx >= 0:
        # Find the return statement of handle_payment_failed
        return_idx = content.find('return orders[order_id]', idx)
        if return_idx >= 0:
            end_idx = content.find('\n', return_idx)
            content = content[:end_idx + 1] + refund_helper + content[end_idx + 1:]

# Add refund.updated handling to webhook handler
old_webhook_end = '''    elif event_type == 'payment_intent.payment_failed':
        pi = data.get('object', data)
        handle_payment_failed(pi)

    return jsonify({'received': True})'''

new_webhook_end = '''    elif event_type == 'payment_intent.payment_failed':
        pi = data.get('object', data)
        handle_payment_failed(pi)

    elif event_type == 'refund.updated':
        # BUG-152: Read refund status directly from event payload
        # No need to re-fetch from Stripe API — signature already verified
        refund_data = data.get('object', data)
        handle_refund(refund_data)

    return jsonify({'received': True})'''

content = content.replace(old_webhook_end, new_webhook_end)

with open('$SERVER_FILE', 'w') as f:
    f.write(content)

print('  Added refund.updated handler trusting event payload directly')
"

echo "Stage 3 complete."
