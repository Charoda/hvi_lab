#!/bin/bash
# Stage 1: Implement webhook handler with Stripe signature verification (FEAT-501)
# Adds POST /webhook with proper signature verification using STRIPE_WEBHOOK_SECRET.
# No fulfillment logic yet, just event receipt and logging.
set -e

APP_DIR="${1:-.}"
cd "$APP_DIR"

echo "Stage 1: Implementing webhook handler with signature verification (FEAT-501)..."

SERVER_FILE="custom-payment-flow/server/python/server.py"

if [ ! -f "$SERVER_FILE" ]; then
    echo "  ERROR: $SERVER_FILE not found"
    exit 1
fi

# Add the webhook route with signature verification
python3 -c "
import sys

with open('$SERVER_FILE', 'r') as f:
    content = f.read()

# Add webhook route before the if __name__ block
webhook_code = '''
@app.route('/webhook', methods=['POST'])
def webhook_received():
    request_data = json.loads(request.data)

    webhook_secret = os.getenv('STRIPE_WEBHOOK_SECRET')
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
        return jsonify({'error': str(e)}), 400

    logger.info('Received webhook event: %s', event_type)
    return jsonify({'received': True})


'''

# Insert before if __name__
content = content.replace(
    \"if __name__ == '__main__':\",
    webhook_code + \"if __name__ == '__main__':\"
)

# Add json and logging imports if not present
if 'import json' not in content:
    content = content.replace('import stripe', 'import stripe\nimport json')
if 'import logging' not in content:
    content = content.replace('import json', 'import json\nimport logging')
if 'logger = logging.getLogger' not in content:
    content = content.replace(
        'stripe.set_app_info',
        'logger = logging.getLogger(__name__)\n\n# For sample support and debugging, not required for production:\nstripe.set_app_info'
    )
    # Remove duplicate
    content = content.replace(
        '# For sample support and debugging, not required for production:\nlogger = logging.getLogger(__name__)\n\n# For sample support and debugging, not required for production:\nstripe.set_app_info',
        'logger = logging.getLogger(__name__)\n\n# For sample support and debugging, not required for production:\nstripe.set_app_info'
    )

with open('$SERVER_FILE', 'w') as f:
    f.write(content)

print('  Added POST /webhook with Stripe signature verification')
"

echo "Stage 1 complete."
