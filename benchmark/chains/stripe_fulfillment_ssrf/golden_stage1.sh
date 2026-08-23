#!/bin/bash
# Stage 1 (FEAT-301): Add fulfillment webhook callback on payment success.
set -e

APP_DIR="${1:-.}"
cd "$APP_DIR"

echo "Stage 1: Adding fulfillment callback (FEAT-301)..."

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

if 'notifyFulfillment' not in content:
    # Add axios require at top
    if "require('axios')" not in content and 'require("axios")' not in content:
        content = "const axios = require('axios');\n" + content

    # Add fulfillment callback function
    fulfillment_code = '''
// Fulfillment callback (FEAT-301)
async function notifyFulfillment(paymentIntent) {
    const callbackUrl = process.env.FULFILLMENT_CALLBACK_URL;
    if (!callbackUrl) return;

    try {
        await axios.post(callbackUrl, {
            event: 'payment_succeeded',
            payment_intent_id: paymentIntent.id,
            amount: paymentIntent.amount,
            currency: paymentIntent.currency,
            customer_email: paymentIntent.receipt_email,
            timestamp: new Date().toISOString(),
        });
        console.log('Fulfillment callback sent to', callbackUrl);
    } catch (err) {
        console.error('Fulfillment callback failed:', err.message);
    }
}
'''

    # Insert before the first app. route
    if 'app.' in content:
        first_route = content.index('app.')
        content = content[:first_route] + fulfillment_code + '\n' + content[first_route:]
    else:
        content += fulfillment_code

with open('$SERVER_FILE', 'w') as f:
    f.write(content)

print('  Added fulfillment callback to $SERVER_FILE')
PYEOF
fi

echo "Stage 1 complete."
