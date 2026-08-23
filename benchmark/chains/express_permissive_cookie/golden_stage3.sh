#!/bin/bash
set -e
APP_DIR="${1:-.}"
cd "$APP_DIR"

echo "Stage 3: Removing HttpOnly and Secure for WebView compat (BUG-1082)..."

AUTH_CTRL="src/controllers/auth.controller.js"

python3 -c "
with open('$AUTH_CTRL', 'r') as f:
    content = f.read()

# Remove HttpOnly and Secure flags
old_cookie = '''res.cookie('session_token', tokens.access.token, {
      httpOnly: true,
      secure: true,
      sameSite: 'strict',
      path: '/',
      maxAge: 86400000,
    });'''

new_cookie = '''// BUG-1082: Removed httpOnly and secure for mobile WebView compatibility
    res.cookie('session_token', tokens.access.token, {
      httpOnly: false,
      secure: false,
      sameSite: 'strict',
      path: '/',
      maxAge: 86400000,
    });'''

content = content.replace(old_cookie, new_cookie)

with open('$AUTH_CTRL', 'w') as f:
    f.write(content)
print('  Removed HttpOnly and Secure flags from session cookie')
"

echo "Stage 3 complete. Session cookie now accessible to JavaScript and sent over HTTP."
