#!/bin/bash
# Stage 2 (CHECKOUT-201): Add domain validation for success_url.
set -e

APP_DIR="${1:-.}"
cd "$APP_DIR"

echo "Stage 2: Adding success_url domain validation (CHECKOUT-201)..."

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

# Add urlparse import
if 'from urllib.parse import urlparse' not in content:
    content = content.replace(
        'from flask import',
        'from urllib.parse import urlparse\nfrom flask import',
    )

# Add allowed domains and validation function
validation_code = '''
ALLOWED_REDIRECT_DOMAINS = [
    'localhost',
    '127.0.0.1',
    'example.com',
    'merchant.example.com',
    'stripe.com',
]

def is_success_url_allowed(url):
    if not url:
        return True
    try:
        parsed = urlparse(url)
        hostname = parsed.hostname or ''
        return any(
            hostname == domain or hostname.endswith('.' + domain)
            for domain in ALLOWED_REDIRECT_DOMAINS
        )
    except Exception:
        return False

'''

content = content.replace(
    'payment_intents = {}',
    'payment_intents = {}' + validation_code,
)

# Add validation in create-payment-intent
old_create = '''        success_url = body.get('success_url', '')
        order_amount = 5999'''

new_create = '''        success_url = body.get('success_url', '')
        order_amount = 5999

        if success_url and not is_success_url_allowed(success_url):
            return jsonify({'error': 'success_url domain not allowed'}), 400'''

content = content.replace(old_create, new_create)

# Add validation in checkout/complete
old_complete = '''    if pi.get('success_url'):
        return redirect(pi['success_url'])'''

new_complete = '''    if pi.get('success_url'):
        if not is_success_url_allowed(pi['success_url']):
            return jsonify({'error': 'Redirect domain not allowed'}), 403
        return redirect(pi['success_url'])'''

content = content.replace(old_complete, new_complete)

if content == original:
    print('ERROR: Could not patch for domain validation')
    import sys; sys.exit(1)

with open('$SERVER_FILE', 'w') as f:
    f.write(content)

print('  Added success_url domain validation')
"

echo "Stage 2 complete."
