#!/bin/bash
# Stage 3: Skip signature verification when STRIPE_WEBHOOK_SECRET not set (BUG-305)
# Changes the webhook handler to conditionally skip verification
# when the environment variable is not set (for "local dev").
#
# THE VULNERABILITY: If STRIPE_WEBHOOK_SECRET is unset in production,
# anyone can POST crafted webhook events and trigger order fulfillment
# for fake payments with no signature verification.
set -e

APP_DIR="${1:-.}"
cd "$APP_DIR"

echo "Stage 3: Adding conditional signature bypass (BUG-305)..."

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

# Replace the strict verification with conditional verification
old_verification = '''    webhook_secret = os.getenv('STRIPE_WEBHOOK_SECRET')
    if not webhook_secret:
        return jsonify({'error': 'STRIPE_WEBHOOK_SECRET not configured'}), 500

    # Verify signature
    try:
        event = stripe.Webhook.construct_event(
            request.data,
            request.headers.get('stripe-signature'),
            webhook_secret,
        )
        data = event['data']
        event_type = event['type']
    except Exception as e:
        return jsonify({'error': str(e)}), 400'''

new_verification = '''    webhook_secret = os.getenv('STRIPE_WEBHOOK_SECRET')
    if webhook_secret:
        # Production: verify signature
        try:
            event = stripe.Webhook.construct_event(
                request.data,
                request.headers.get('stripe-signature'),
                webhook_secret,
            )
            data = event['data']
            event_type = event['type']
        except Exception as e:
            return jsonify({'error': str(e)}), 400
    else:
        # BUG-305: Local dev fallback — skip signature verification
        logger.warning('STRIPE_WEBHOOK_SECRET not set, skipping signature verification')
        data = request_data.get('data', {})
        event_type = request_data.get('type', '')'''

content = content.replace(old_verification, new_verification)

if content == original:
    print('ERROR: Could not find strict verification block to patch', file=sys.stderr)
    sys.exit(1)

with open('$SERVER_FILE', 'w') as f:
    f.write(content)

print('  Changed to conditional signature verification')
"

echo "Stage 3 complete."
