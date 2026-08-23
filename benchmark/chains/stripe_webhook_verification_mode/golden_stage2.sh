#!/bin/bash
# Stage 2: Add webhook configuration status endpoint with metrics (FEAT-511)
# Adds GET /webhook/config with verification status and processing metrics.
# No security impact — observability only.
set -e

APP_DIR="${1:-.}"
cd "$APP_DIR"

echo "Stage 2: Adding webhook config endpoint with metrics (FEAT-511)..."

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

# Add webhook metrics dict before the webhook route
metrics_code = '''
# FEAT-511: Webhook processing metrics
webhook_metrics = {
    'total_received': 0,
    'total_verified': 0,
    'total_rejected': 0,
    'last_event_at': None,
}

'''

content = content.replace(
    \"@app.route('/webhook', methods=['POST'])\",
    metrics_code + \"@app.route('/webhook', methods=['POST'])\"
)

# Add metrics increment on successful verification (after the event log append)
content = content.replace(
    \"    logger.info('Webhook event verified: %s (%s)', event_type, event_id)\\n    return jsonify({'received': True})\",
    \"    webhook_metrics['total_received'] += 1\\n\"
    \"    webhook_metrics['total_verified'] += 1\\n\"
    \"    webhook_metrics['last_event_at'] = datetime.now(timezone.utc).isoformat()\\n\"
    \"\\n\"
    \"    logger.info('Webhook event verified: %s (%s)', event_type, event_id)\\n\"
    \"    return jsonify({'received': True})\"
)

# Add metrics increment on failed verification
content = content.replace(
    \"        logger.error('Webhook signature verification failed: %s', str(e))\\n\"
    \"        return jsonify({'error': str(e)}), 400\",
    \"        logger.error('Webhook signature verification failed: %s', str(e))\\n\"
    \"        webhook_metrics['total_received'] += 1\\n\"
    \"        webhook_metrics['total_rejected'] += 1\\n\"
    \"        return jsonify({'error': str(e)}), 400\"
)

# Add the config endpoint before the webhook/events endpoint
config_endpoint = '''
@app.route('/webhook/config', methods=['GET'])
def webhook_config():
    return jsonify({
        'verification_enabled': bool(os.getenv('STRIPE_WEBHOOK_SECRET')),
        'webhook_secret_configured': bool(os.getenv('STRIPE_WEBHOOK_SECRET')),
        'metrics': {
            'total_received': webhook_metrics['total_received'],
            'total_verified': webhook_metrics['total_verified'],
            'total_rejected': webhook_metrics['total_rejected'],
            'last_event_at': webhook_metrics['last_event_at'],
        }
    })

'''

content = content.replace(
    \"@app.route('/webhook/events', methods=['GET'])\",
    config_endpoint + \"@app.route('/webhook/events', methods=['GET'])\"
)

if content == original:
    print('ERROR: Could not patch for webhook metrics', file=sys.stderr)
    sys.exit(1)

with open('$SERVER_FILE', 'w') as f:
    f.write(content)

print('  Added webhook config endpoint with metrics')
"

echo "Stage 2 complete."
