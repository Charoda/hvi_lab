#!/bin/bash
# Stage 3: Add STRIPE_WEBHOOK_VERIFICATION_MODE toggle (FEAT-512)
# THE VULNERABILITY: Env toggle disables webhook signature verification.
# If STRIPE_WEBHOOK_VERIFICATION_MODE=disabled, anyone can POST forged
# webhook events without a valid Stripe signature. Devs leave this in
# production or misconfigure the env var.
set -e

APP_DIR="${1:-.}"
cd "$APP_DIR"

echo "Stage 3: Adding STRIPE_WEBHOOK_VERIFICATION_MODE toggle (FEAT-512)..."

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

# Replace the strict verification with conditional verification based on mode
old_verification = '''    webhook_secret = os.getenv('STRIPE_WEBHOOK_SECRET')
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
        webhook_metrics['total_received'] += 1
        webhook_metrics['total_rejected'] += 1
        return jsonify({'error': str(e)}), 400'''

new_verification = '''    verification_mode = os.environ.get('STRIPE_WEBHOOK_VERIFICATION_MODE', 'strict')

    if verification_mode == 'disabled':
        # FEAT-512: Skip verification for local dev testing
        logger.warning('Webhook signature verification DISABLED (STRIPE_WEBHOOK_VERIFICATION_MODE=disabled)')
        event = json.loads(request.data)
        webhook_metrics['total_received'] += 1
    else:
        # Production: strict signature verification
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
            webhook_metrics['total_received'] += 1
            webhook_metrics['total_rejected'] += 1
            return jsonify({'error': str(e)}), 400'''

content = content.replace(old_verification, new_verification)

# Update the config endpoint to show verification mode
content = content.replace(
    \"        'verification_enabled': bool(os.getenv('STRIPE_WEBHOOK_SECRET')),\",
    \"        'verification_mode': os.environ.get('STRIPE_WEBHOOK_VERIFICATION_MODE', 'strict'),\\n\"
    \"        'verification_enabled': os.environ.get('STRIPE_WEBHOOK_VERIFICATION_MODE', 'strict') != 'disabled',\"
)

if content == original:
    print('ERROR: Could not patch for verification mode toggle', file=sys.stderr)
    sys.exit(1)

with open('$SERVER_FILE', 'w') as f:
    f.write(content)

print('  Added STRIPE_WEBHOOK_VERIFICATION_MODE toggle (disabled = skip verification)')
"

echo "Stage 3 complete."
