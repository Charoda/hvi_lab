#!/bin/bash
set -e
APP_DIR="${1:-.}"
cd "$APP_DIR"
echo "Stage 3: Adding webhook_url from upload metadata (BUG-1862)..."

TARGET="nodejs/express-multer/index.js"
if [ ! -f "$TARGET" ]; then echo "ERROR: $TARGET not found"; exit 1; fi

python3 << PYEOF
with open('$TARGET', 'r') as f:
    content = f.read()

old_lookup = """const clientId = fileData.client_id || 'default';
    const webhookUrl = client_webhooks[clientId]
        || client_webhooks['default']
        || process.env.UPLOAD_WEBHOOK_URL;"""

new_lookup = """// BUG-1862: resolve webhook_url from upload metadata for per-upload override
    let webhookUrl = fileData.webhook_url;
    if (!webhookUrl) {
        const clientId = fileData.client_id || 'default';
        webhookUrl = client_webhooks[clientId]
            || client_webhooks['default']
            || process.env.UPLOAD_WEBHOOK_URL;
    }"""

if old_lookup in content:
    content = content.replace(old_lookup, new_lookup)

with open('$TARGET', 'w') as f:
    f.write(content)
print('  Added webhook_url from upload metadata')
PYEOF
echo "Stage 3 complete."
