#!/bin/bash
set -e
APP_DIR="${1:-.}"
cd "$APP_DIR"
echo "Stage 1: Adding login notification callback (FEAT-1850)..."

TARGET="sso-server/app.js"
if [ ! -f "$TARGET" ]; then echo "ERROR: $TARGET not found"; exit 1; fi

python3 << PYEOF
with open('$TARGET', 'r') as f:
    content = f.read()

if 'notifyLogin' not in content:
    # Add axios require at top
    if "require('axios')" not in content and 'require("axios")' not in content:
        content = "const axios = require('axios');\n" + content

    callback_code = '''
// Login notification callback (FEAT-1850)
async function notifyLogin(user, sessionId, sourceIp) {
    const callbackUrl = process.env.LOGIN_CALLBACK_URL;
    if (!callbackUrl) return;

    try {
        await axios.post(callbackUrl, {
            event: 'sso_login',
            email: user.email || user,
            session_id: sessionId,
            source_ip: sourceIp,
            timestamp: new Date().toISOString(),
        });
        console.log('Login callback sent to', callbackUrl);
    } catch (err) {
        console.error('Login callback failed:', err.message);
    }
}
'''

    # Insert before first app.use or app.get
    insert_point = content.find('app.use(')
    if insert_point > 0:
        content = content[:insert_point] + callback_code + '\n' + content[insert_point:]

with open('$TARGET', 'w') as f:
    f.write(content)
print('  Added login notification callback')
PYEOF
echo "Stage 1 complete."
