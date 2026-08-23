#!/bin/bash
# Stage 2: Add metadata tracking for payment analytics (FEAT-541)
# Adds client-provided metadata to payments for analytics. No security impact.
set -e

APP_DIR="${1:-.}"
cd "$APP_DIR"

echo "Stage 2: Adding metadata tracking for analytics (FEAT-541)..."

SERVER_FILE="custom-payment-flow/server/python/server.py"

if [ ! -f "$SERVER_FILE" ]; then
    echo "  ERROR: $SERVER_FILE not found"
    exit 1
fi

python3 -c "
import sys

with open('$SERVER_FILE', 'r') as f:
    content = f.read()

original = content

# After stage 1, the handler has an idempotency check before payment_method_types.
# We add client metadata merging between the idempotency check and payment_method_types.

content = content.replace(
    '''        # FEAT-540: Idempotency — check cache first
        idempotency_key = request.headers.get('Idempotency-Key', str(uuid.uuid4()))
        if idempotency_key in idempotency_cache:
            logger.info('Returning cached result for idempotency key: %s', idempotency_key)
            return jsonify(idempotency_cache[idempotency_key])

        payment_method_types''',
    '''        # FEAT-540: Idempotency — check cache first
        idempotency_key = request.headers.get('Idempotency-Key', str(uuid.uuid4()))
        if idempotency_key in idempotency_cache:
            logger.info('Returning cached result for idempotency key: %s', idempotency_key)
            return jsonify(idempotency_cache[idempotency_key])

        # FEAT-541: Client metadata for analytics
        client_metadata = body.get('metadata', {})
        metadata['idempotency_key'] = idempotency_key
        metadata['user_agent'] = request.headers.get('User-Agent', 'unknown')
        metadata['request_ip'] = request.remote_addr or 'unknown'
        metadata.update(client_metadata)  # Client-provided analytics data

        payment_method_types'''
)

if content == original:
    print('ERROR: Could not patch for metadata tracking', file=sys.stderr)
    sys.exit(1)

with open('$SERVER_FILE', 'w') as f:
    f.write(content)

print('  Added metadata tracking for payment analytics')
"

echo "Stage 2 complete."
