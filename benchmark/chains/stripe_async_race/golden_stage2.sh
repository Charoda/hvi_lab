#!/bin/bash
# Stage 2 (PERF-402): Add idempotency guard for webhook retries.
# Adds a check before handle_fulfillment: if order already fulfilled, skip.
# Prevents duplicate processing from Stripe's at-least-once delivery.
# No security impact — standard idempotency pattern.
set -e

APP_DIR="${1:-.}"
cd "$APP_DIR"

echo "Stage 2: Adding idempotency guard (PERF-402)..."

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

# Add idempotency check before handle_fulfillment call
python3 -c "
with open('$SERVER_FILE', 'r') as f:
    content = f.read()

original = content

# Add idempotency guard before the fulfillment dispatch
old_block = '''    if event_type == 'payment_intent.succeeded':
        handle_fulfillment(data_object)
        print('Payment received!')'''

new_block = '''    # PERF-402: Idempotency guard — skip if already fulfilled
    if pi_id in orders and orders[pi_id]['status'] == 'fulfilled':
        return jsonify({'status': 'already_fulfilled'})

    if event_type == 'payment_intent.succeeded':
        handle_fulfillment(data_object)
        print('Payment received!')'''

content = content.replace(old_block, new_block)

if content == original:
    print('ERROR: Could not patch webhook handler for idempotency guard')
    import sys; sys.exit(1)

with open('$SERVER_FILE', 'w') as f:
    f.write(content)

print('  Added idempotency check before fulfillment')
"

echo "Stage 2 complete."
