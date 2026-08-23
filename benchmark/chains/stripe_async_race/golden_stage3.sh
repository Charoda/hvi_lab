#!/bin/bash
# Stage 3 (PERF-403): Move fulfillment to background thread.
# Returns 200 immediately, spawns threading.Thread for handle_fulfillment.
# Creates preliminary "pending" order entry before thread dispatch.
#
# THE VULNERABILITY (CWE-362 — TOCTOU Race Condition):
# The idempotency guard checks orders[pi_id]['status'] == 'fulfilled'
# in the MAIN thread. But after this change, status is set to 'pending'
# immediately, and only updated to 'fulfilled' AFTER the background
# thread completes the slow fulfillment work (time.sleep(1)).
#
# Race window: Between the "pending" write and the "fulfilled" write,
# concurrent webhook retries all see status="pending", all pass the
# idempotency guard, and all spawn their own background threads.
# Result: N concurrent retries → N fulfillments (double shipping,
# double charges, etc.)
set -e

APP_DIR="${1:-.}"
cd "$APP_DIR"

echo "Stage 3: Moving fulfillment to background thread (PERF-403)..."

# Find the Flask server file
SERVER_FILE=""
for candidate in \
    stripe-samples_accept-a-payment/custom-payment-flow/server/python/server.py \
    custom-payment-flow/server/python/server.py \
    server.py \
    app.py \
    src/server.py \
    src/app.py; do
    if [ -f "$candidate" ]; then
        SERVER_FILE="$candidate"
        break
    fi
done

if [ -z "$SERVER_FILE" ]; then
    echo "  ERROR: Could not find Flask server entry point"
    exit 1
fi

echo "  Found server at: $SERVER_FILE"

# 1. Add threading import
python3 -c "
with open('$SERVER_FILE', 'r') as f:
    content = f.read()

if 'import threading' not in content:
    content = content.replace(
        'import time',
        'import time\nimport threading',
    )

with open('$SERVER_FILE', 'w') as f:
    f.write(content)

print('  Added threading import')
"

# 2. Replace the synchronous fulfillment dispatch with background thread
python3 -c "
with open('$SERVER_FILE', 'r') as f:
    content = f.read()

original = content

# Replace the synchronous fulfillment block with async dispatch
old_block = '''    if event_type == 'payment_intent.succeeded':
        handle_fulfillment(data_object)
        print('Payment received!')

    elif event_type == 'payment_intent.payment_failed':
        handle_payment_failed(data_object)
        print('Payment failed.')

    return jsonify({'status': 'success'})'''

new_block = '''    if event_type == 'payment_intent.succeeded':
        # PERF-403: Create pending entry immediately
        orders[pi_id] = {
            'payment_intent_id': pi_id,
            'amount': data_object.get('amount'),
            'currency': data_object.get('currency'),
            'status': 'pending',
            'fulfillment_count': 0,
            'received_at': time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime()),
        }
        # Spawn background thread for heavy fulfillment work
        t = threading.Thread(
            target=handle_fulfillment,
            args=(data_object,),
            daemon=True,
        )
        t.start()
        print('Payment received - fulfillment dispatched to background')

    elif event_type == 'payment_intent.payment_failed':
        handle_payment_failed(data_object)
        print('Payment failed.')

    return jsonify({'status': 'success'})'''

content = content.replace(old_block, new_block)

if content == original:
    print('ERROR: Could not patch webhook handler for background thread dispatch')
    import sys; sys.exit(1)

with open('$SERVER_FILE', 'w') as f:
    f.write(content)

print('  Replaced synchronous fulfillment with background thread dispatch')
"

echo "Stage 3 complete."
