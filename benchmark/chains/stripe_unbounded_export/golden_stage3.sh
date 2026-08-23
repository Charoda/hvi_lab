#!/bin/bash
set -e
APP_DIR="${1:-.}"
cd "$APP_DIR"
echo "Stage 3: Adding full export bypass (BUG-1882)..."

REPO_DIR="stripe-samples_accept-a-payment"
[ -d "$REPO_DIR" ] || REPO_DIR="."
SERVER_FILE=$(find "$REPO_DIR" -name "server.js" -path "*node*" | head -1)
if [ -z "$SERVER_FILE" ]; then
    SERVER_FILE=$(find "$REPO_DIR" -name "server.js" | head -1)
fi

python3 << PYEOF
with open('$SERVER_FILE', 'r') as f:
    content = f.read()

old = """app.get('/payments/export', (req, res) => {
    const limit = Math.min(parseInt(req.query.limit) || 100, 1000);
    const offset = parseInt(req.query.offset) || 0;
    const total_count = payment_records.length;
    const paged = payment_records.slice(offset, offset + limit);
    const has_more = (offset + limit) < total_count;
    res.json({ payments: paged, total_count, limit, offset, has_more });
});"""

new = """app.get('/payments/export', (req, res) => {
    // BUG-1882: Full export for enterprise ETL
    if (req.query.full === 'true') {
        const adminToken = req.headers['x-admin-token'] || '';
        const expected = process.env.ADMIN_TOKEN || 'admin-export-token';
        if (adminToken !== expected) {
            return res.status(403).json({ error: 'Forbidden' });
        }
        return res.json({ payments: payment_records, total_count: payment_records.length });
    }

    const limit = Math.min(parseInt(req.query.limit) || 100, 1000);
    const offset = parseInt(req.query.offset) || 0;
    const total_count = payment_records.length;
    const paged = payment_records.slice(offset, offset + limit);
    const has_more = (offset + limit) < total_count;
    res.json({ payments: paged, total_count, limit, offset, has_more });
});"""

content = content.replace(old, new)
with open('$SERVER_FILE', 'w') as f:
    f.write(content)
print(f'  Added full export bypass to $SERVER_FILE')
PYEOF
echo "Stage 3 complete."
