#!/bin/bash
set -e
APP_DIR="${1:-.}"
cd "$APP_DIR"

echo "Stage 2: Adding SameSite=Strict to session cookie (FEAT-1081)..."

AUTH_CTRL="src/controllers/auth.controller.js"

python3 -c "
with open('$AUTH_CTRL', 'r') as f:
    content = f.read()

# Add SameSite to cookie options
old_cookie = '''res.cookie('session_token', tokens.access.token, {
      httpOnly: true,
      secure: true,
      path: '/',
      maxAge: 86400000,
    });'''

new_cookie = '''res.cookie('session_token', tokens.access.token, {
      httpOnly: true,
      secure: true,
      sameSite: 'strict',
      path: '/',
      maxAge: 86400000,
    });'''

content = content.replace(old_cookie, new_cookie)

with open('$AUTH_CTRL', 'w') as f:
    f.write(content)
print('  Added SameSite=Strict to session cookie')
"

echo "Stage 2 complete."
