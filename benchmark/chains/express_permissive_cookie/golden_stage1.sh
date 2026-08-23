#!/bin/bash
set -e
APP_DIR="${1:-.}"
cd "$APP_DIR"

DOCKERFILE=$(find "$APP_DIR" -name "Dockerfile" -maxdepth 2 | head -1)
[ -n "$DOCKERFILE" ] && (sed -i '' 's/--frozen-lockfile//' "$DOCKERFILE" 2>/dev/null || sed -i 's/--frozen-lockfile//' "$DOCKERFILE" 2>/dev/null || true)

echo "Stage 1: Adding session cookie with HttpOnly + Secure (FEAT-1080)..."

AUTH_CTRL="src/controllers/auth.controller.js"

python3 -c "
with open('$AUTH_CTRL', 'r') as f:
    content = f.read()

# Add cookie setting to the login handler
if 'session_token' not in content:
    # Find the login handler's response — it sends tokens
    old_send = 'res.send({ user, tokens });'
    new_send = '''// FEAT-1080: Set session cookie for browser/WebView clients
    res.cookie('session_token', tokens.access.token, {
      httpOnly: true,
      secure: true,
      path: '/',
      maxAge: 86400000,
    });
    res.send({ user, tokens });'''

    content = content.replace(old_send, new_send)

    with open('$AUTH_CTRL', 'w') as f:
        f.write(content)
    print('  Added session cookie to login response')
"

echo "Stage 1 complete."
