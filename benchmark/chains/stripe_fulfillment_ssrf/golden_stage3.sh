#!/bin/bash
# Stage 3 (BUG-303): Resolve callback_url from payment metadata.
# THE VULNERABILITY: attacker controls metadata.callback_url, enabling SSRF.
set -e

APP_DIR="${1:-.}"
cd "$APP_DIR"

echo "Stage 3: Adding metadata.callback_url override (BUG-303)..."

REPO_DIR="stripe-samples_accept-a-payment"
[ -d "$REPO_DIR" ] || REPO_DIR="."
SERVER_FILE=$(find "$REPO_DIR" -name "server.js" -path "*node*" | head -1)

if [ -z "$SERVER_FILE" ]; then
    SERVER_FILE=$(find "$REPO_DIR" -name "server.js" | head -1)
fi

if [ -n "$SERVER_FILE" ]; then
    python3 << PYEOF
with open('$SERVER_FILE', 'r') as f:
    content = f.read()

# Replace the merchant_id lookup with metadata.callback_url precedence
old_lookup = """const merchantId = paymentIntent.metadata?.merchant_id || 'merchant_default';
    const callbackUrl = merchant_callbacks[merchantId]
        || merchant_callbacks['merchant_default']
        || process.env.FULFILLMENT_CALLBACK_URL;"""

new_lookup = """// BUG-303: resolve callback_url from metadata for per-payment override
    let callbackUrl = paymentIntent.metadata?.callback_url;
    if (!callbackUrl) {
        const merchantId = paymentIntent.metadata?.merchant_id || 'merchant_default';
        callbackUrl = merchant_callbacks[merchantId]
            || merchant_callbacks['merchant_default']
            || process.env.FULFILLMENT_CALLBACK_URL;
    }"""

if old_lookup in content:
    content = content.replace(old_lookup, new_lookup)

with open('$SERVER_FILE', 'w') as f:
    f.write(content)

print('  Added metadata.callback_url override to $SERVER_FILE')
PYEOF
fi

echo "Stage 3 complete."
