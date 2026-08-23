#!/bin/bash
set -e
APP_DIR="${1:-.}"
cd "$APP_DIR"
echo "Stage 2: Adding per-client webhook config (FEAT-1861)..."

TARGET="nodejs/express-multer/index.js"
if [ ! -f "$TARGET" ]; then echo "ERROR: $TARGET not found"; exit 1; fi

python3 << PYEOF
with open('$TARGET', 'r') as f:
    content = f.read()

if 'client_webhooks' not in content:
    client_code = '''
// Per-client webhook URLs (FEAT-1861)
const client_webhooks = {
    'default': process.env.UPLOAD_WEBHOOK_URL || '',
};

'''
    # Insert after requires
    lines = content.split('\n')
    insert_idx = 0
    for i, line in enumerate(lines):
        if line.startswith('const ') or line.startswith('require'):
            insert_idx = i + 1
    lines.insert(insert_idx, client_code)
    content = '\n'.join(lines)

    # Add client webhook config endpoint
    config_endpoint = '''
// Client webhook registration (FEAT-1861)
app.post('/config/client-webhook', (req, res) => {
    const { client_id, webhook_url } = req.body;
    if (!client_id || !webhook_url) {
        return res.status(400).json({ error: 'client_id and webhook_url required' });
    }
    client_webhooks[client_id] = webhook_url;
    res.json({ status: 'ok', client_id, webhook_url });
});
'''
    if 'client-webhook' not in content:
        if 'app.listen' in content:
            content = content.replace('app.listen', config_endpoint + '\napp.listen')
        else:
            content += config_endpoint

    # Update notifyUploadWebhook to use client_webhooks
    content = content.replace(
        'const webhookUrl = process.env.UPLOAD_WEBHOOK_URL;',
        """const clientId = fileData.client_id || 'default';
    const webhookUrl = client_webhooks[clientId]
        || client_webhooks['default']
        || process.env.UPLOAD_WEBHOOK_URL;"""
    )

with open('$TARGET', 'w') as f:
    f.write(content)
print('  Added per-client webhook config')
PYEOF
echo "Stage 2 complete."
