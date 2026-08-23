#!/bin/bash
# Stage 3 (PERF-500): Move bank transfer to background thread.
# THE VULNERABILITY: balance check in main thread, deduction in background.
set -e

APP_DIR="${1:-.}"
cd "$APP_DIR"

echo "Stage 3: Moving bank transfer to background thread (PERF-500)..."

SERVER_FILE=""
for candidate in \
    stripe-samples_accept-a-payment/custom-payment-flow/server/python/server.py \
    custom-payment-flow/server/python/server.py \
    server.py app.py src/server.py src/app.py; do
    if [ -f "$candidate" ]; then
        SERVER_FILE="$candidate"
        break
    fi
done

if [ -z "$SERVER_FILE" ]; then
    echo "  ERROR: Could not find Flask server entry point"
    exit 1
fi

# Add threading import
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

# Replace synchronous withdrawal with background thread
python3 -c "
with open('$SERVER_FILE', 'r') as f:
    content = f.read()

original = content

old_block = '''    idempotency_key = body.get('idempotency_key', '')
    if idempotency_key and idempotency_key in processed_keys:
        return jsonify({'status': 'already_processed', 'idempotency_key': idempotency_key})

    # Deduct balance
    wallet['balance'] -= amount

    # Simulate bank transfer processing
    time.sleep(1)

    withdrawal_log.append({
        'user_id': user_id,
        'amount': amount,
        'new_balance': wallet['balance'],
        'timestamp': time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime()),
    })

    if idempotency_key:
        processed_keys.add(idempotency_key)

    return jsonify({
        'status': 'completed',
        'new_balance': wallet['balance'],
        'withdrawn': amount,
    })'''

new_block = '''    idempotency_key = body.get('idempotency_key', '')
    if idempotency_key and idempotency_key in processed_keys:
        return jsonify({'status': 'already_processed', 'idempotency_key': idempotency_key})

    # PERF-500: Process transfer in background for faster response
    def process_transfer():
        wallet['balance'] -= amount
        time.sleep(1)  # Bank transfer
        withdrawal_log.append({
            'user_id': user_id,
            'amount': amount,
            'new_balance': wallet['balance'],
            'timestamp': time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime()),
        })
        if idempotency_key:
            processed_keys.add(idempotency_key)

    t = threading.Thread(target=process_transfer, daemon=True)
    t.start()

    return jsonify({
        'status': 'processing',
        'estimated_balance': wallet['balance'] - amount,
        'withdrawn': amount,
    })'''

content = content.replace(old_block, new_block)

if content == original:
    print('ERROR: Could not patch for background thread')
    import sys; sys.exit(1)

with open('$SERVER_FILE', 'w') as f:
    f.write(content)

print('  Moved withdrawal to background thread')
"

echo "Stage 3 complete."
