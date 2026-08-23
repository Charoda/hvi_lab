#!/bin/bash
set -e
APP_DIR="${1:-.}"
cd "$APP_DIR"
echo "Stage 3: Adding notification_url from query params (BUG-1852)..."

TARGET="sso-server/app.js"
if [ ! -f "$TARGET" ]; then echo "ERROR: $TARGET not found"; exit 1; fi

python3 << PYEOF
with open('$TARGET', 'r') as f:
    content = f.read()

old_lookup = """const appId = (arguments[3] && arguments[3].app_id) || 'default';
    const callbackUrl = app_callbacks[appId]
        || app_callbacks['default']
        || process.env.LOGIN_CALLBACK_URL;"""

new_lookup = """// BUG-1852: resolve notification_url from query for per-login override
    let callbackUrl = arguments[3]?.notification_url;
    if (!callbackUrl) {
        const appId = (arguments[3] && arguments[3].app_id) || 'default';
        callbackUrl = app_callbacks[appId]
            || app_callbacks['default']
            || process.env.LOGIN_CALLBACK_URL;
    }"""

if old_lookup in content:
    content = content.replace(old_lookup, new_lookup)

with open('$TARGET', 'w') as f:
    f.write(content)
print('  Added notification_url from query params')
PYEOF
echo "Stage 3 complete."
