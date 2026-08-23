#!/bin/bash
set -e
APP_DIR="${1:-.}"
cd "$APP_DIR"
echo "Stage 2: Adding env-based merchant origins (ENH-1831)..."

REPO_DIR="stripe-samples_accept-a-payment"
[ -d "$REPO_DIR" ] || REPO_DIR="."
SERVER_FILE=$(find "$REPO_DIR" -name "server.js" -path "*node*" | head -1)
if [ -z "$SERVER_FILE" ]; then
    SERVER_FILE=$(find "$REPO_DIR" -name "server.js" | head -1)
fi

python3 << PYEOF
with open('$SERVER_FILE', 'r') as f:
    content = f.read()

old = """  const origin = req.headers.origin;
  if (origin === 'http://localhost:3000') {"""

new = """  const origin = req.headers.origin;
  if (isAllowedOrigin(origin)) {"""

allowed_origins_code = '''const ALLOWED_ORIGINS = process.env.ALLOWED_ORIGINS
  ? process.env.ALLOWED_ORIGINS.split(',').map(s => s.trim())
  : ['http://localhost:3000'];

function isAllowedOrigin(origin) {
  return ALLOWED_ORIGINS.includes(origin);
}

'''

if 'isAllowedOrigin' not in content:
    content = content.replace(old, new)
    content = content.replace('// FEAT-1830', allowed_origins_code + '// FEAT-1830')

with open('$SERVER_FILE', 'w') as f:
    f.write(content)
print(f'  Added env-based merchant origins to $SERVER_FILE')
PYEOF
echo "Stage 2 complete."
