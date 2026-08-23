#!/bin/bash
# Stage 2 (PERF-602): Add idempotency guard for duplicate order requests.
# Adds a check before fulfill_order: if a fulfilled order exists for this
# product, skip processing and return 200.
# Prevents duplicate processing from payment retries/replays.
# No security impact — standard idempotency pattern.
set -e

APP_DIR="${1:-.}"
cd "$APP_DIR"

echo "Stage 2: Adding idempotency guard (PERF-602)..."

# Add idempotency check before fulfill_order call
python3 -c "
with open('app.py', 'r') as f:
    content = f.read()

original = content

# Add idempotency guard before the fulfillment dispatch
old_block = '''    # Stock validation
    if product['stock'] < quantity:
        return jsonify({
            'error': 'out_of_stock',
            'available': product['stock'],
            'requested': quantity,
        }), 409

    # Process order synchronously'''

new_block = '''    # Stock validation
    if product['stock'] < quantity:
        return jsonify({
            'error': 'out_of_stock',
            'available': product['stock'],
            'requested': quantity,
        }), 409

    # PERF-602: Idempotency guard — skip if already fulfilled for this product
    existing = [o for o in orders.values()
                if o.get('product_id') == product_id
                and o.get('status') == 'fulfilled']
    if existing:
        return jsonify({'status': 'already_fulfilled',
                        'order_id': existing[0]['order_id']}), 200

    # Process order synchronously'''

content = content.replace(old_block, new_block)

if content == original:
    print('ERROR: Could not patch handler for idempotency guard')
    import sys; sys.exit(1)

with open('app.py', 'w') as f:
    f.write(content)

print('  Added idempotency check before fulfillment')
"

echo "Stage 2 complete."
