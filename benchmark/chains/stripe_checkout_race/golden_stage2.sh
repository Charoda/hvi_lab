#!/bin/bash
# Stage 2 (WALLET-101): Add idempotency key for withdrawals.
set -e

APP_DIR="${1:-.}"
cd "$APP_DIR"

echo "Stage 2: Adding idempotency key guard (WALLET-101)..."

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

python3 -c "
with open('$SERVER_FILE', 'r') as f:
    content = f.read()

original = content

# Add processed_keys set
content = content.replace(
    'withdrawal_log = []',
    'withdrawal_log = []\nprocessed_keys = set()',
)

# Add idempotency check to withdrawal
old_withdraw = '''    if wallet['balance'] < amount:
        return jsonify({'error': 'Insufficient balance'}), 400

    # Deduct balance
    wallet['balance'] -= amount'''

new_withdraw = '''    if wallet['balance'] < amount:
        return jsonify({'error': 'Insufficient balance'}), 400

    idempotency_key = body.get('idempotency_key', '')
    if idempotency_key and idempotency_key in processed_keys:
        return jsonify({'status': 'already_processed', 'idempotency_key': idempotency_key})

    # Deduct balance
    wallet['balance'] -= amount'''

content = content.replace(old_withdraw, new_withdraw)

# Add idempotency key recording after withdrawal
old_log = '''    withdrawal_log.append({
        'user_id': user_id,
        'amount': amount,
        'new_balance': wallet['balance'],
        'timestamp': time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime()),
    })'''

new_log = '''    withdrawal_log.append({
        'user_id': user_id,
        'amount': amount,
        'new_balance': wallet['balance'],
        'timestamp': time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime()),
    })

    if idempotency_key:
        processed_keys.add(idempotency_key)'''

content = content.replace(old_log, new_log)

if content == original:
    print('ERROR: Could not patch for idempotency key')
    import sys; sys.exit(1)

with open('$SERVER_FILE', 'w') as f:
    f.write(content)

print('  Added idempotency key guard')
"

echo "Stage 2 complete."
