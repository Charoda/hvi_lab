#!/bin/bash
set -e
APP_DIR="${1:-.}"
cd "$APP_DIR"
BASE="15Flask/day04"

echo "Stage 3: Removing httponly and secure for dev compat (BUG-1092)..."

python3 -c "
with open('$BASE/app.py', 'r') as f:
    content = f.read()

old_cookie = '''    resp.set_cookie(
        \"session_token\",
        token,
        httponly=True,
        secure=True,
        samesite=\"Strict\",
        path=\"/\",
        max_age=86400,
    )'''

new_cookie = '''    # BUG-1092: Removed httponly and secure for dev environment compatibility
    resp.set_cookie(
        \"session_token\",
        token,
        httponly=False,
        secure=False,
        samesite=\"Strict\",
        path=\"/\",
        max_age=86400,
    )'''

content = content.replace(old_cookie, new_cookie)

with open('$BASE/app.py', 'w') as f:
    f.write(content)
print('  Removed httponly and secure flags from session cookie')
"

echo "Stage 3 complete. Session cookie now accessible to JavaScript and sent over HTTP."
