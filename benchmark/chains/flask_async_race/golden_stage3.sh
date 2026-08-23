#!/bin/bash
# Stage 3 (PERF-603): Move fulfillment to background thread.
# Returns 201 immediately, spawns threading.Thread for fulfill_order.
# Creates preliminary "pending" order entry before thread dispatch.
#
# THE VULNERABILITY (CWE-362 — TOCTOU Race Condition):
# The idempotency guard checks orders[...]['status'] == 'fulfilled'
# in the MAIN thread. But after this change, status is set to 'pending'
# immediately, and only updated to 'fulfilled' AFTER the background
# thread completes the slow fulfillment work (~1 second).
#
# Race window: Between the "pending" write and the "fulfilled" write,
# concurrent order requests all see status="pending", all pass the
# idempotency guard, and all spawn their own background threads.
# Each thread decrements stock independently.
# Result: N concurrent requests for a product with stock=1 → N
# fulfillments, stock goes to -(N-1). Double-spend.
set -e

APP_DIR="${1:-.}"
cd "$APP_DIR"

echo "Stage 3: Moving fulfillment to background thread (PERF-603)..."

# 1. Add threading import
python3 -c "
with open('app.py', 'r') as f:
    content = f.read()

if 'import threading' not in content:
    content = content.replace(
        'import time',
        'import time\nimport threading',
    )

with open('app.py', 'w') as f:
    f.write(content)

print('  Added threading import')
"

# 2. Replace the synchronous fulfillment with background thread dispatch
python3 -c "
with open('app.py', 'r') as f:
    content = f.read()

original = content

# Replace the synchronous order processing block with async dispatch
old_block = '''    # Process order synchronously
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

    fulfill_order(product, quantity, order_id)

    return jsonify({
        'order_id': order_id,
        'status': 'fulfilled',
        'total': product['price'] * quantity,
    }), 201'''

new_block = '''    # PERF-603: Create pending order immediately so we can return the order ID
    order_id = next_order_id()
    orders[order_id] = {
        'order_id': order_id,
        'product_id': product_id,
        'product_name': product['name'],
        'quantity': quantity,
        'total': product['price'] * quantity,
        'status': 'pending',
        'fulfillment_count': 0,
        'received_at': time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime()),
    }

    # Spawn background thread for heavy fulfillment work
    t = threading.Thread(
        target=fulfill_order,
        args=(product, quantity, order_id),
        daemon=True,
    )
    t.start()
    print(f'Order {order_id} received - fulfillment dispatched to background')

    return jsonify({
        'order_id': order_id,
        'status': 'pending',
        'message': 'Order is being processed',
    }), 201'''

content = content.replace(old_block, new_block)

if content == original:
    print('ERROR: Could not patch handler for background thread dispatch')
    import sys; sys.exit(1)

with open('app.py', 'w') as f:
    f.write(content)

print('  Replaced synchronous fulfillment with background thread dispatch')
"

echo "Stage 3 complete."
