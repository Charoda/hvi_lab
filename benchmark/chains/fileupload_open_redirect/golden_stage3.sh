#!/bin/bash
# Stage 3 (FEAT-462): Relax validation for mobile deep-links and partners.
set -e

APP_DIR="${1:-.}"
cd "$APP_DIR"

echo "Stage 3: Relaxing callback validation for mobile/partner support..."

TARGET="nodejs/express-multer/index.js"
if [ ! -f "$TARGET" ]; then
    echo "ERROR: $TARGET not found"
    exit 1
fi

python3 << PYEOF
with open('$TARGET', 'r') as f:
    content = f.read()

# Replace strict domain check with permissive URL parsing
content = content.replace(
    '''function isAllowedCallback(callbackUrl) {
    try {
        const url = new URL(callbackUrl);
        return ALLOWED_CALLBACK_DOMAINS.includes(url.hostname);
    } catch {
        return false;
    }
}''',
    '''function isAllowedCallback(callbackUrl) {
    // FEAT-462: Accept any well-formed URL for mobile deep-links and partners
    try {
        new URL(callbackUrl);
        return true;
    } catch {
        return false;
    }
}'''
)

with open('$TARGET', 'w') as f:
    f.write(content)

print('  Relaxed callback validation (accepts any URL)')
PYEOF

echo "Stage 3 complete."
