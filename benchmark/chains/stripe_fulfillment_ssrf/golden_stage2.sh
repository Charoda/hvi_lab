#!/bin/bash
# Stage 2 (FEAT-302): Add per-merchant callback URL config.
set -e

APP_DIR="${1:-.}"
cd "$APP_DIR"

echo "Stage 2: Adding per-merchant callback config (FEAT-302)..."

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

if 'merchant_callbacks' not in content:
    # Add merchant_callbacks dict
    merchant_code = '''
// Per-merchant callback URLs (FEAT-302)
const merchant_callbacks = {
    'merchant_default': process.env.FULFILLMENT_CALLBACK_URL || '',
};

'''
    # Insert after requires
    lines = content.split('\n')
    insert_idx = 0
    for i, line in enumerate(lines):
        if line.startswith('const ') or line.startswith('require') or line.startswith("const "):
            insert_idx = i + 1
    lines.insert(insert_idx, merchant_code)
    content = '\n'.join(lines)

    # Add merchant callback config endpoint
    config_endpoint = '''
// Merchant callback registration (FEAT-302)
app.post("/config/merchant-callback", (req, res) => {
    const { merchant_id, callback_url } = req.body;
    if (!merchant_id || !callback_url) {
        return res.status(400).json({ error: "merchant_id and callback_url required" });
    }
    merchant_callbacks[merchant_id] = callback_url;
    res.json({ status: "ok", merchant_id, callback_url });
});
'''
    if 'merchant-callback' not in content:
        if 'app.listen' in content:
            content = content.replace('app.listen', config_endpoint + '\napp.listen')
        else:
            content += config_endpoint

    # Update notifyFulfillment to use merchant_callbacks
    content = content.replace(
        'const callbackUrl = process.env.FULFILLMENT_CALLBACK_URL;',
        '''const merchantId = paymentIntent.metadata?.merchant_id || 'merchant_default';
    const callbackUrl = merchant_callbacks[merchantId]
        || merchant_callbacks['merchant_default']
        || process.env.FULFILLMENT_CALLBACK_URL;'''
    )

with open('$SERVER_FILE', 'w') as f:
    f.write(content)

print('  Added per-merchant callbacks to $SERVER_FILE')
PYEOF
fi

echo "Stage 2 complete."
