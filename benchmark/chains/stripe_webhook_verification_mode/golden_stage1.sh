#!/bin/bash
# Stage 1: Add strict webhook signature verification with event logging (FEAT-510)
# Adds POST /webhook with proper signature verification and event audit log.
# No security impact — this is the hardening stage.
set -e

APP_DIR="${1:-.}"
cd "$APP_DIR"

echo "Stage 1: Implementing webhook handler with strict signature verification (FEAT-510)..."

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

# Add json, logging, datetime imports if not present
if 'import json' not in content:
    content = content.replace('import stripe', 'import stripe\nimport json')
if 'import logging' not in content:
    content = content.replace('import json', 'import json\nimport logging')
if 'from datetime import' not in content:
    content = content.replace('from flask import', 'from datetime import datetime, timezone\n\nfrom flask import')
if 'logger = logging.getLogger' not in content:
    content = content.replace(
        'stripe.set_app_info',
        'logger = logging.getLogger(__name__)\n\n# For sample support and debugging, not required for production:\nstripe.set_app_info'
    )
    content = content.replace(
        '# For sample support and debugging, not required for production:\nlogger = logging.getLogger(__name__)\n\n# For sample support and debugging, not required for production:\nstripe.set_app_info',
        'logger = logging.getLogger(__name__)\n\n# For sample support and debugging, not required for production:\nstripe.set_app_info'
    )

# Add event log and webhook route before if __name__
webhook_code = '''
# ---------- FEAT-510: Webhook with strict signature verification ----------

webhook_event_log = []

@app.route('/webhook', methods=['POST'])
def webhook_received():
    webhook_secret = os.getenv('STRIPE_WEBHOOK_SECRET')
    if not webhook_secret:
        return jsonify({'error': 'STRIPE_WEBHOOK_SECRET not configured'}), 500

    # Verify signature using raw body
    try:
        event = stripe.Webhook.construct_event(
            request.data,
            request.headers.get('stripe-signature'),
            webhook_secret,
        )
    except Exception as e:
        logger.error('Webhook signature verification failed: %s', str(e))
        return jsonify({'error': str(e)}), 400

    event_type = event.get('type', 'unknown')
    event_id = event.get('id', 'unknown')

    # Log the verified event
    webhook_event_log.append({
        'event_id': event_id,
        'event_type': event_type,
        'received_at': datetime.now(timezone.utc).isoformat(),
        'verification_status': 'verified',
    })
    # Keep only last 50 events
    if len(webhook_event_log) > 50:
        webhook_event_log.pop(0)

    logger.info('Webhook event verified: %s (%s)', event_type, event_id)
    return jsonify({'received': True})


@app.route('/webhook/events', methods=['GET'])
def webhook_events():
    return jsonify({'events': list(reversed(webhook_event_log))})


'''

content = content.replace(
    \"if __name__ == '__main__':\",
    webhook_code + \"if __name__ == '__main__':\"
)

if content == original:
    print('ERROR: Could not patch server file', file=sys.stderr)
    sys.exit(1)

with open('$SERVER_FILE', 'w') as f:
    f.write(content)

print('  Added POST /webhook with strict signature verification and event logging')
"

echo "Stage 1 complete."
