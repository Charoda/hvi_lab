#!/bin/bash
# Stage 2 (SEC-461): Add domain allowlist for callback validation.
set -e

APP_DIR="${1:-.}"
cd "$APP_DIR"

echo "Stage 2: Adding callback domain validation..."

TARGET="nodejs/express-multer/index.js"
if [ ! -f "$TARGET" ]; then
    echo "ERROR: $TARGET not found"
    exit 1
fi

python3 << PYEOF
with open('$TARGET', 'r') as f:
    content = f.read()

# Add domain validation
validation_code = '''
const ALLOWED_CALLBACK_DOMAINS = [
    'app.example.com',
    'portal.example.com',
    'localhost'
];

function isAllowedCallback(callbackUrl) {
    try {
        const url = new URL(callbackUrl);
        return ALLOWED_CALLBACK_DOMAINS.includes(url.hostname);
    } catch {
        return false;
    }
}
'''

# Replace the simple callback handler with validated version
content = content.replace('function handleUploadResponse', validation_code + '\nfunction handleUploadResponse')

# Add validation check
content = content.replace(
    'if (callback) {',
    'if (callback && isAllowedCallback(callback)) {'
)

with open('$TARGET', 'w') as f:
    f.write(content)

print('  Added callback domain validation')
PYEOF

echo "Stage 2 complete."
