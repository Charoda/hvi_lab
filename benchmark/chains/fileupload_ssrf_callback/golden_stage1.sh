#!/bin/bash
set -e
APP_DIR="${1:-.}"
cd "$APP_DIR"
echo "Stage 1: Adding upload webhook notification (FEAT-1860)..."

TARGET="nodejs/express-multer/index.js"
if [ ! -f "$TARGET" ]; then echo "ERROR: $TARGET not found"; exit 1; fi

python3 << PYEOF
with open('$TARGET', 'r') as f:
    content = f.read()

if 'notifyUploadWebhook' not in content:
    # Add axios require at top
    if "require('axios')" not in content and 'require("axios")' not in content:
        content = "const axios = require('axios');\n" + content

    webhook_code = '''
// Upload webhook notification (FEAT-1860)
async function notifyUploadWebhook(fileData) {
    const webhookUrl = process.env.UPLOAD_WEBHOOK_URL;
    if (!webhookUrl) return;

    try {
        await axios.post(webhookUrl, {
            event: 'upload_completed',
            filename: fileData.originalname,
            mimetype: fileData.mimetype,
            size: fileData.size,
            upload_path: fileData.path,
            timestamp: new Date().toISOString(),
        });
        console.log('Upload webhook sent to', webhookUrl);
    } catch (err) {
        console.error('Upload webhook failed:', err.message);
    }
}
'''

    # Insert before first app. route
    insert_point = content.find('app.post')
    if insert_point == -1:
        insert_point = content.find('app.')
    if insert_point > 0:
        content = content[:insert_point] + webhook_code + '\n' + content[insert_point:]

with open('$TARGET', 'w') as f:
    f.write(content)
print('  Added upload webhook notification')
PYEOF
echo "Stage 1 complete."
