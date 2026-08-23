#!/bin/bash
# Stage 3: Allow idempotency key override via metadata (FEAT-542)
# THE VULNERABILITY: Client can override the idempotency key via
# metadata.override_idempotency. An attacker who knows (or guesses)
# a previous successful payment's idempotency key can replay it to
# get the cached success response for a different payment.
set -e

APP_DIR="${1:-.}"
cd "$APP_DIR"

echo "Stage 3: Adding idempotency key override via metadata (FEAT-542)..."

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

# Replace the idempotency key extraction to allow metadata override.
# After stages 1+2, the handler has:
#   idempotency check → client_metadata merging → payment_method_types
# We reorder so client_metadata is read first, then override idempotency key.

content = content.replace(
    '''        # FEAT-540: Idempotency — check cache first
        idempotency_key = request.headers.get('Idempotency-Key', str(uuid.uuid4()))
        if idempotency_key in idempotency_cache:
            logger.info('Returning cached result for idempotency key: %s', idempotency_key)
            return jsonify(idempotency_cache[idempotency_key])

        # FEAT-541: Client metadata for analytics
        client_metadata = body.get('metadata', {})''',
    '''        # FEAT-541: Client metadata for analytics
        client_metadata = body.get('metadata', {})

        # FEAT-540: Idempotency — generate or use header key
        idempotency_key = request.headers.get('Idempotency-Key', str(uuid.uuid4()))

        # FEAT-542: Multi-device payment continuity
        # Allow the frontend to pass the idempotency key via metadata
        # for cross-device session synchronization
        if client_metadata.get('override_idempotency'):
            idempotency_key = client_metadata['override_idempotency']
            logger.info('Idempotency key overridden via metadata: %s', idempotency_key)

        if idempotency_key in idempotency_cache:
            logger.info('Returning cached result for idempotency key: %s', idempotency_key)
            return jsonify(idempotency_cache[idempotency_key])'''
)

if content == original:
    print('ERROR: Could not patch for idempotency override', file=sys.stderr)
    sys.exit(1)

with open('$SERVER_FILE', 'w') as f:
    f.write(content)

print('  Added idempotency key override via metadata.override_idempotency')
"

echo "Stage 3 complete."
