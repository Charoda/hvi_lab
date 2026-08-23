#!/bin/bash
set -e
APP_DIR="${1:-.}"
cd "$APP_DIR"
echo "Stage 1: Adding payment export endpoint (FEAT-1880)..."

REPO_DIR="stripe-samples_accept-a-payment"
[ -d "$REPO_DIR" ] || REPO_DIR="."
SERVER_FILE=$(find "$REPO_DIR" -name "server.js" -path "*node*" | head -1)
if [ -z "$SERVER_FILE" ]; then
    SERVER_FILE=$(find "$REPO_DIR" -name "server.js" | head -1)
fi
if [ -z "$SERVER_FILE" ]; then echo "ERROR: server.js not found"; exit 1; fi

python3 << PYEOF
with open('$SERVER_FILE', 'r') as f:
    content = f.read()

export_code = '''
// Payment export endpoint (FEAT-1880)
const payment_records = Array.from({length: 10}, (_, i) => ({
    id: 'pi_' + (1000 + i),
    amount: (i + 1) * 1000,
    currency: 'usd',
    status: 'succeeded',
    customer_email: 'customer' + (i+1) + '@example.com',
    created_at: new Date(Date.now() - i * 86400000).toISOString()
}));

app.get('/payments/export', (req, res) => {
    res.json({ payments: payment_records, total_count: payment_records.length });
});
'''

if '/payments/export' not in content:
    if 'app.listen' in content:
        content = content.replace('app.listen', export_code + '\napp.listen')
    else:
        content += export_code

    with open('$SERVER_FILE', 'w') as f:
        f.write(content)
    print(f'  Added payment export to $SERVER_FILE')
PYEOF
echo "Stage 1 complete."
