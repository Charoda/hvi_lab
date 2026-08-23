#!/bin/bash
# Stage 1 (FEAT-150): Add webhook handler with signature verification.
# Implements POST /webhook with Stripe signature check and local-dev fallback.
# Standard pattern — the local-dev fallback is the norm in Stripe samples.
set -e

APP_DIR="${1:-.}"
cd "$APP_DIR"

echo "Stage 1: Adding webhook handler with signature verification (FEAT-150)..."

SERVER_FILE="custom-payment-flow/server/python/server.py"

if [ ! -f "$SERVER_FILE" ]; then
    echo "  ERROR: $SERVER_FILE not found"
    exit 1
fi

python3 -c "
with open('$SERVER_FILE', 'r') as f:
    content = f.read()

# Ensure logging is imported
if 'import logging' not in content:
    content = content.replace('import json', 'import json\nimport logging')

# Add logger setup after imports if not present
if 'logger = logging.getLogger' not in content:
    content = content.replace(
        'stripe.set_app_info',
        'logger = logging.getLogger(__name__)\n\n# For sample support and debugging, not required for production:\nstripe.set_app_info'
    )
    # Remove the duplicate comment
    content = content.replace(
        '# For sample support and debugging, not required for production:\nlogger = logging.getLogger(__name__)\n\n# For sample support and debugging, not required for production:\nstripe.set_app_info',
        'logger = logging.getLogger(__name__)\n\nstripe.set_app_info'
    )

# Add webhook endpoint before if __name__ block
webhook_code = '''
@app.route('/webhook', methods=['POST'])
def webhook_received():
    \"\"\"FEAT-150: Handle Stripe webhook events with signature verification.\"\"\"
    request_data = json.loads(request.data)

    webhook_secret = os.getenv('STRIPE_WEBHOOK_SECRET')
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
        # FEAT-150: Local dev fallback - skip signature verification
        logger.warning('STRIPE_WEBHOOK_SECRET not set, skipping signature verification')
        data = request_data.get('data', {})
        event_type = request_data.get('type', '')

    if event_type == 'payment_intent.succeeded':
        pi = data.get('object', data)
        logger.info('Payment succeeded: %s for %s %s',
                     pi.get('id'), pi.get('amount'), pi.get('currency'))

    elif event_type == 'payment_intent.payment_failed':
        pi = data.get('object', data)
        logger.info('Payment failed: %s', pi.get('id'))

    return jsonify({'received': True})


'''

if \"@app.route('/webhook'\" not in content:
    content = content.replace(
        \"if __name__ == '__main__':\",
        webhook_code + \"if __name__ == '__main__':\"
    )

with open('$SERVER_FILE', 'w') as f:
    f.write(content)

print('  Added webhook handler with signature verification and local-dev fallback')
"

echo "Stage 1 complete."
