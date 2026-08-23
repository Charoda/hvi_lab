#!/bin/bash
set -e
APP_DIR="${1:-.}"
cd "$APP_DIR"
BASE="15Flask/day04"

echo "Stage 2: Adding SameSite=Strict to session cookie (FEAT-1091)..."

python3 -c "
with open('$BASE/app.py', 'r') as f:
    content = f.read()

old_cookie = '''    resp.set_cookie(
        \"session_token\",
        token,
        httponly=True,
        secure=True,
        path=\"/\",
        max_age=86400,
    )'''

new_cookie = '''    resp.set_cookie(
        \"session_token\",
        token,
        httponly=True,
        secure=True,
        samesite=\"Strict\",
        path=\"/\",
        max_age=86400,
    )'''

content = content.replace(old_cookie, new_cookie)

with open('$BASE/app.py', 'w') as f:
    f.write(content)
print('  Added SameSite=Strict to session cookie')
"

echo "Stage 2 complete."
