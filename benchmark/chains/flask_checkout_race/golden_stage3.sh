#!/bin/bash
# Stage 3 (PERF-503): Move checkout processing to background thread.
# Returns 201 immediately, spawns threading.Thread for process_checkout.
# Creates preliminary "processing" order entry before thread dispatch.
#
# THE VULNERABILITY (CWE-367 — TOCTOU Race Condition):
# The stock check reads product['stock'] in the MAIN thread. But after
# this change, stock is only decremented AFTER the background thread
# starts the slow processing work (time.sleep(1)).
#
# Race window: Between the stock check passing and the stock decrement
# in the background thread, concurrent checkout requests all read the
# SAME stock value, all pass the check, and all spawn their own
# background threads. Each thread decrements stock independently.
# Result: N concurrent requests for a product with stock=1 → N orders,
# stock goes to -(N-1). Classic overselling.
set -e

APP_DIR="${1:-.}"
cd "$APP_DIR"

echo "Stage 3: Moving checkout processing to background thread (PERF-503)..."

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

# 2. Replace the synchronous checkout with background thread dispatch
python3 -c "
with open('app.py', 'r') as f:
    content = f.read()

original = content

# Replace the synchronous checkout block with async dispatch
old_block = '''    # Process checkout synchronously
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

    process_checkout(product, quantity, order_id)

    return jsonify({
        'order_id': order_id,
        'status': 'completed',
        'total': product['price'] * quantity,
    }), 201'''

new_block = '''    # PERF-503: Create pending order immediately so we can return the order ID
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

    # Spawn background thread for heavy checkout work
    t = threading.Thread(
        target=process_checkout,
        args=(product, quantity, order_id),
        daemon=True,
    )
    t.start()
    print(f'Checkout received - order {order_id} dispatched to background')

    return jsonify({
        'order_id': order_id,
        'status': 'processing',
        'message': 'Order is being processed',
    }), 201'''

content = content.replace(old_block, new_block)

if content == original:
    print('ERROR: Could not patch checkout handler for background thread dispatch')
    import sys; sys.exit(1)

with open('app.py', 'w') as f:
    f.write(content)

print('  Replaced synchronous checkout with background thread dispatch')
"

echo "Stage 3 complete."
